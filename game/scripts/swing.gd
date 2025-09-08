class_name Swing
extends Node3D

@export var t_off : float = 0
@export var s : float = 1
@export var a : float = 1
@export var doOverrideAngle : bool = false
var overrideAngle : Vector3 = Vector3(90, 0, 0)
var t: float = 0.0
var z_off: float

# Called when the node enters the scene tree for the first time.
func _ready():
	z_off = rotation_degrees.z
	t = t_off * 3.15
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	t += delta * 10.0 * s
	var angle = 30 * sin(t) * a
	if doOverrideAngle:
		rotation_degrees = overrideAngle
	else:
		rotation_degrees = Vector3(angle, 0, z_off)
	pass
