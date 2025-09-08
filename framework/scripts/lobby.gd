extends Node3D

var http_request: HTTPRequest
var server_url: String = "http://207.154.222.143:5000"
var current_game_id: String = ""
var available_games: Array = []
var info_box: Label

func _ready():
	info_box = get_node("info_box")
	update_info("Lobby - Press C to create game, L to list games, then 1-4 to join as player")
	
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Auto-load existing games on startup
	list_games()

func update_info(text: String):
	if info_box:
		info_box.text = text
	print(text)

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_C:
				create_game()
			KEY_L:
				list_games()
			KEY_1:
				if available_games.size() >= 1:
					select_game_or_join(1)
				else:
					join_as_player(1)
			KEY_2:
				if available_games.size() >= 2:
					select_game_or_join(2)
				else:
					join_as_player(2)
			KEY_3:
				if available_games.size() >= 3:
					select_game_or_join(3)
				else:
					join_as_player(3)
			KEY_4:
				if available_games.size() >= 4:
					select_game_or_join(4)
				else:
					join_as_player(4)

func create_game():
	update_info("Creating new game...")
	var url = server_url + "/games"
	http_request.request(url, [], HTTPClient.METHOD_POST)

func list_games():
	update_info("Fetching active games...")
	var url = server_url + "/games"
	http_request.request(url)

func join_as_player(player_num: int):
	if current_game_id == "":
		update_info("No game selected! Press L to list games or C to create one.")
		return
	
	update_info("Joining as Player " + str(player_num))
	var scene_path = "res://game/scenes/client" + str(player_num) + ".tscn"
	
	get_tree().set_meta("game_id", current_game_id)
	get_tree().change_scene_to_file(scene_path)

func select_game_or_join(num: int):
	if current_game_id == "":
		# Select game
		if num <= available_games.size():
			current_game_id = available_games[num - 1].gameId
			update_info("Selected game: " + current_game_id + "\nNow press 1-4 to join as a player")
	else:
		# Join as player
		join_as_player(num)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		
		if parse_result == OK:
			if "gameId" in json.data:
				# Game creation response
				current_game_id = json.data.gameId
				update_info("Game created! Game ID: " + current_game_id + "\nNow press 1, 2, 3, or 4 to join as a player")
			elif "games" in json.data:
				# Game list response
				available_games = json.data.games
				if available_games.size() == 0:
					update_info("No active games found. Press C to create one.")
					current_game_id = ""
				else:
					var info_text = "Active games:\n"
					for i in range(available_games.size()):
						var game = available_games[i]
						info_text += "  " + str(i+1) + ": " + game.gameId + " (Turn: Player " + str(game.playerInTurn + 1) + ")\n"
					info_text += "Press 1-" + str(available_games.size()) + " to select game, then 1-4 to join as player"
					
					# Auto-select first game if only one exists
					if available_games.size() == 1:
						current_game_id = available_games[0].gameId
						info_text += "\nAuto-selected game: " + current_game_id
					
					update_info(info_text)
	else:
		update_info("Server request failed. Response code: " + str(response_code))
