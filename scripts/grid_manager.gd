extends Node

@onready var grid_node: Node3D = get_parent().get_node("Grid")
@onready var island_loader: Node = get_parent().get_node("IslandLoader")

var hex_water_scene = preload("res://setdressing/scenes/hex0_water.tscn")
var hex_grass_scene = preload("res://setdressing/scenes/hex1_grass.tscn")

func _ready():
	if island_loader:
		island_loader.map_loaded.connect(_on_map_loaded)

func _on_map_loaded(map_data: Array):
	print("Grid Manager: Updating grid with island map data")
	update_grid_tiles(map_data)

func update_grid_tiles(map_data: Array):
	if not grid_node or map_data.size() != 10:
		print("Grid Manager: Invalid map data or grid node")
		return
	
	for row_index in range(10):
		if row_index >= map_data.size():
			continue
			
		var row_data = map_data[row_index]
		if row_data.length() != 10:
			continue
			
		var row_node = grid_node.get_child(row_index)
		if not row_node:
			continue
			
		for hex_index in range(10):
			if hex_index >= row_data.length():
				continue
				
			var tile_type = int(str(row_data[hex_index]))
			var hex_node = row_node.get_child(hex_index)
			
			if not hex_node:
				continue
			
			# Get current transform to preserve position
			var current_transform = hex_node.transform
			
			# Remove old hex node
			row_node.remove_child(hex_node)
			hex_node.queue_free()
			
			# Create new hex based on tile type
			var new_hex_scene
			if tile_type == 0:
				new_hex_scene = hex_water_scene
			else:
				new_hex_scene = hex_grass_scene
			
			var new_hex = new_hex_scene.instantiate()
			new_hex.name = "Hex" + str(hex_index)
			new_hex.transform = current_transform
			
			# Add to row at correct position
			row_node.add_child(new_hex)
			row_node.move_child(new_hex, hex_index)