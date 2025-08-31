class_name Client
extends Node3D

@export var client_number: int = 1
@export var server_url: String = "http://localhost:5000"
@export var game_id: String = ""
@export var poll_interval: float = 0.5

var http_request: HTTPRequest
var players_node: Node3D
var grid_node: Node3D
var player_positions: Array[Vector2i] = []
var cached_last_paths: Array[Array] = [[], [], [], []]
var current_game_state: Dictionary = {}
var is_animating: bool = false

func _ready():
	players_node = get_node("Players")
	grid_node = get_node("Grid")
	
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
	
	var new_state = json.data
	process_game_state(new_state)
	call_deferred("schedule_next_poll")

func process_game_state(state: Dictionary):
	current_game_state = state
	
	# Check for path changes and animate
	for i in range(4):
		var new_path = state.lastPaths[i]
		var cached_path = cached_last_paths[i]
		
		if new_path != cached_path and len(new_path) > 1:
			animate_player_move(i, new_path)
		
		cached_last_paths[i] = new_path.duplicate()
	
	# Update positions
	for i in range(4):
		var pos = state.positions[i]
		player_positions[i] = Vector2i(pos.q, pos.r)

func animate_player_move(player_index: int, path: Array):
	var player_node = players_node.get_child(player_index)
	if not player_node:
		return
	
	# Convert hex path to world positions and animate
	var world_positions: Array[Vector3] = []
	for hex_pos in path:
		world_positions.append(hex_to_world(Vector2i(hex_pos.q, hex_pos.r)))
	
	animate_along_path(player_node, world_positions)

func hex_to_world(hex_pos: Vector2i) -> Vector3:
	# Convert hex coordinates (q, r) to world position
	var q = float(hex_pos.x)
	var r = float(hex_pos.y)
	
	var x = 1.7 * q + 0.85 * r
	var z = 1.5 * r
	
	return Vector3(x, 1, z)

func animate_along_path(player_node: Node3D, positions: Array[Vector3]):
	if positions.size() < 2:
		return
	
	is_animating = true
	var tween = create_tween()
	
	for i in range(1, positions.size()):
		tween.tween_property(player_node, "position", positions[i], 0.3)
	
	tween.tween_callback(func(): is_animating = false)

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
