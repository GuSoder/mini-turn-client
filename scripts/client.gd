class_name Client
extends Node3D

@export var client_number: int = 1
@export var server_url: String = "http://207.154.222.143:5000"
@export var game_id: String = ""
@export var poll_interval: float = 0.5

var http_request: HTTPRequest
var players_node: Node3D
var grid_node: Node3D
var turn_marker_node: MeshInstance3D
var path_markers_node: Node3D
var player_positions: Array[Vector2i] = []
var cached_last_paths: Array[Array] = [[], [], [], []]
var current_game_state: Dictionary = {}
var is_animating: bool = false

func _ready():
	players_node = get_node("Players")
	grid_node = get_node("Grid")
	turn_marker_node = get_node("TurnMarker")
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
		print("No game ID set")
		return
	
	var url = server_url + "/games/" + game_id + "/state"
	http_request.request(url)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code != 200:
		print("Server request failed: ", response_code)
		call_deferred("schedule_next_poll")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		print("Failed to parse JSON response")
		call_deferred("schedule_next_poll")
		return
	
	var response_data = json.data
	
	# Check if this is a move response (has "ok" field) vs game state
	if "ok" in response_data:
		print("Move response: ", response_data)
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
		print("lastPaths: ", state.lastPaths)
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
	else:
		print("ERROR: lastPaths not found in state")

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
	
	# Animate through all positions
	for i in range(1, positions.size()):
		tween.tween_property(player_node, "position", positions[i], 0.3)
	
	# Update final position after animation completes
	tween.tween_callback(func(): 
		is_animating = false
		update_player_position(player_index, state)
	)

func schedule_next_poll():
	await get_tree().create_timer(poll_interval).timeout
	poll_server()

func make_move(path: Array[Vector2i]):
	if current_game_state.get("playerInTurn", -1) != client_number - 1:
		print("Not your turn!")
		return
	
	if is_animating:
		print("Animation in progress, please wait")
		return
	
	# Convert path to server format
	var server_path = []
	for hex_pos in path:
		server_path.append({"q": hex_pos.x, "r": hex_pos.y})
	
	var request_body = {
		"player": client_number - 1,
		"path": server_path
	}
	
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
	
	print("Could not find hex node for ", hex_pos)
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
	if not turn_marker_node or not "playerInTurn" in state or not "positions" in state:
		return
	
	var current_player = state.playerInTurn
	var player_pos = state.positions[current_player]
	var hex_pos = Vector2i(player_pos.q, player_pos.r)
	
	# Position turn marker above the current player's hex
	var hex_world_pos = get_hex_node_position(hex_pos)
	turn_marker_node.position = hex_world_pos

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
	
	# Show numbered markers for each step in path (skip first position as it's current)
	for i in range(1, min(path.size(), path_markers_node.get_child_count() + 1)):
		var hex_pos = path[i]
		var hex_world_pos = get_hex_node_position(hex_pos)
		
		if hex_world_pos != Vector3.UP * 1000:
			var marker_index = i - 1  # Marker numbering starts at 0
			if marker_index < path_markers_node.get_child_count():
				var marker = path_markers_node.get_child(marker_index)
				marker.position = hex_world_pos + Vector3(0, 1, 0)  # Slightly above hex
				marker.visible = true
