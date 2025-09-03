class_name Client
extends Node3D

@export var client_number: int = 1
@export var server_url: String = "http://207.154.222.143:5000"
@export var game_id: String = ""
@export var poll_interval: float = 0.5

var http_request: HTTPRequest
var players_node: Node3D
var grid_node: Node3D
var initiative_tracker_node: Node2D
var ui_turn_marker_node: Node2D
var path_markers_node: Node3D
var player_positions: Array[Vector2i] = []
var cached_last_paths: Array[Array] = [[], [], [], []]
var current_game_state: Dictionary = {}
var is_animating: bool = false
var pending_move_callback: Callable

func _ready():
	players_node = get_node("Players")
	grid_node = get_node("Grid")
	initiative_tracker_node = get_node("InitiativeTracker")
	ui_turn_marker_node = get_node("InitiativeTracker/CharacterPanel1/TurnMarker")
	path_markers_node = get_node("PathMarkers")
	
	# Hide all path markers initially
	hide_all_path_markers()
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Get game ID from lobby
	game_id = get_tree().get_meta("game_id", "")
	
	# Initialize positions array
	player_positions = [Vector2i(0, 0), Vector2i(2, -1), Vector2i(-1, 1), Vector2i(3, 0)]
	
	# Add hex input handler
	var hex_input = preload("res://scripts/hex_input.gd").new()
	add_child(hex_input)
	
	# Start polling
	poll_server()

func poll_server():
	if game_id == "":
		return
	
	var url = server_url + "/games/" + game_id + "/state"
	http_request.request(url)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 200:
		# If we have a pending move callback, notify it of failure
		if pending_move_callback.is_valid():
			pending_move_callback.call(false, {"error": "Server request failed: " + str(response_code)})
			pending_move_callback = Callable()
		call_deferred("schedule_next_poll")
		return
	
	if result != HTTPRequest.RESULT_SUCCESS:
		# If we have a pending move callback, notify it of failure
		if pending_move_callback.is_valid():
			pending_move_callback.call(false, {"error": "HTTP request failed: " + str(result)})
			pending_move_callback = Callable()
		call_deferred("schedule_next_poll")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		# If we have a pending move callback, notify it of failure
		if pending_move_callback.is_valid():
			pending_move_callback.call(false, {"error": "Failed to parse JSON response"})
			pending_move_callback = Callable()
		call_deferred("schedule_next_poll")
		return
	
	var response_data = json.data
	
	# Check if this is a move response (has "ok" field) vs game state
	if "ok" in response_data:
		# Call pending callback if exists
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

	# Update turn marker position
	update_turn_marker_position(state)

	# Check for path changes and animate
	if "lastPaths" in state:
		for i in range(4):
			var new_path = state.lastPaths[i]
			var cached_path = cached_last_paths[i]
			
			if new_path != cached_path and len(new_path) > 1:
				# Don't update position immediately - let animation handle it
				animate_player_move(i, new_path, state)
			else:
				# No animation needed, update position directly
				update_player_position(i, state)
			
			cached_last_paths[i] = new_path.duplicate()

func animate_player_move(player_index: int, path: Array, state: Dictionary):
	var player_node = players_node.get_child(player_index)
	if not player_node:
		return
	
	# Convert hex path to world positions and animate
	var world_positions: Array[Vector3] = []
	for hex_pos in path:
		var node_pos = get_hex_node_position(Vector2i(hex_pos.q, hex_pos.r))
		world_positions.append(node_pos)
	
	if world_positions.size() > 1:
		animate_along_path(player_node, world_positions, player_index, state)

func hex_to_world(hex_pos: Vector2i) -> Vector3:
	# Convert hex coordinates (q, r) to world position
	var q = float(hex_pos.x)
	var r = float(hex_pos.y)
	
	var x = 1.7 * q + 0.85 * r
	var z = 1.5 * r
	
	return Vector3(x, 0, z)

func animate_along_path(player_node: Node3D, positions: Array[Vector3], player_index: int, state: Dictionary):
	if positions.size() < 2:
		return
	
	is_animating = true
	var tween = create_tween()
	
	# Start from first position
	player_node.position = positions[0]
	
	# Rotate to face the first destination before starting movement
	if positions.size() > 1:
		var start_pos = positions[0]
		var first_target = positions[1]
		var direction = (first_target - start_pos).normalized()
		var target_position = start_pos + direction
		player_node.look_at(target_position, Vector3.UP)
	
	# Animate through all positions
	for i in range(1, positions.size()):
		tween.tween_property(player_node, "position", positions[i], 0.3)
		
		# After reaching this position, rotate to look at next position (if not the last position)
		if i < positions.size() - 1:
			var current_index = i  # Capture the current value
			tween.tween_callback(func():
				var current_pos = positions[current_index]
				var next_pos = positions[current_index + 1]
				var direction = (next_pos - current_pos).normalized()
				var target_position = current_pos + direction
				player_node.look_at(target_position, Vector3.UP)
			)
	
	# Update final position after animation completes
	tween.tween_callback(func(): 
		is_animating = false
		update_player_position(player_index, state)
	)

func schedule_next_poll():
	await get_tree().create_timer(poll_interval).timeout
	poll_server()

func make_move(path: Array[Vector2i], callback: Callable = Callable()):
	if current_game_state.get("playerInTurn", -1) != client_number - 1:
		if callback.is_valid():
			callback.call(false, {"error": "Not your turn"})
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

func get_hex_node_position(hex_pos: Vector2i) -> Vector3:
	# Find the actual hex node in the grid and return its position
	# Grid has 10 rows (0-9), each with 10 hexes (0-9)
	# Direct mapping from hex coordinates to grid indices
	
	var row_index = hex_pos.y
	var hex_index = hex_pos.x
	
	# Clamp to valid grid bounds
	row_index = clamp(row_index, 0, 9)
	hex_index = clamp(hex_index, 0, 9)
	
	if grid_node:
		var row_node = grid_node.get_child(row_index)
		if row_node:
			var hex_node = row_node.get_child(hex_index)
			if hex_node:
				return hex_node.global_position
	
	return Vector3.UP * 1000

func update_player_position(player_index: int, state: Dictionary):
	var pos = state.positions[player_index]
	var new_hex_pos = Vector2i(pos.q, pos.r)
	player_positions[player_index] = new_hex_pos
	
	# Move player to correct world position
	var player_node = players_node.get_child(player_index)
	if player_node:
		var hex_node_pos = get_hex_node_position(new_hex_pos)
		player_node.position = hex_node_pos

func update_turn_marker_position(state: Dictionary):
	print("[TURN MARKER DEBUG] update_turn_marker_position called")
	print("[TURN MARKER DEBUG] initiative_tracker_node: ", initiative_tracker_node)
	print("[TURN MARKER DEBUG] ui_turn_marker_node: ", ui_turn_marker_node)
	print("[TURN MARKER DEBUG] playerInTurn in state: ", "playerInTurn" in state)
	
	if not initiative_tracker_node or not ui_turn_marker_node or not "playerInTurn" in state:
		print("[TURN MARKER DEBUG] Early return - missing nodes or playerInTurn")
		return
	
	var current_player = state.playerInTurn
	print("[TURN MARKER DEBUG] Current player: ", current_player)
	
	# Move the UI turn marker to the correct character panel
	# Player indices are 0-3, corresponding to CharacterPanel1-4
	var target_panel_name = "CharacterPanel" + str(current_player + 1)
	print("[TURN MARKER DEBUG] Target panel name: ", target_panel_name)
	var target_panel = initiative_tracker_node.get_node(target_panel_name)
	print("[TURN MARKER DEBUG] Target panel: ", target_panel)
	
	if target_panel:
		print("[TURN MARKER DEBUG] Current parent: ", ui_turn_marker_node.get_parent())
		# Remove turn marker from current parent
		if ui_turn_marker_node.get_parent():
			ui_turn_marker_node.get_parent().remove_child(ui_turn_marker_node)
			print("[TURN MARKER DEBUG] Removed from parent")
		
		# Add to new parent
		target_panel.add_child(ui_turn_marker_node)
		print("[TURN MARKER DEBUG] Added to new parent: ", target_panel)
		
		# Set local position and scale as requested
		ui_turn_marker_node.position = Vector2(0, 0)
		ui_turn_marker_node.scale = Vector2(1, 1)
		print("[TURN MARKER DEBUG] Set position and scale")
	else:
		print("[TURN MARKER DEBUG] Target panel not found!")

func hide_all_path_markers():
	if not path_markers_node:
		return
	
	for i in range(path_markers_node.get_child_count()):
		var marker = path_markers_node.get_child(i)
		marker.visible = false

func show_path_markers(path: Array[Vector2i]):
	if not path_markers_node:
		return
	
	hide_all_path_markers()
	
	# Show numbered markers for each step in path
	for i in range(0, min(path.size(), path_markers_node.get_child_count() + 1)):
		var hex_pos = path[i]
		var hex_world_pos = get_hex_node_position(hex_pos)
		
		if hex_world_pos != Vector3.UP * 1000:
			var marker_index = i
			if marker_index < path_markers_node.get_child_count():
				var marker = path_markers_node.get_child(marker_index)
				marker.position = hex_world_pos
				marker.visible = true
