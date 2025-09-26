extends Node

enum CampaignState { LOBBY, OVERWORLD, PLAINS }

const SERVER_URL = "http://207.154.222.143:5000"

var current_state: CampaignState = CampaignState.LOBBY
var map_loader: Node
var character_loader: Node
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
	character_loader = client.get_node_or_null("CharacterLoader")

	# Get game_id from tree meta or client property
	game_id = get_tree().get_meta("game_id", "")
	if game_id == "" and "game_id" in client:
		game_id = client.game_id

	#print("Campaign Manager: Using game_id: ", game_id)

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
		#print("Campaign Manager: Starting campaign - setting overworld_start scenario")

func set_scenario(scenario_name: String):
	# Only client 1 should set scenarios
	if client.client_number != 1:
		return

	if game_id == "":
		#print("Campaign Manager: No game_id available, cannot set scenario")
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

	#print("Campaign Manager: Setting scenario to ", scenario_name, " for game ", game_id, " (attempt 1/10)")
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
				#print("Campaign Manager: Scenario set successfully")
				# Trigger character loading based on current state
				_load_characters_for_current_state()
			else:
				print("Campaign Manager: Scenario set failed: ", response_data.get("error", "Unknown error"))
		else:
			print("Campaign Manager: Failed to parse scenario response JSON")
	else:
		print("Campaign Manager: Scenario set failed with response code: ", response_code)

func _on_scenario_timeout():
	scenario_retry_count += 1

	if scenario_retry_count < 10:
		#print("Campaign Manager: Scenario request timed out - retrying (attempt " + str(scenario_retry_count + 1) + "/10)...")
		scenario_timeout_timer.start()  # Start timer for next attempt

		# Retry the last request - we need to store the scenario name
		# For now, just retry with a generic approach
		#print("Campaign Manager: Retrying scenario request...")
	else:
		#print("Campaign Manager: Scenario request failed after 10 attempts - giving up")
		is_scenario_request_pending = false
		scenario_retry_count = 0


func game_state_changed():
	# Only client 1 controls the campaign flow
	if client.client_number != 1:
		return

	#print("Campaign Manager: Game state changed, current state: ", CampaignState.keys()[current_state])

	if current_state == CampaignState.PLAINS:
		# Check if all enemies are defeated
		if all_enemies_defeated():
			# Return to overworld
			current_state = CampaignState.OVERWORLD
			set_scenario("overworld_return")
			#print("Campaign Manager: All enemies defeated - returning to overworld")

func on_move_completed():
	# Only client 1 controls the campaign flow
	if client.client_number != 1:
		return

	#print("Campaign Manager: Move completed, current state: ", CampaignState.keys()[current_state])

	if current_state == CampaignState.OVERWORLD:
		# Move from overworld to plains
		current_state = CampaignState.PLAINS
		set_scenario("plains_battle")
		#print("Campaign Manager: Transitioning from overworld to plains battle")

func all_enemies_defeated() -> bool:
	# Check health of entities 5, 6, 7, and 8 (enemies)
	# Access the current game state from the client
	if not client or not client.current_game_state.has("stats"):
		#print("Campaign Manager: No game state available")
		return false

	var stats = client.current_game_state["stats"]
	if stats.size() < 8:
		#print("Campaign Manager: Not enough entity stats")
		return false

	# Check if entities 5, 6, 7, and 8 (indices 4, 5, 6, 7) are all dead
	var enemy_entities = [4, 5, 6, 7]  # Entities 5, 6, 7, 8 (0-indexed)
	var alive_enemies = 0

	for enemy_index in enemy_entities:
		var enemy_health = stats[enemy_index].get("health", 0)
		if enemy_health > 0:
			alive_enemies += 1

	#print("Campaign Manager: Alive enemies (entities 5,6,7,8): ", alive_enemies)
	return alive_enemies == 0

func _load_characters_for_current_state():
	if not character_loader:
		#print("Campaign Manager: CharacterLoader not found")
		return

	var state_string = ""
	match current_state:
		CampaignState.OVERWORLD:
			state_string = "overworld"
		CampaignState.PLAINS:
			state_string = "plains"
		_:
			state_string = "default"

	#print("Campaign Manager: Loading characters for state: ", state_string)
	character_loader.load_characters(state_string)

func go_to_overworld():
	# Only client 1 should call go_to_overworld
	if client.client_number != 1:
		return

	if game_id == "":
		#print("Campaign Manager: No game_id available, cannot go to overworld")
		return

	var url = SERVER_URL + "/games/" + game_id + "/go_to_overworld"
	var headers = ["Content-Type: application/json"]

	#print("Campaign Manager: Calling go_to_overworld for game ", game_id)
	# Use a simple fire-and-forget request since we don't need to track the response
	var temp_http = HTTPRequest.new()
	add_child(temp_http)
	temp_http.request_completed.connect(func(result, code, h, body): temp_http.queue_free())
	temp_http.request(url, headers, HTTPClient.METHOD_POST, "{}")
