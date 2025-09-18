extends Node

enum CampaignState { LOBBY, OVERWORLD, PLAINS }

const SERVER_URL = "http://207.154.222.143:5000"

var current_state: CampaignState = CampaignState.LOBBY
var map_loader: Node
var client: Node
var http_request: HTTPRequest
var game_id: String
var scenario_retry_count: int = 0
var scenario_timeout_timer: Timer
var is_scenario_request_pending: bool = false

func _ready():
	# Get references to other nodes
	client = get_parent()
	map_loader = client.get_node_or_null("MapLoader")

	# Get game_id from tree meta or client property
	game_id = get_tree().get_meta("game_id", "")
	if game_id == "" and "game_id" in client:
		game_id = client.game_id

	print("Campaign Manager: Using game_id: ", game_id)

	# Setup HTTP request for scenario calls
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_scenario_request_completed)

	# Setup scenario timeout timer
	scenario_timeout_timer = Timer.new()
	add_child(scenario_timeout_timer)
	scenario_timeout_timer.wait_time = 0.25  # 250ms timeout
	scenario_timeout_timer.one_shot = true
	scenario_timeout_timer.timeout.connect(_on_scenario_timeout)

	# Start campaign flow after a brief delay
	call_deferred("start_campaign")

func start_campaign():
	# Only client 1 controls the campaign flow
	if client.client_number == 1:
		current_state = CampaignState.OVERWORLD
		set_scenario("overworld_start")
		print("Campaign Manager: Starting campaign - setting overworld_start scenario")

func set_scenario(scenario_name: String):
	# Only client 1 should set scenarios
	if client.client_number != 1:
		return

	if game_id == "":
		print("Campaign Manager: No game_id available, cannot set scenario")
		return

	if is_scenario_request_pending:
		return  # Already have a scenario request pending

	var request_body = {
		"scenario": scenario_name
	}

	var url = SERVER_URL + "/games/" + game_id + "/set_scenario"
	var headers = ["Content-Type: application/json"]

	# Setup retry tracking
	is_scenario_request_pending = true
	scenario_retry_count = 0
	scenario_timeout_timer.start()

	print("Campaign Manager: Setting scenario to ", scenario_name, " for game ", game_id, " (attempt 1/10)")
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(request_body))

func _on_scenario_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if not is_scenario_request_pending:
		return  # Not our response

	is_scenario_request_pending = false
	scenario_retry_count = 0
	scenario_timeout_timer.stop()

	if response_code == 200:
		var json_parser = JSON.new()
		var parse_result = json_parser.parse(body.get_string_from_utf8())

		if parse_result == OK:
			var response_data = json_parser.data
			if response_data.get("ok", false):
				print("Campaign Manager: Scenario set successfully")
			else:
				print("Campaign Manager: Scenario set failed: ", response_data.get("error", "Unknown error"))
		else:
			print("Campaign Manager: Failed to parse scenario response JSON")
	else:
		print("Campaign Manager: Scenario set failed with response code: ", response_code)

func _on_scenario_timeout():
	scenario_retry_count += 1

	if scenario_retry_count < 10:
		print("Campaign Manager: Scenario request timed out - retrying (attempt " + str(scenario_retry_count + 1) + "/10)...")
		scenario_timeout_timer.start()  # Start timer for next attempt

		# Retry the last request - we need to store the scenario name
		# For now, just retry with a generic approach
		print("Campaign Manager: Retrying scenario request...")
	else:
		print("Campaign Manager: Scenario request failed after 10 attempts - giving up")
		is_scenario_request_pending = false
		scenario_retry_count = 0


func on_move_completed():
	# Only client 1 controls the campaign flow
	if client.client_number != 1:
		return

	print("Campaign Manager: Move completed, current state: ", CampaignState.keys()[current_state])

	if current_state == CampaignState.OVERWORLD:
		# Move from overworld to plains
		current_state = CampaignState.PLAINS
		set_scenario("plains_battle")
		print("Campaign Manager: Transitioning from overworld to plains battle")
	elif current_state == CampaignState.PLAINS:
		# Check if all enemies are defeated
		if all_enemies_defeated():
			# Return to overworld
			current_state = CampaignState.OVERWORLD
			set_scenario("overworld_start")
			print("Campaign Manager: All enemies defeated - returning to overworld")
		else:
			print("Campaign Manager: Still enemies remaining in plains")

func all_enemies_defeated() -> bool:
	# Check health of players 2, 3, and 4 (hardcoded as enemies)
	# Access the current game state from the client
	if not client or not client.current_game_state.has("stats"):
		print("Campaign Manager: No game state available")
		return false

	var stats = client.current_game_state["stats"]
	if stats.size() < 4:
		print("Campaign Manager: Not enough player stats")
		return false

	# Check if players 2, 3, and 4 (indices 1, 2, 3) are all dead
	var enemy_players = [1, 2, 3]  # Players 2, 3, 4 (0-indexed)
	var alive_enemies = 0

	for enemy_index in enemy_players:
		var enemy_health = stats[enemy_index].get("health", 0)
		if enemy_health > 0:
			alive_enemies += 1

	print("Campaign Manager: Alive enemies (players 2,3,4): ", alive_enemies)
	return alive_enemies == 0
