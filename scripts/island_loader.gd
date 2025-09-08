extends Node

signal map_loaded(map_data: Array)

const SERVER_URL = "http://207.154.222.143:5000"
var http_request: HTTPRequest

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Fetch island map on startup
	fetch_island_map(1)

func fetch_island_map(island_number: int):
	var url = SERVER_URL + "/island/" + str(island_number)
	print("Fetching island map from: ", url)
	http_request.request(url)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if response_code == 200:
		var json = JSON.new()
		var parse_result = json.parse(body.get_string_from_utf8())
		
		if parse_result == OK:
			var data = json.data
			if data.has("map"):
				print("Island map loaded successfully")
				map_loaded.emit(data.map)
			else:
				print("Error: No map data in response")
		else:
			print("Error parsing JSON: ", parse_result)
	else:
		print("Error fetching island map. Response code: ", response_code)