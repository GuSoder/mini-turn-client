extends Node3D

func _ready():
	print("Press 1, 2, 3, or 4 to open a client scene")

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				get_tree().change_scene_to_file("res://scenes/client1.tscn")
			KEY_2:
				get_tree().change_scene_to_file("res://scenes/client2.tscn")
			KEY_3:
				get_tree().change_scene_to_file("res://scenes/client3.tscn")
			KEY_4:
				get_tree().change_scene_to_file("res://scenes/client4.tscn")
