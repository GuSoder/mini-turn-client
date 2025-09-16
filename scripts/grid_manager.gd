extends Node

@onready var grid_node: Node3D = get_parent().get_node("Grid")
@onready var map_loader: Node = get_parent().get_node("MapLoader")

var hex_water_scene = preload("res://setdressing/scenes/hex0_water.tscn")
var hex_grass_scene = preload("res://setdressing/scenes/hex1_grass.tscn")
var hex_tree_scene = preload("res://setdressing/scenes/hex2_tree.tscn")
var hex_house_scene = preload("res://setdressing/scenes/hex3_house.tscn")
var hex_stone_scene = preload("res://setdressing/scenes/hex4_stone.tscn")
var hex_plain_scene = preload("res://overworld/scenes/hex5_plain.tscn")
var hex_forrest_scene = preload("res://overworld/scenes/hex6_forrest.tscn")
var hex_village_scene = preload("res://overworld/scenes/hex7_village.tscn")

func _ready():
	if map_loader:
		map_loader.map_loaded.connect(_on_map_loaded)

func _on_map_loaded(map_data: Array):
	print("Grid Manager: Updating grid with island map data")
	update_grid_tiles(map_data)

func update_grid_tiles(map_data: Array):
	if not grid_node or map_data.size() == 0:
		print("Grid Manager: Invalid map data or grid node")
		return
	
	var map_size = map_data.size()
	print("Grid Manager: Loading ", map_size, "x", map_size, " map")
	
	# Ensure we have enough row nodes - create additional rows if needed
	while grid_node.get_child_count() < map_size:
		var new_row = Node3D.new()
		var row_index = grid_node.get_child_count()
		new_row.name = "Row" + str(row_index)
		
		# Use the exact same pattern as the original grid: 30-degree rotation, -1.7 Z spacing
		var basis = Basis(Vector3(0.866025, 0, -0.5), Vector3(0, 1, 0), Vector3(0.5, 0, 0.866025))
		new_row.transform = Transform3D(basis, Vector3(0, 0, row_index * -1.7))
		
		grid_node.add_child(new_row)
	
	for row_index in range(map_size):
		if row_index >= map_data.size():
			continue
			
		var row_data = map_data[row_index]
		if row_data.length() != map_size:
			print("Grid Manager: Row ", row_index, " has wrong length: ", row_data.length())
			continue
			
		var row_node = grid_node.get_child(row_index)
		
		# Extend this row if it needs more hexes - continue the 1.7 unit spacing pattern
		while row_node.get_child_count() < map_size:
			var hex_index = row_node.get_child_count()
			var placeholder_hex = hex_grass_scene.instantiate()
			placeholder_hex.name = "Hex" + str(hex_index)
			
			# Use the exact same pattern as original: X position = hex_index * 1.7
			placeholder_hex.transform = Transform3D(Basis.IDENTITY, Vector3(hex_index * 1.7, 0, 0))
			
			row_node.add_child(placeholder_hex)
		
		# Now update all hexes in this row
		for hex_index in range(map_size):
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
			elif tile_type == 1:
				new_hex_scene = hex_grass_scene
			elif tile_type == 2:
				new_hex_scene = hex_tree_scene
			elif tile_type == 3:
				new_hex_scene = hex_house_scene
			elif tile_type == 4:
				new_hex_scene = hex_stone_scene
			elif tile_type == 5:
				new_hex_scene = hex_plain_scene
			elif tile_type == 6:
				new_hex_scene = hex_forrest_scene
			elif tile_type == 7:
				new_hex_scene = hex_village_scene
			else:
				new_hex_scene = hex_grass_scene
			
			var new_hex = new_hex_scene.instantiate()
			new_hex.name = "Hex" + str(hex_index)
			new_hex.transform = current_transform
			
			# Add to row at correct position
			row_node.add_child(new_hex)
			row_node.move_child(new_hex, hex_index)
