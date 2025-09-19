extends Node

signal characters_loaded

@onready var players_node: Node3D = get_parent().get_node("Players")
var hero_scene = preload("res://game/scenes/hero.tscn")
var upper_body_scenes = [
	preload("res://game/scenes/upper_body_1.tscn"),
	preload("res://game/scenes/upper_body_2.tscn"),
	preload("res://game/scenes/upper_body_3.tscn"),
	preload("res://game/scenes/upper_body_4.tscn")
]

func _ready():
	# Character loading is now controlled by CampaignManager
	pass

func load_characters(campaign_state = null):
	print("Character Loader: Loading characters for state: ", campaign_state)

	if campaign_state == "overworld":
		load_characters_party()
	else:
		replace_players_with_heroes()

	characters_loaded.emit()

func load_characters_party():
	print("Character Loader: Loading characters in party mode")

	# Make players 2-4 invisible
	for i in range(1, 4):
		var player_name = "Player" + str(i + 1)
		var player_node = players_node.get_node_or_null(player_name)
		if player_node:
			player_node.visible = false

	# Create party heroes parented to Player1
	var player1 = players_node.get_node_or_null("Player1")
	if not player1:
		print("Character Loader: Player1 not found for party mode")
		return

	# Position offsets for party members
	var party_positions = [
		Vector3(0.3, 0, 0),    # Hero 1
		Vector3(0, 0, 0.3),    # Hero 2
		Vector3(-0.3, 0, 0),   # Hero 3
		Vector3(0, 0, -0.3)    # Hero 4
	]

	# Create all 4 heroes as children of Player1
	for i in range(4):
		var hero_instance = create_hero_for_player(i + 1)
		if hero_instance:
			hero_instance.name = "PartyHero" + str(i + 1)
			hero_instance.scale = Vector3(0.2, 0.2, 0.2)
			hero_instance.position = party_positions[i]
			player1.add_child(hero_instance)
			print("Character Loader: Added party hero ", i + 1, " at position ", party_positions[i])

func create_hero_for_player(player_number: int) -> Node3D:
	# Create a hero instance for the specified player
	var hero_instance = hero_scene.instantiate()
	replace_upper_body(hero_instance, player_number)
	return hero_instance

func replace_players_with_heroes():
	if not players_node:
		print("Character Loader: Players node not found")
		return

	# Always make all players visible first (in case coming from overworld mode)
	for i in range(4):
		var player_name = "Player" + str(i + 1)
		var player_node = players_node.get_node_or_null(player_name)
		if player_node:
			player_node.visible = true

	# Replace each Player1, Player2, Player3, Player4 with hero scenes
	for i in range(4):
		var player_name = "Player" + str(i + 1)
		var player_node = players_node.get_node(player_name)

		if not player_node:
			print("Character Loader: Player node " + player_name + " not found")
			continue

		# Get current transform to preserve position
		var current_transform = player_node.transform
		var current_name = player_node.name

		# Remove old player node
		players_node.remove_child(player_node)
		player_node.queue_free()

		# Create new hero scene using the refactored function
		var hero_instance = create_hero_for_player(i + 1)
		hero_instance.name = current_name
		hero_instance.transform = current_transform

		# Add to players node
		players_node.add_child(hero_instance)

		print("Character Loader: Replaced " + player_name + " with hero scene")

func replace_upper_body(hero_instance: Node3D, player_number: int):
	# Find the UpperBody node in the hero's Appearance
	var appearance_node = hero_instance.get_node("Appearance")
	if not appearance_node:
		print("Character Loader: Appearance node not found in hero")
		return
	
	var upper_body_node = appearance_node.get_node("UpperBody")
	if not upper_body_node:
		print("Character Loader: UpperBody node not found in appearance")
		return
	
	# Get current transform to preserve position
	var current_transform = upper_body_node.transform
	var current_name = upper_body_node.name
	
	# Remove old upper body node
	appearance_node.remove_child(upper_body_node)
	upper_body_node.queue_free()
	
	# Create new upper body based on player number
	var upper_body_scene_index = player_number - 1
	if upper_body_scene_index >= 0 and upper_body_scene_index < upper_body_scenes.size():
		var new_upper_body = upper_body_scenes[upper_body_scene_index].instantiate()
		new_upper_body.name = current_name
		new_upper_body.transform = current_transform
		
		# Add to appearance node
		appearance_node.add_child(new_upper_body)
		
		print("Character Loader: Replaced upper body with upper_body_" + str(player_number))
	else:
		print("Character Loader: Invalid player number for upper body: " + str(player_number))
