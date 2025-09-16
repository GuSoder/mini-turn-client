extends Node

enum CampaignState { LOBBY, OVERWORLD, PLAINS }

const SERVER_URL = "http://207.154.222.143:5000"

var current_state: CampaignState = CampaignState.LOBBY
var map_loader: Node
var client: Node
var http_request: HTTPRequest
var game_id: String

func _ready():
	# Get references to other nodes
	client = get_parent()
	map_loader = client.get_node_or_null("MapLoader")
	if "game_id" in client:
		game_id = client.game_id
	else:
		game_id = ""

	# Setup HTTP request for set_map calls
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_set_map_completed)

	# Start campaign flow after a brief delay
	call_deferred("start_campaign")

func start_campaign():
	# Only client 1 controls the campaign flow
	if client.client_number == 1:
		current_state = CampaignState.OVERWORLD
		set_server_map("overworld")
		print("Campaign Manager: Starting campaign - setting server map to overworld")

func set_server_map(map_name: String):
	# Only client 1 should call this
	if client.client_number != 1:
		return

	var request_body = {
		"map": map_name
	}

	var url = SERVER_URL + "/games/" + game_id + "/set_map"
	var headers = ["Content-Type: application/json"]

	print("Campaign Manager: Setting server map to ", map_name)
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))

func _on_set_map_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		print("Campaign Manager: Server map change successful")
	else:
		print("Campaign Manager: Server map change failed: ", response_code)

func on_move_completed():
	# Only client 1 controls the campaign flow
	if client.client_number != 1:
		return

	print("Campaign Manager: Move completed, current state: ", CampaignState.keys()[current_state])

	if current_state == CampaignState.OVERWORLD:
		# Move from overworld to plains
		current_state = CampaignState.PLAINS
		set_server_map("plains")
		print("Campaign Manager: Transitioning from overworld to plains")
	elif current_state == CampaignState.PLAINS:
		# Check if all enemies are defeated
		if all_enemies_defeated():
			# Return to overworld
			current_state = CampaignState.OVERWORLD
			set_server_map("overworld")
			print("Campaign Manager: All enemies defeated - returning to overworld")
		else:
			print("Campaign Manager: Still enemies remaining in plains")

func all_enemies_defeated() -> bool:
	# Check all bot clients for enemies
	var bots_node = client.get_node("Bots")
	if not bots_node:
		return true

	var enemy_count = 0
	for bot in bots_node.get_children():
		if "alignment" in bot and bot.alignment == "enemy":
			enemy_count += 1

	print("Campaign Manager: Enemy count: ", enemy_count)
	return enemy_count == 0