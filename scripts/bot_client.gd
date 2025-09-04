class_name BotClient
extends Node3D

enum Status { CHOOSING, MOVING }

@export var client_number: int = 2
@export var server_url: String = "http://207.154.222.143:5000"
@export var game_id: String = ""
@export var poll_interval: float = 0.5

var http_request: HTTPRequest
var player_positions: Array[Vector2i] = []
var cached_last_paths: Array[Array] = [[], [], [], []]
var current_game_state: Dictionary = {}
var is_animating: bool = false
var pending_move_callback: Callable
var move_direction: int = 0  # 0 = left, 1 = right
var has_made_move: bool = false
var client_status: Status = Status.CHOOSING

func _ready():
	# Get game ID from lobby
	game_id = get_tree().get_meta("game_id", "")
	
	# Initialize positions array (same as main client)
	player_positions = [Vector2i(0, 0), Vector2i(2, -1), Vector2i(-1, 1), Vector2i(3, 0)]
	
	# Setup HTTP request
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
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
	
	# Check if this is a move response (has "ok" field) vs game state
	if "ok" in response_data:
		if pending_move_callback.is_valid():
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
					print(f"BOT: Player {client_number} animation starting, status -> MOVING")
					# Simulate animation time then send end turn
					await get_tree().create_timer(0.5 * new_path.size()).timeout
					if client_status == Status.MOVING:  # Make sure we're still moving
						print(f"BOT: Player {client_number} animation complete, sending end_turn")
						end_turn()
	
	# Check if it's our turn and make a move (only in planning phase and choosing status)
	var current_player = state.get("playerInTurn", -1)
	if current_player == client_number - 1 and not is_animating and not pending_move_callback.is_valid():
		if state.get("phase", "planning") == "planning" and client_status == Status.CHOOSING:
			await get_tree().create_timer(0.5).timeout  # Small delay before moving
			make_bot_move()

func make_bot_move():
	var current_pos = player_positions[client_number - 1]
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
	
	# Create path from current to target position
	var path: Array[Vector2i] = [current_pos, target_pos]
	
	# Make the move
	make_move(path, _on_bot_move_response)
	
	# Toggle direction for next time
	move_direction = 1 - move_direction

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
	var request_body = {
		"player": client_number - 1
	}
	
	var url = server_url + "/games/" + game_id + "/end_turn"
	var headers = ["Content-Type: application/json"]
	
	# Reset client status to choosing
	client_status = Status.CHOOSING
	print(f"BOT: Player {client_number} status -> CHOOSING, sending end_turn request")
	
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))

func _on_bot_move_response(success: bool, response_data: Dictionary):
	if success:
		has_made_move = true
	else:
		pass

func schedule_next_poll():
	await get_tree().create_timer(poll_interval).timeout
	poll_server()
