class_name ScenarioManager
extends Node

signal scenario_loaded(scenario_data: Dictionary)

const SERVER_URL = "http://207.154.222.143:5000"
var http_request: HTTPRequest

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

func load_scenario(scenario_name: String):
	var url = SERVER_URL + "/scenario/" + scenario_name
	print("ScenarioManager: Loading scenario from: ", url)
	http_request.request(url)

func get_available_scenarios():
	var url = SERVER_URL + "/scenarios"
	print("ScenarioManager: Getting available scenarios from: ", url)
	http_request.request(url)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		var json_parser = JSON.new()
		var parse_result = json_parser.parse(body.get_string_from_utf8())

		if parse_result == OK:
			var data = json_parser.data
			print("ScenarioManager: Data received successfully")
			scenario_loaded.emit(data)
		else:
			print("ScenarioManager: Error parsing JSON: ", parse_result)
	else:
		print("ScenarioManager: Error loading scenario. Response code: ", response_code)
		print("ScenarioManager: Response body: ", body.get_string_from_utf8())

func place_players(scenario_data: Dictionary):
	"""Place players at their scenario positions"""
	if not scenario_data.has("player_positions"):
		print("ScenarioManager: No player_positions in scenario data")
		return

	var player_positions = scenario_data["player_positions"]
	var players_node = get_parent().get_node_or_null("Players")

	if not players_node:
		print("ScenarioManager: Players node not found")
		return

	print("ScenarioManager: Placing players at scenario positions")

	for i in range(min(player_positions.size(), 4)):
		var player_node = players_node.get_node_or_null("Player" + str(i + 1))
		if player_node:
			var pos = player_positions[i]
			var world_pos = hex_to_world(pos["q"], pos["r"])
			player_node.position = world_pos
			print("ScenarioManager: Placed Player", i + 1, " at hex (", pos["q"], ",", pos["r"], ") world pos ", world_pos)

func hex_to_world(q: int, r: int) -> Vector3:
	"""Convert hex coordinates to world position"""
	var hex_size = 1.0
	var x = hex_size * (3.0/2.0 * q)
	var z = hex_size * (sqrt(3.0)/2.0 * q + sqrt(3.0) * r)
	return Vector3(x, 0, z)