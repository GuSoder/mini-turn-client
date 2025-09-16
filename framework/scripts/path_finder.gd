class_name PathFinder
extends Node

# A* pathfinding for hex grid
# Handles blocked hexes (player positions) and uses 3D distance as heuristic

class AStarNode:
	var hex_pos: Vector2i
	var world_pos: Vector3
	var g_cost: float = 0.0  # Distance from start
	var h_cost: float = 0.0  # Heuristic distance to goal
	var f_cost: float = 0.0  # g_cost + h_cost
	var parent: AStarNode = null
	
	func _init(pos: Vector2i, world: Vector3):
		hex_pos = pos
		world_pos = world
	
	func calculate_f_cost():
		f_cost = g_cost + h_cost

var blocked_hexes: Array[Vector2i] = []
var island_map: Array = []
var client: Client

func _ready():
	client = get_parent() as Client
	# Connect to map loader if it exists
	var map_loader = get_parent().get_node_or_null("MapLoader")
	if map_loader:
		map_loader.map_loaded.connect(_on_island_map_loaded)

func _on_island_map_loaded(map_data: Array):
	island_map = map_data
	print("PathFinder: Island map loaded for pathfinding")

# Set blocked hexes (usually player positions)
func set_blocked_hexes(hexes: Array[Vector2i]):
	blocked_hexes = hexes.duplicate()

# Convert hex coordinates to world position
func hex_to_world(hex_pos: Vector2i) -> Vector3:
	var q = float(hex_pos.x)
	var r = float(hex_pos.y)
	
	var x = 1.7 * q + 0.85 * r
	var z = 1.5 * r
	
	return Vector3(x, 0, z)

# Get 3D distance between two hex positions (heuristic function)
func get_3d_distance(from: Vector2i, to: Vector2i) -> float:
	var from_world = hex_to_world(from)
	var to_world = hex_to_world(to)
	return from_world.distance_to(to_world)

# Get hex neighbors (adjacent hexes)
func get_hex_neighbors(hex_pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	
	# Hex grid neighbors (6 directions)
	var hex_directions = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	
	# Get map size dynamically from island_map
	var map_size = island_map.size() if island_map.size() > 0 else 10
	
	for direction in hex_directions:
		var neighbor = hex_pos + direction
		# Check grid bounds using dynamic map size
		if neighbor.x >= 0 and neighbor.x < map_size and neighbor.y >= 0 and neighbor.y < map_size:
			neighbors.append(neighbor)
	
	return neighbors

# Check if hex is non-traversable (water or trees)
func is_hex_blocked_by_terrain(hex_pos: Vector2i) -> bool:
	if island_map.size() == 0:
		return false  # No map data, assume traversable
	
	if hex_pos.y < 0 or hex_pos.y >= island_map.size():
		return true  # Out of bounds, treat as water
	
	var row_data = island_map[hex_pos.y]
	if hex_pos.x < 0 or hex_pos.x >= row_data.length():
		return true  # Out of bounds, treat as water
	
	var tile_value = int(str(row_data[hex_pos.x]))
	return tile_value != 1  # Only grass (1) is walkable

# Check if hex is blocked (by players or terrain)
func is_hex_blocked(hex_pos: Vector2i) -> bool:
	return hex_pos in blocked_hexes or is_hex_blocked_by_terrain(hex_pos)

# Get full path from start to goal (may be very long)
func get_full_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	return find_path(start, goal)

# A* pathfinding algorithm
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return [start]
	
	var open_set: Array[AStarNode] = []
	var closed_set: Array[Vector2i] = []
	
	# Create start node
	var start_node = AStarNode.new(start, hex_to_world(start))
	start_node.g_cost = 0.0
	start_node.h_cost = get_3d_distance(start, goal)
	start_node.calculate_f_cost()
	
	open_set.append(start_node)
	
	while open_set.size() > 0:
		# Find node with lowest f_cost
		var current_node = open_set[0]
		var current_index = 0
		
		for i in range(1, open_set.size()):
			if open_set[i].f_cost < current_node.f_cost:
				current_node = open_set[i]
				current_index = i
		
		# Move current node from open to closed set
		open_set.remove_at(current_index)
		closed_set.append(current_node.hex_pos)
		
		# Check if we reached the goal
		if current_node.hex_pos == goal:
			return reconstruct_path(current_node)
		
		# Check all neighbors
		var neighbors = get_hex_neighbors(current_node.hex_pos)
		for neighbor_pos in neighbors:
			# Skip if in closed set or blocked (but allow goal even if blocked)
			if neighbor_pos in closed_set:
				continue
			if is_hex_blocked(neighbor_pos) and neighbor_pos != goal:
				continue
			
			# Calculate tentative g_cost
			var neighbor_world = hex_to_world(neighbor_pos)
			var tentative_g_cost = current_node.g_cost + current_node.world_pos.distance_to(neighbor_world)
			
			# Check if this path to neighbor is better
			var neighbor_node = find_node_in_open_set(open_set, neighbor_pos)
			
			if neighbor_node == null:
				# Create new node
				neighbor_node = AStarNode.new(neighbor_pos, neighbor_world)
				neighbor_node.g_cost = tentative_g_cost
				neighbor_node.h_cost = get_3d_distance(neighbor_pos, goal)
				neighbor_node.parent = current_node
				neighbor_node.calculate_f_cost()
				open_set.append(neighbor_node)
			elif tentative_g_cost < neighbor_node.g_cost:
				# Better path found
				neighbor_node.g_cost = tentative_g_cost
				neighbor_node.parent = current_node
				neighbor_node.calculate_f_cost()
	
	# No path found
	return []

# Find node in open set
func find_node_in_open_set(open_set: Array[AStarNode], hex_pos: Vector2i) -> AStarNode:
	for node in open_set:
		if node.hex_pos == hex_pos:
			return node
	return null

# Reconstruct path from goal to start
func reconstruct_path(goal_node: AStarNode) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current_node = goal_node
	
	while current_node != null:
		path.push_front(current_node.hex_pos)
		current_node = current_node.parent
	
	return path
