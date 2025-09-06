class_name HexInput
extends Node3D

signal hex_clicked(hex_pos: Vector2i)

var client: Client
var camera: Camera3D
var current_path: Array[Vector2i] = []
var is_selecting_path: bool = false
var hover_mark: MeshInstance3D
var target_ring: MeshInstance3D
var is_move_pending: bool = false
var move_timeout_timer: Timer
var move_retry_count: int = 0
var current_move_path: Array[Vector2i] = []

func _ready():
	client = get_parent() as Client
	camera = get_viewport().get_camera_3d()
	hover_mark = client.get_node("HoverMark")
	target_ring = client.get_node("TargetRing")
	
	# Initially hide the target ring
	target_ring.visible = false
	
	# Set up timeout timer for move requests
	move_timeout_timer = Timer.new()
	move_timeout_timer.wait_time = 0.25  # 250ms timeout
	move_timeout_timer.one_shot = true
	move_timeout_timer.timeout.connect(_on_move_timeout)
	add_child(move_timeout_timer)


func handle_mouse_click(screen_pos: Vector2):
	if not camera:
		return
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var hex_pos = get_hex_coordinates_from_node(result.collider)
		handle_hex_click(hex_pos)

func world_to_hex(world_pos: Vector3) -> Vector2i:
	# Convert world position back to hex coordinates
	var x = world_pos.x
	var z = world_pos.z
	
	var q = (x / 1.7) - (z / 2.55)
	var r = z / 1.5
	
	return Vector2i(round(q), round(r))

func handle_hex_click(hex_pos: Vector2i):
	if not client:
		return
	
	var player_index = client.client_number - 1
	var current_pos = client.player_positions[player_index]
	
	if not is_selecting_path:
		# Start new path - auto-add current position and then the clicked hex if valid
		current_path = [current_pos]
		is_selecting_path = true
		print("Started path selection from ", current_pos)
		
		# If clicked hex is not current position and is adjacent, add it to path or attack
		if hex_pos != current_pos and is_adjacent_hex_by_distance(current_pos, hex_pos):
			var target_player = get_player_at_hex(hex_pos)
			if target_player != -1:
				# Clicking on occupied hex = set attack target and submit move immediately
				print("Will attack player ", target_player, " at ", hex_pos, " after move")
				client.is_attacking = true
				client.attack_target = target_player
				is_selecting_path = false
				client.hide_all_path_markers()
				if not is_move_pending:
					is_move_pending = true
					move_retry_count = 0
					current_move_path = [current_pos]  # Single hex path for attack
					print("Submitting move for attack (attempt 1/10)...")
					move_timeout_timer.start()
					client.make_move([current_pos], _on_move_response)
			elif hex_pos not in current_path:
				current_path.append(hex_pos)
				print("Extended path to ", hex_pos, " (length: ", current_path.size(), ")")
				client.show_path_markers(current_path)
			else:
				print("Hex ", hex_pos, " is already in path")
		elif hex_pos != current_pos:
			# First click is not adjacent - try pathfinding
			var pathfinding_result = try_pathfind_to_hex(current_pos, hex_pos)
			if pathfinding_result.size() > 1:  # Need at least start + one more hex
				# Limit to 10 steps total
				var steps_to_add = min(10, pathfinding_result.size())
				current_path = []
				for i in range(steps_to_add):
					current_path.append(pathfinding_result[i])
				print("Used pathfinding for initial path to ", hex_pos, " (length: ", current_path.size(), ")")
				client.show_path_markers(current_path)
			else:
				print("No path found from current position. Clicked: ", hex_pos, " Current: ", current_pos)
	else:
		# Continue or end path
		if hex_pos == current_pos and current_path.size() > 1:
			# Clicked back to start, cancel path
			current_path.clear()
			is_selecting_path = false
			print("Cancelled path selection")
			client.hide_all_path_markers()
		elif is_adjacent_to_last_in_path(hex_pos):
			var target_player = get_player_at_hex(hex_pos)
			if target_player != -1:
				# Clicking on occupied hex = set attack target and submit move
				print("Will attack player ", target_player, " at ", hex_pos, " after move")
				client.is_attacking = true
				client.attack_target = target_player
				is_selecting_path = false
				var attack_path = current_path.duplicate()
				current_path.clear()
				client.hide_all_path_markers()
				if not is_move_pending:
					is_move_pending = true
					move_retry_count = 0
					current_move_path = attack_path
					print("Submitting move for attack (attempt 1/10)...")
					move_timeout_timer.start()
					client.make_move(attack_path, _on_move_response)
			elif hex_pos not in current_path:
				current_path.append(hex_pos)
				print("Extended path to ", hex_pos, " (length: ", current_path.size(), ")")
				client.show_path_markers(current_path)
			else:
				print("Hex ", hex_pos, " is already in path")
		else:
			# Not adjacent - try pathfinding to fill in the gaps
			var last_pos = current_path[-1] if current_path.size() > 0 else Vector2i(-1, -1)
			var pathfinding_result = try_pathfind_to_hex(last_pos, hex_pos)
			if pathfinding_result.size() > 0:
				# Found a path - add the steps (excluding the starting position which is already in path)
				for i in range(1, pathfinding_result.size()):
					if current_path.size() >= 10:  # Limit to 10 total steps
						break
					current_path.append(pathfinding_result[i])
				print("Used pathfinding to extend path to ", hex_pos, " (new length: ", current_path.size(), ")")
				client.show_path_markers(current_path)
			else:
				var diff = hex_pos - last_pos
				print("No path found. Last: ", last_pos, " Clicked: ", hex_pos, " Diff: ", diff)

func is_adjacent_to_last_in_path(hex_pos: Vector2i) -> bool:
	if current_path.is_empty():
		return false
	
	var last_pos = current_path[-1]
	return is_adjacent_hex_by_distance(last_pos, hex_pos)

func is_hex_occupied_by_player(hex_pos: Vector2i) -> bool:
	if not client or not client.player_positions:
		return false
	
	# Check if any player is standing on this hex
	for player_pos in client.player_positions:
		if player_pos == hex_pos:
			return true
	return false

func get_player_at_hex(hex_pos: Vector2i) -> int:
	if not client or not client.player_positions:
		return -1
	
	# Return player index (0-3) occupying this hex, or -1 if none
	for i in range(client.player_positions.size()):
		if client.player_positions[i] == hex_pos:
			return i
	return -1

func is_adjacent_hex_by_distance(pos1: Vector2i, pos2: Vector2i) -> bool:
	# Get actual 3D positions of both hex nodes
	var pos1_world = client.get_hex_node_position(pos1)
	var pos2_world = client.get_hex_node_position(pos2)

	# Calculate 3D distance between hex centers
	var distance = pos1_world.distance_to(pos2_world)

	# Adjacent hexes are 1.7 units apart, use 1.8 as threshold
	return distance <= 1.8

func get_hex_coordinates_from_node(hex_node: Node3D) -> Vector2i:
	# Find the hex coordinates by looking up the node in the grid hierarchy
	var grid_node = client.grid_node
	
	if not grid_node or not hex_node:
		return Vector2i(-1, -1)
	
	# Find which row and hex index this node is at
	for row_index in range(grid_node.get_child_count()):
		var row_node = grid_node.get_child(row_index)
		for hex_index in range(row_node.get_child_count()):
			var grid_hex_node = row_node.get_child(hex_index)
			if grid_hex_node == hex_node:
				return Vector2i(hex_index, row_index)
	
	print("Could not find hex coordinates for node")
	return Vector2i(-1, -1)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if is_selecting_path and current_path.size() > 1 and not is_move_pending:
			is_move_pending = true
			move_retry_count = 0
			current_move_path = current_path.duplicate()  # Save path for retries
			print("Submitting move (attempt 1/10)...")
			move_timeout_timer.start()  # Start timeout timer
			client.make_move(current_path, _on_move_response)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_move_pending:
			# Cancel pending move
			move_timeout_timer.stop()
			is_move_pending = false
			move_retry_count = 0
			current_move_path.clear()
			print("Move cancelled by player")
		elif is_selecting_path:
			# Cancel path selection
			current_path.clear()
			is_selecting_path = false
			client.hide_all_path_markers()
			print("Path selection cancelled")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not is_move_pending:  # Don't allow new selections while move is pending
			handle_mouse_click(event.position)
	elif event is InputEventMouseMotion:
		handle_mouse_hover(event.position)

func handle_mouse_hover(screen_pos: Vector2):
	if not camera or not hover_mark or not target_ring:
		return
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider:
		# Get the hex node position directly from the collision body
		var hex_node = result.collider
		var hex_world_pos = hex_node.global_position
		var hex_pos = get_hex_coordinates_from_node(hex_node)
		
		# Check if this hex is occupied by a player
		if is_hex_occupied_by_player(hex_pos):
			# Show TargetRing, hide HoverMark
			target_ring.position = hex_world_pos
			target_ring.visible = true
			hover_mark.visible = false
		else:
			# Show HoverMark, hide TargetRing
			hover_mark.position = hex_world_pos
			hover_mark.visible = true
			target_ring.visible = false
	else:
		# No intersection - hide both markers
		hover_mark.visible = false
		target_ring.visible = false

func _on_move_response(success: bool, response_data: Dictionary):
	move_timeout_timer.stop()  # Stop timeout timer since we got response
	is_move_pending = false
	move_retry_count = 0
	current_move_path.clear()
	
	if success:
		print("Move confirmed by server!")
		# Clear path and markers only after server confirmation
		current_path.clear()
		is_selecting_path = false
		client.hide_all_path_markers()
	else:
		print("Move failed: ", response_data.get("error", "Unknown error"))
		# Keep path and markers visible so player can try again

func _on_move_timeout():
	move_retry_count += 1
	
	if move_retry_count < 10:
		print("Move request timed out - retrying (attempt ", move_retry_count + 1, "/10)...")
		move_timeout_timer.start()  # Start timer for next attempt
		client.make_move(current_move_path, _on_move_response)
	else:
		print("Move request failed after 10 attempts - giving up")
		is_move_pending = false
		move_retry_count = 0
		current_move_path.clear()
		# Keep path and markers visible so player can try again manually

func hex_to_world(hex_pos: Vector2i) -> Vector3:
	# Convert hex coordinates (q, r) to world position
	var q = float(hex_pos.x)
	var r = float(hex_pos.y)
	
	var x = 1.7 * q + 0.85 * r
	var z = 1.5 * r
	
	return Vector3(x, 0, z)

func try_pathfind_to_hex(start_pos: Vector2i, target_pos: Vector2i) -> Array[Vector2i]:
	# Get PathFinder from client
	var path_finder = client.get_node("PathFinder") as PathFinder
	if not path_finder:
		return []
	
	# Set up blocked hexes (other players, excluding current player)
	var blocked_hexes: Array[Vector2i] = []
	var player_index = client.client_number - 1
	for i in range(client.player_positions.size()):
		if i != player_index:
			blocked_hexes.append(client.player_positions[i])
	
	path_finder.set_blocked_hexes(blocked_hexes)
	
	# Get path using A*
	return path_finder.get_full_path(start_pos, target_pos)
