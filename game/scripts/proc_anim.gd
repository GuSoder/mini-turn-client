extends Node

# Procedural Animation Controller
# Manages swing animations for hero characters

var swing_scripts: Array = []

func _ready():
	# Find all swing scripts in the hero hierarchy
	find_swing_scripts(get_parent())
	# Deactivate all swings by default
	deactivate_swings()
	print("ProcAnim: Found " + str(swing_scripts.size()) + " swing scripts")

func find_swing_scripts(node: Node):
	# Recursively find all nodes with swing scripts
	for child in node.get_children():
		if child.has_method("set_enabled") and child.get_script() != null:
			var script_path = child.get_script().get_path()
			if "swing.gd" in script_path:
				swing_scripts.append(child)
				print("ProcAnim: Found swing script on " + child.name)
		
		# Recursively check children
		find_swing_scripts(child)

func activate_swings():
	print("ProcAnim: Activating " + str(swing_scripts.size()) + " swing animations")
	for swing_script in swing_scripts:
		if swing_script and swing_script.has_method("set_enabled"):
			swing_script.set_enabled(true)

func deactivate_swings():
	print("ProcAnim: Deactivating " + str(swing_scripts.size()) + " swing animations")
	for swing_script in swing_scripts:
		if swing_script and swing_script.has_method("set_enabled"):
			swing_script.set_enabled(false)