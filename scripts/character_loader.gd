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
	# Load characters on startup
	load_characters()

func load_characters():
	print("Character Loader: Replacing player nodes with hero scenes")
	replace_players_with_heroes()
	characters_loaded.emit()

func replace_players_with_heroes():
	if not players_node:
		print("Character Loader: Players node not found")
		return
	
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
		
		# Create new hero scene
		var hero_instance = hero_scene.instantiate()
		hero_instance.name = current_name
		hero_instance.transform = current_transform
		
		# Add to players node
		players_node.add_child(hero_instance)
		
		# Replace upper body with player-specific variant
		replace_upper_body(hero_instance, i + 1)
		
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
