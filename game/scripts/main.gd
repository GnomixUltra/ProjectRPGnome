extends Node3D

## Порядок кадров важен: Terrain строит меш/коллизии в своём _ready,
## main спавнит игрока на кадре позже, WolfSpawner ждёт ещё кадр и спавнит волков.


func _ready() -> void:
	# Ждём, пока terrain.gd в _ready() построит меш и коллизию.
	await get_tree().process_frame

	# Спавн игрока над поверхностью ландшафта (в долине тракта высота ~0).
	var terrain := get_node_or_null("GroundBody/Terrain")
	var spawn := get_tree().get_first_node_in_group("player")
	if spawn and terrain and terrain.has_method("height_at"):
		var ground_y: float = terrain.height_at(Vector2(0.0, 0.0))
		spawn.global_position = Vector3(0.0, ground_y + 1.5, 0.0)
	elif spawn:
		spawn.global_position = Vector3(0.0, 2.0, 0.0)

	# Ещё кадр — волки спавнятся уже на готовом рельефе (их скрипт сам ждёт process_frame).
	await get_tree().process_frame
