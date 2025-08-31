extends Node3D

var http_request: HTTPRequest
var server_url: String = "http://localhost:5000"
var current_game_id: String = ""

func _ready():
	print("Lobby - Press C to create game, then 1-4 to join as player")
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_C:
				create_game()
			KEY_1:
				join_as_player(1)
			KEY_2:
				join_as_player(2)
			KEY_3:
				join_as_player(3)
			KEY_4:
				join_as_player(4)

func create_game():
	print("Creating new game...")
	var url = server_url + "/games"
	http_request.request(url, [], HTTPClient.METHOD_POST)

func join_as_player(player_num: int):
	if current_game_id == "":
		print("No game created yet! Press C to create a game first.")
		return
	
	print("Joining as Player ", player_num)
	var scene_path = "res://scenes/client" + str(player_num) + ".tscn"
	
	# Store game ID in global autoload or pass it somehow
	# For now, we'll use a simple approach with a global variable
	get_tree().set_meta("game_id", current_game_id)
	get_tree().change_scene_to_file(scene_path)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		
		if parse_result == OK and "gameId" in json.data:
			current_game_id = json.data.gameId
			print("Game created! Game ID: ", current_game_id)
			print("Now press 1, 2, 3, or 4 to join as a player")
	else:
		print("Failed to create game. Response code: ", response_code)
