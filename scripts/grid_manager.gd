extends Node

@onready var grid_node: Node3D = get_parent().get_node("Grid")
@onready var island_loader: Node = get_parent().get_node("IslandLoader")

var hex_water_scene = preload("res://setdressing/scenes/hex0_water.tscn")
var hex_grass_scene = preload("res://setdressing/scenes/hex1_grass.tscn")
var hex_tree_scene = preload("res://setdressing/scenes/hex2_tree.tscn")
var hex_house_scene = preload("res://setdressing/scenes/hex3_house.tscn")
var hex_stone_scene = preload("res://setdressing/scenes/hex4_stone.tscn")

func _ready():
	if island_loader:
		island_loader.map_loaded.connect(_on_map_loaded)

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
		new_row.name = "Row" + str(grid_node.get_child_count())
		
		# Position new row following the existing pattern
		var row_index = grid_node.get_child_count()
		if grid_node.get_child_count() > 0:
			var last_row = grid_node.get_child(grid_node.get_child_count() - 1)
			new_row.transform = last_row.transform
			new_row.transform.origin.z += 1.5  # Continue the row spacing pattern
		
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
			
			# Position following the existing 1.7 unit spacing pattern
			if row_node.get_child_count() > 0:
				var last_hex = row_node.get_child(row_node.get_child_count() - 1)
				placeholder_hex.transform = last_hex.transform
				placeholder_hex.transform.origin.x += 1.7  # Continue the hex spacing
			
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
			else:
				new_hex_scene = hex_grass_scene
			
			var new_hex = new_hex_scene.instantiate()
			new_hex.name = "Hex" + str(hex_index)
			new_hex.transform = current_transform
			
			# Add to row at correct position
			row_node.add_child(new_hex)
			row_node.move_child(new_hex, hex_index)
