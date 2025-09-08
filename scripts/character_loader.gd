extends Node

signal characters_loaded

@onready var players_node: Node3D = get_parent().get_node("Players")
var hero_scene = preload("res://game/scenes/hero.tscn")

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
		
		print("Character Loader: Replaced " + player_name + " with hero scene")