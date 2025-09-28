extends Node

const SERVER_URL = "http://207.154.222.143:5000"

var http_request: HTTPRequest
var client: Node
var current_settlement_data: Dictionary = {}

func _ready():
	# Get references to other nodes
	client = get_parent()

	# Setup HTTP request for settlement calls
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_settlement_request_completed)

func load_settlement(settlement_name: String):
	if settlement_name == "":
		return

	var url = SERVER_URL + "/settlement/" + settlement_name
	http_request.request(url, [], HTTPClient.METHOD_GET)

func _on_settlement_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		var json_parser = JSON.new()
		var parse_result = json_parser.parse(body.get_string_from_utf8())

		if parse_result == OK:
			current_settlement_data = json_parser.data
			_assign_patrol_points()
		else:
			print("SettlementManager: Failed to parse settlement response JSON")
	else:
		print("SettlementManager: Settlement request failed with response code: ", response_code)

func _assign_patrol_points():
	if not current_settlement_data.has("entity_routes"):
		return

	var entity_routes = current_settlement_data["entity_routes"]
	if not client or not client.current_game_state.has("positions"):
		return

	# Assign patrol routes to all 8 entities
	for i in range(8):
		if i < entity_routes.size() and i < client.current_game_state["positions"].size():
			var route = entity_routes[i]
			if route.size() >= 2:
				# For now, just set the entity's target to the second point in their route
				# This could be expanded to full patrol logic later
				var target_pos = route[1]
				print("SettlementManager: Entity ", i + 1, " assigned patrol target: ", target_pos)