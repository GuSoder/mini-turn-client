class_name BotClient
extends Node3D

enum Status { CHOOSING, MOVING }
enum PathStrategy { PONG, PATROL, ATTACK }

@export var client_number: int = 2
@export var server_url: String = "http://207.154.222.143:5000"
@export var game_id: String = ""
@export var poll_interval: float = 0.5
@export var path_strategy: PathStrategy = PathStrategy.PONG
@export var patrol_point_1: Vector2i = Vector2i(2, 2)
@export var patrol_point_2: Vector2i = Vector2i(6, 6)
@export var attack_target: int = 2
@export var alignment: String = "friend"

var http_request: HTTPRequest
var player_positions: Array[Vector2i] = []
var cached_last_paths: Array[Array] = [[], [], [], []]
var current_game_state: Dictionary = {}
var is_animating: bool = false
var pending_move_callback: Callable
var move_direction: int = 0  # 0 = left, 1 = right
var has_made_move: bool = false
var current_patrol_target: int = 0  # 0 = patrol_point_1, 1 = patrol_point_2
var target_patrol_point: Vector2i  # Current target point we're heading to
var client_status: Status = Status.CHOOSING
var end_turn_retry_count: int = 0
var end_turn_timeout_timer: Timer
var is_end_turn_pending: bool = false
var is_attacking: bool = false
var is_attack_request_pending: bool = false
var attack_retry_count: int = 0
var attack_timeout_timer: Timer

func _ready():
	# Get game ID from lobby
	game_id = get_tree().get_meta("game_id", "")
	
	# Initialize positions array (same as main client)
	player_positions = [Vector2i(0, 0), Vector2i(2, -1), Vector2i(-1, 1), Vector2i(3, 0)]
	
	# Initialize patrol target
	target_patrol_point = patrol_point_1
	
	# Setup HTTP request
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Setup end turn timeout timer
	end_turn_timeout_timer = Timer.new()
	add_child(end_turn_timeout_timer)
	end_turn_timeout_timer.wait_time = 0.25  # 250ms timeout
	end_turn_timeout_timer.one_shot = true
	end_turn_timeout_timer.timeout.connect(_on_end_turn_timeout)
	
	# Setup attack timeout timer
	attack_timeout_timer = Timer.new()
	add_child(attack_timeout_timer)
	attack_timeout_timer.wait_time = 0.25  # 250ms timeout
	attack_timeout_timer.one_shot = true
	attack_timeout_timer.timeout.connect(_on_attack_timeout)
	
	# Start polling
	poll_server()

func poll_server():
	if game_id == "":
		return
	
	var url = server_url + "/games/" + game_id + "/state"
	http_request.request(url)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 200:
		if pending_move_callback.is_valid():
			pending_move_callback.call(false, {"error": "Server request failed: " + str(response_code)})
			pending_move_callback = Callable()
		call_deferred("schedule_next_poll")
		return
	
	if result != HTTPRequest.RESULT_SUCCESS:
		if pending_move_callback.is_valid():
			pending_move_callback.call(false, {"error": "HTTP request failed: " + str(result)})
			pending_move_callback = Callable()
		call_deferred("schedule_next_poll")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		if pending_move_callback.is_valid():
			pending_move_callback.call(false, {"error": "Failed to parse JSON response"})
			pending_move_callback = Callable()
		call_deferred("schedule_next_poll")
		return
	
	var response_data = json.data
	
	# Check if this is a move/end_turn/attack response (has "ok" field) vs game state
	if "ok" in response_data:
		# Handle attack response
		if is_attack_request_pending:
			is_attack_request_pending = false
			attack_retry_count = 0
			attack_timeout_timer.stop()
			if response_data.get("ok", false):
				print("BOT: Attack confirmed by server, now sending end_turn")
				is_attacking = false
				send_end_turn_request()
			else:
				print("BOT: Attack failed: " + str(response_data.get("error", "Unknown error")))
				# Reset attack state on failure
				is_attacking = false
		# Handle end_turn response
		elif is_end_turn_pending:
			is_end_turn_pending = false
			end_turn_retry_count = 0
			end_turn_timeout_timer.stop()
			if response_data.get("ok", false):
				pass  # Success
			else:
				pass  # Failed but bot doesn't need to report it
		# Call pending move callback if exists
		elif pending_move_callback.is_valid():
			pending_move_callback.call(response_data.get("ok", false), response_data)
			pending_move_callback = Callable()
		# Don't process as game state, just continue polling
	else:
		# This is game state data
		process_game_state(response_data)
	
	call_deferred("schedule_next_poll")

func process_game_state(state: Dictionary):
	current_game_state = state
	
	# Handle phase changes - reset to choosing if server is back in planning
	if state.get("phase", "planning") == "planning" and client_status == Status.MOVING:
		client_status = Status.CHOOSING
		# Reset attack state when new turn begins
		is_attacking = false
		
		# Deactivate animations for all players when returning to planning phase
		for i in range(4):
			deactivate_player_animations(i)
	
	# Update player positions from server state
	if "positions" in state:
		for i in range(4):
			if i < state.positions.size():
				var pos = state.positions[i]
				player_positions[i] = Vector2i(pos.q, pos.r)
	
	# Check for path changes and handle animation timing
	if "lastPaths" in state:
		for i in range(4):
			var new_path = state.lastPaths[i]
			var cached_path = cached_last_paths[i]
			
			if new_path != cached_path:
				cached_last_paths[i] = new_path.duplicate()
				# If this is our player and we're in moving phase, simulate animation
				if i == client_number - 1 and state.get("phase", "planning") == "moving":
					client_status = Status.MOVING
					print("BOT: Player " + str(client_number) + " animation starting, status -> MOVING")
				
				# Activate animations when any player starts moving
				if state.get("phase", "planning") == "moving":
					activate_player_animations(i)
					# Simulate animation time then check for attack
					await get_tree().create_timer(0.5 * new_path.size()).timeout
					if client_status == Status.MOVING:  # Make sure we're still moving
						# Deactivate animations when bot finishes moving
						deactivate_player_animations(i)
						
						# For attack strategy, check if we're now adjacent to target after animation
						if path_strategy == PathStrategy.ATTACK:
							var target_player_index = attack_target - 1
							if target_player_index >= 0 and target_player_index < 4 and target_player_index != client_number - 1:
								var current_pos = player_positions[client_number - 1]
								var target_pos = player_positions[target_player_index]
								
								if is_adjacent_to_target(current_pos, target_pos):
									# Set attack state and send attack immediately while in MOVING phase
									is_attacking = true
									print("BOT: Player " + str(client_number) + " animation complete, adjacent to target, sending attack")
									send_attack_request()
									return  # Don't send end_turn yet, attack response will handle it
						
						print("BOT: Player " + str(client_number) + " animation complete, sending end_turn")
						end_turn()
	
	# Check if it's our turn and make a move (only in planning phase and choosing status)
	var current_player = state.get("playerInTurn", -1)
	if current_player == client_number - 1 and not is_animating and not pending_move_callback.is_valid():
		if state.get("phase", "planning") == "planning" and client_status == Status.CHOOSING:
			make_bot_move()

func make_bot_move():
	var current_pos = player_positions[client_number - 1]
	var path: Array[Vector2i]
	
	match path_strategy:
		PathStrategy.PONG:
			path = make_pong_move(current_pos)
		PathStrategy.PATROL:
			path = make_patrol_move(current_pos)
		PathStrategy.ATTACK:
			path = make_attack_move(current_pos)
		_:
			path = [current_pos]  # Fallback: stay in place
	
	# Make the move
	make_move(path, _on_bot_move_response)

func make_pong_move(current_pos: Vector2i) -> Array[Vector2i]:
	var target_pos: Vector2i
	
	# Alternate between moving left and right
	if move_direction == 0:  # Move left
		target_pos = Vector2i(current_pos.x - 1, current_pos.y)
	else:  # Move right
		target_pos = Vector2i(current_pos.x + 1, current_pos.y)
	
	# Ensure target position is within bounds (0-9 for both x and y)
	target_pos.x = clamp(target_pos.x, 0, 9)
	target_pos.y = clamp(target_pos.y, 0, 9)
	
	# Check if target position is occupied by another player
	var is_occupied = false
	for i in range(4):
		if i != client_number - 1 and player_positions[i] == target_pos:
			is_occupied = true
			break
	
	# If occupied or can't move in desired direction, try the opposite direction
	if is_occupied or target_pos == current_pos:
		move_direction = 1 - move_direction  # Flip direction
		if move_direction == 0:  # Move left
			target_pos = Vector2i(current_pos.x - 1, current_pos.y)
		else:  # Move right  
			target_pos = Vector2i(current_pos.x + 1, current_pos.y)
		target_pos.x = clamp(target_pos.x, 0, 9)
		target_pos.y = clamp(target_pos.y, 0, 9)
		
		# Check again if new target is occupied
		is_occupied = false
		for i in range(4):
			if i != client_number - 1 and player_positions[i] == target_pos:
				is_occupied = true
				break
	
	# If still can't move, try staying in place (just move to current position)
	if is_occupied or target_pos == current_pos:
		target_pos = current_pos
	
	# Toggle direction for next time
	move_direction = 1 - move_direction
	
	return [current_pos, target_pos]

func make_patrol_move(current_pos: Vector2i) -> Array[Vector2i]:
	# Check if we've reached the current target patrol point
	if current_pos == target_patrol_point:
		# Toggle to the other patrol point
		if target_patrol_point == patrol_point_1:
			target_patrol_point = patrol_point_2
		else:
			target_patrol_point = patrol_point_1
		print("BOT: Player " + str(client_number) + " reached patrol point, switching target to " + str(target_patrol_point))
	
	# Get PathFinder from main client (assuming it exists)
	var main_client = get_parent().get_parent()  # Bots -> Client
	var path_finder = main_client.get_node("PathFinder") as PathFinder
	
	if path_finder:
		# Set blocked hexes (other player positions, excluding self)
		var blocked_hexes: Array[Vector2i] = []
		for i in range(4):
			if i != client_number - 1:
				blocked_hexes.append(player_positions[i])
		
		path_finder.set_blocked_hexes(blocked_hexes)
		
		# Get full path from current position to target patrol point
		var full_path = path_finder.get_full_path(current_pos, target_patrol_point)
		
		if full_path.size() > 1:
			# Take up to 5 steps from the full path (including current position)
			var steps_to_take = min(5, full_path.size() - 1)  # -1 because we don't count current pos twice
			var move_path: Array[Vector2i] = []
			
			for i in range(steps_to_take + 1):  # +1 to include current position
				move_path.append(full_path[i])
			
			print("BOT: Player " + str(client_number) + " taking " + str(steps_to_take) + " steps toward " + str(target_patrol_point))
			return move_path
		else:
			# If no path found or already at target, stay in place
			return [current_pos]
	else:
		# Fallback: simple move towards target
		return make_simple_move_towards(current_pos, target_patrol_point)

func make_simple_move_towards(current_pos: Vector2i, target_pos: Vector2i) -> Array[Vector2i]:
	# Simple movement towards target (one step at a time)
	var diff = target_pos - current_pos
	var next_pos = current_pos
	
	# Move one step in the direction with the largest difference
	if abs(diff.x) >= abs(diff.y):
		if diff.x > 0:
			next_pos.x += 1
		elif diff.x < 0:
			next_pos.x -= 1
	else:
		if diff.y > 0:
			next_pos.y += 1
		elif diff.y < 0:
			next_pos.y -= 1
	
	# Ensure within bounds
	next_pos.x = clamp(next_pos.x, 0, 9)
	next_pos.y = clamp(next_pos.y, 0, 9)
	
	# Check if position is occupied by another player
	for i in range(4):
		if i != client_number - 1 and player_positions[i] == next_pos:
			# Position occupied, stay in place
			return [current_pos]
	
	return [current_pos, next_pos]

func is_adjacent_to_target(current_pos: Vector2i, target_pos: Vector2i) -> bool:
	# Check if positions are adjacent in hex grid (distance <= 1)
	var diff = target_pos - current_pos
	return abs(diff.x) <= 1 and abs(diff.y) <= 1 and abs(diff.x - diff.y) <= 1

func make_simple_move_towards_adjacent(current_pos: Vector2i, target_pos: Vector2i) -> Array[Vector2i]:
	# Simple movement towards target but not onto target
	var diff = target_pos - current_pos
	var next_pos = current_pos
	
	# If already adjacent, don't move
	if is_adjacent_to_target(current_pos, target_pos):
		return [current_pos]
	
	# Move one step in the direction with the largest difference
	if abs(diff.x) >= abs(diff.y):
		if diff.x > 0:
			next_pos.x += 1
		elif diff.x < 0:
			next_pos.x -= 1
	else:
		if diff.y > 0:
			next_pos.y += 1
		elif diff.y < 0:
			next_pos.y -= 1
	
	# Ensure within bounds
	next_pos.x = clamp(next_pos.x, 0, 9)
	next_pos.y = clamp(next_pos.y, 0, 9)
	
	# Check if position is occupied by another player
	for i in range(4):
		if i != client_number - 1 and player_positions[i] == next_pos:
			# Position occupied, stay in place
			return [current_pos]
	
	# Don't move onto the target
	if next_pos == target_pos:
		return [current_pos]
	
	return [current_pos, next_pos]

func make_attack_move(current_pos: Vector2i) -> Array[Vector2i]:
	# Convert attack_target from 1-4 to 0-3 index
	var target_player_index = attack_target - 1
	
	# Validate target player index
	if target_player_index < 0 or target_player_index >= 4 or target_player_index == client_number - 1:
		# Invalid target or trying to attack self, stay in place
		return [current_pos]
	
	var target_pos = player_positions[target_player_index]
	
	# Check if we're already adjacent to the target
	if is_adjacent_to_target(current_pos, target_pos):
		# Already adjacent, stay in place (attack will happen in end_turn)
		print("BOT: Player " + str(client_number) + " already adjacent to target player " + str(attack_target) + ", staying in place")
		return [current_pos]
	
	# Get PathFinder from main client
	var main_client = get_parent().get_parent()  # Bots -> Client
	var path_finder = main_client.get_node("PathFinder") as PathFinder
	
	if path_finder:
		# Set blocked hexes (all other player positions, including target)
		var blocked_hexes: Array[Vector2i] = []
		for i in range(4):
			if i != client_number - 1:
				blocked_hexes.append(player_positions[i])
		
		path_finder.set_blocked_hexes(blocked_hexes)
		
		# Get full path from current position to target player
		var full_path = path_finder.get_full_path(current_pos, target_pos)
		
		if full_path.size() > 2:  # Need at least current + intermediate + target
			# Remove the target position from the end of the path
			# Stop one hex before the target (adjacent)
			var attack_path = full_path.slice(0, full_path.size() - 1)
			
			# Take up to 5 steps from the path (including current position)
			var steps_to_take = min(5, attack_path.size() - 1)  # -1 because we don't count current pos twice
			var move_path: Array[Vector2i] = []
			
			for i in range(steps_to_take + 1):  # +1 to include current position
				move_path.append(attack_path[i])
			
			print("BOT: Player " + str(client_number) + " moving toward player " + str(attack_target) + ", taking " + str(steps_to_take) + " steps")
			return move_path
		else:
			# If no valid path found, try simple move towards target (but not onto target)
			return make_simple_move_towards_adjacent(current_pos, target_pos)
	else:
		# Fallback: simple move towards target (but not onto target)
		return make_simple_move_towards_adjacent(current_pos, target_pos)

func make_move(path: Array[Vector2i], callback: Callable = Callable()):
	if current_game_state.get("playerInTurn", -1) != client_number - 1:
		if callback.is_valid():
			callback.call(false, {"error": "Not your turn"})
		return
	
	# Check if server is in planning phase
	if current_game_state.get("phase", "planning") != "planning":
		if callback.is_valid():
			callback.call(false, {"error": "Not in planning phase"})
		return
	
	# Check if client is in choosing status
	if client_status != Status.CHOOSING:
		if callback.is_valid():
			callback.call(false, {"error": "Currently moving"})
		return
	
	if is_animating:
		if callback.is_valid():
			callback.call(false, {"error": "Animation in progress"})
		return
	
	# Convert path to server format
	var server_path = []
	for hex_pos in path:
		server_path.append({"q": hex_pos.x, "r": hex_pos.y})
	
	var request_body = {
		"player": client_number - 1,
		"path": server_path
	}
	
	# Store callback for when response comes back
	pending_move_callback = callback
	
	var url = server_url + "/games/" + game_id + "/move"
	var headers = ["Content-Type: application/json"]
	
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))

func end_turn():
	if is_end_turn_pending:
		return  # Already have an end turn request pending
	
	# Send end turn directly (attack is handled separately during MOVING phase)
	send_end_turn_request()

func send_attack_request():
	var target_player_index = attack_target - 1
	var request_body = {
		"attacker": client_number - 1,
		"target": target_player_index
	}
	
	var url = server_url + "/games/" + game_id + "/attack"
	var headers = ["Content-Type: application/json"]
	
	is_attack_request_pending = true
	attack_retry_count = 0
	attack_timeout_timer.start()
	print("BOT: Player " + str(client_number) + " sending attack request against player " + str(attack_target) + " (attempt 1/10)")
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))

func send_end_turn_request():
	var request_body = {
		"player": client_number - 1
	}
	
	var url = server_url + "/games/" + game_id + "/end_turn"
	var headers = ["Content-Type: application/json"]
	
	# Reset client status to choosing
	client_status = Status.CHOOSING
	
	# Setup retry tracking
	is_end_turn_pending = true
	end_turn_retry_count = 0
	end_turn_timeout_timer.start()
	
	print("BOT: Player " + str(client_number) + " status -> CHOOSING, sending end_turn request (attempt 1/10)")
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))

func _on_end_turn_timeout():
	end_turn_retry_count += 1
	
	if end_turn_retry_count < 10:
		print("BOT: End turn request timed out - retrying (attempt " + str(end_turn_retry_count + 1) + "/10)...")
		end_turn_timeout_timer.start()  # Start timer for next attempt
		
		var request_body = {
			"player": client_number - 1
		}
		var url = server_url + "/games/" + game_id + "/end_turn"
		var headers = ["Content-Type: application/json"]
		
		http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))
	else:
		print("BOT: End turn request failed after 10 attempts - giving up")
		is_end_turn_pending = false
		end_turn_retry_count = 0

func _on_attack_timeout():
	attack_retry_count += 1
	
	if attack_retry_count < 10:
		print("BOT: Attack request timed out - retrying (attempt " + str(attack_retry_count + 1) + "/10)...")
		attack_timeout_timer.start()  # Start timer for next attempt
		
		var target_player_index = attack_target - 1
		var request_body = {
			"attacker": client_number - 1,
			"target": target_player_index
		}
		var url = server_url + "/games/" + game_id + "/attack"
		var headers = ["Content-Type: application/json"]
		
		http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))
	else:
		print("BOT: Attack request failed after 10 attempts - giving up")
		is_attack_request_pending = false
		attack_retry_count = 0
		# Reset attack state and continue to end turn
		is_attacking = false
		send_end_turn_request()

func _on_bot_move_response(success: bool, response_data: Dictionary):
	if success:
		has_made_move = true
	else:
		pass

func schedule_next_poll():
	await get_tree().create_timer(poll_interval).timeout
	poll_server()

func activate_player_animations(player_index: int):
	var players_node = get_parent().get_node("Players")
	if not players_node:
		return

	var player_node = _get_player_node_for_animations(player_index, players_node)
	if player_node:
		var proc_anim = player_node.get_node("ProcAnim")
		if proc_anim and proc_anim.has_method("activate_swings"):
			proc_anim.activate_swings()

func deactivate_player_animations(player_index: int):
	var players_node = get_parent().get_node("Players")
	if not players_node:
		return

	var player_node = _get_player_node_for_animations(player_index, players_node)
	if player_node:
		var proc_anim = player_node.get_node("ProcAnim")
		if proc_anim and proc_anim.has_method("deactivate_swings"):
			proc_anim.deactivate_swings()

func _get_player_node_for_animations(player_index: int, players_node: Node3D) -> Node3D:
	# Check if we're in campaign overworld mode
	var campaign_manager = get_parent().get_node_or_null("CampaignManager")
	if campaign_manager and campaign_manager.current_state == campaign_manager.CampaignState.OVERWORLD:
		# In overworld mode, all party heroes are children of Player1
		var player1 = players_node.get_child(0)  # Player1
		if player1 and player1.get_child_count() > (player_index + 2):
			return player1.get_child(player_index + 2)  # PartyHero1, PartyHero2, etc. (skip Capsule and Chevron)
	else:
		# In regular mode, get the player directly
		if player_index < players_node.get_child_count():
			return players_node.get_child(player_index)

	return null
