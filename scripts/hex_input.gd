class_name HexInput
extends Node3D

signal hex_clicked(hex_pos: Vector2i)

var client: Client
var camera: Camera3D
var current_path: Array[Vector2i] = []
var is_selecting_path: bool = false
var hover_mark: MeshInstance3D

func _ready():
	client = get_parent() as Client
	camera = get_viewport().get_camera_3d()
	hover_mark = client.get_node("HoverMark")


func handle_mouse_click(screen_pos: Vector2):
	if not camera:
		return
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		var hex_pos = get_hex_coordinates_from_node(result.collider)
		handle_hex_click(hex_pos)

func world_to_hex(world_pos: Vector3) -> Vector2i:
	# Convert world position back to hex coordinates
	var x = world_pos.x
	var z = world_pos.z
	
	var q = (x / 1.7) - (z / 2.55)
	var r = z / 1.5
	
	return Vector2i(round(q), round(r))

func handle_hex_click(hex_pos: Vector2i):
	if not client:
		return
	
	var player_index = client.client_number - 1
	var current_pos = client.player_positions[player_index]
	
	if not is_selecting_path:
		# Start new path
		if hex_pos == current_pos:
			current_path = [current_pos]
			is_selecting_path = true
			print("Started path selection from ", current_pos)
		else:
			print("Must start path from current position. Clicked: ", hex_pos, " but current position is: ", current_pos)
	else:
		# Continue or end path
		if hex_pos == current_pos and current_path.size() > 1:
			# Clicked back to start, cancel path
			current_path.clear()
			is_selecting_path = false
			print("Cancelled path selection")
		elif is_adjacent_to_last_in_path(hex_pos):
			current_path.append(hex_pos)
			print("Extended path to ", hex_pos, " (length: ", current_path.size(), ")")
		else:
			print("Invalid move - not adjacent to last position in path")

func is_adjacent_to_last_in_path(hex_pos: Vector2i) -> bool:
	if current_path.is_empty():
		return false
	
	var last_pos = current_path[-1]
	return is_adjacent_hex(last_pos, hex_pos)

func is_adjacent_hex(pos1: Vector2i, pos2: Vector2i) -> bool:
	var diff_q = pos2.x - pos1.x
	var diff_r = pos2.y - pos1.y
	
	# Hex neighbors: (0,1), (1,0), (1,-1), (0,-1), (-1,0), (-1,1)
	var neighbors = [Vector2i(0,1), Vector2i(1,0), Vector2i(1,-1), Vector2i(0,-1), Vector2i(-1,0), Vector2i(-1,1)]
	return Vector2i(diff_q, diff_r) in neighbors

func get_hex_coordinates_from_node(hex_node: Node3D) -> Vector2i:
	# Find the hex coordinates by looking up the node in the grid hierarchy
	var grid_node = client.grid_node
	
	if not grid_node or not hex_node:
		return Vector2i(-1, -1)
	
	# Find which row and hex index this node is at
	for row_index in range(grid_node.get_child_count()):
		var row_node = grid_node.get_child(row_index)
		for hex_index in range(row_node.get_child_count()):
			var grid_hex_node = row_node.get_child(hex_index)
			if grid_hex_node == hex_node:
				return Vector2i(hex_index, row_index)
	
	print("Could not find hex coordinates for node")
	return Vector2i(-1, -1)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		if is_selecting_path and current_path.size() > 1:
			client.make_move(current_path)
			current_path.clear()
			is_selecting_path = false
			print("Move submitted!")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		handle_mouse_click(event.position)
	elif event is InputEventMouseMotion:
		handle_mouse_hover(event.position)

func handle_mouse_hover(screen_pos: Vector2):
	if not camera or not hover_mark:
		print("Camera or hover_mark not found")
		return
	
	var from = camera.project_ray_origin(screen_pos)
	var to = from + camera.project_ray_normal(screen_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result and result.collider:
		# Get the hex node position directly from the collision body
		var hex_node = result.collider
		var hex_world_pos = hex_node.global_position
		
		#print("Hover: Hit hex at ", hex_world_pos)
		hover_mark.position = hex_world_pos
		hover_mark.visible = true
	else:
		#print("No ray intersection")
		hover_mark.visible = false

func hex_to_world(hex_pos: Vector2i) -> Vector3:
	# Convert hex coordinates (q, r) to world position
	var q = float(hex_pos.x)
	var r = float(hex_pos.y)
	
	var x = 1.7 * q + 0.85 * r
	var z = 1.5 * r
	
	return Vector3(x, 0, z)
