extends Node3D

@export var move_speed: float = 5.0
@export var rotation_speed: float = 2.0
@export var zoom_speed: float = 1.0
@export var min_zoom: float = 2.0
@export var max_zoom: float = 20.0

@onready var hand: Node3D = $Arm/Hand

func _ready():
	pass

func _process(delta):
	handle_movement(delta)
	handle_rotation(delta)

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(zoom_speed)

func handle_movement(delta):
	var input_vector = Vector2()
	
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_vector.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_vector.x += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_vector.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_vector.y += 1
	
	if input_vector != Vector2.ZERO:
		input_vector = input_vector.normalized()
		var movement = Vector3(input_vector.x, 0, input_vector.y) * move_speed * delta
		translate(movement)

func handle_rotation(delta):
	var rotation_input = 0.0
	
	if Input.is_key_pressed(KEY_Q):
		rotation_input -= 1
	if Input.is_key_pressed(KEY_E):
		rotation_input += 1
	
	if rotation_input != 0:
		rotate_y(rotation_input * rotation_speed * delta)

func zoom(amount):
	if hand:
		var current_z = hand.transform.origin.z
		var new_z = clamp(current_z + amount, min_zoom, max_zoom)
		hand.transform.origin.z = new_z