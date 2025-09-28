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
	if not client:
		return

	# Get the Bots node containing all bot clients
	var bots_node = client.get_node_or_null("Bots")
	if not bots_node:
		print("SettlementManager: Bots node not found")
		return

	# Assign patrol routes to all 8 entities via their BotClient nodes
	for i in range(8):
		if i < entity_routes.size():
			var route = entity_routes[i]
			if route.size() >= 2:
				var patrol_point_1 = Vector2i(route[0]["q"], route[0]["r"])
				var patrol_point_2 = Vector2i(route[1]["q"], route[1]["r"])

				# Find the corresponding BotClient node
				var bot_client_name = "BotClient" + str(i + 1)
				var bot_client = bots_node.get_node_or_null(bot_client_name)

				if bot_client:
					bot_client.patrol_point_1 = patrol_point_1
					bot_client.patrol_point_2 = patrol_point_2
					bot_client.path_strategy = 2  # Set to patrol strategy
					print("SettlementManager: ", bot_client_name, " assigned patrol points: ", patrol_point_1, " -> ", patrol_point_2)
				else:
					print("SettlementManager: ", bot_client_name, " not found")