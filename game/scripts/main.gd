extends Node3D


func _ready() -> void:
	# Стартовая позиция игрока (над землёй, чтобы не застрять).
	var spawn := get_tree().get_first_node_in_group("player")
	if spawn:
		spawn.global_position = Vector3(0.0, 2.0, 0.0)
