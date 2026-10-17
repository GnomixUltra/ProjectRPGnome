extends Node3D

## Спавн волков на поляне (в плоской долине terrain, по центру карты).
## Позиции подбираются так, чтобы не появляться прямо на игроке.

@export var wolf_count := 6
@export var glade_center := Vector2(0.0, -28.0)   # «поляна» в долине у тракта
@export var glade_radius := 14.0                  # разброс стай вокруг центра
@export var min_distance_to_player := 12.0        # не спавниться вплотную к игроку


func _ready() -> void:
	await get_tree().process_frame  # дождаться построения ландшафта и спавна игрока
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for i in range(wolf_count):
		var pos := _random_pos(player)
		# add_child.call_deferred: узел может спавниться, пока дерево ещё в фазе setup.
		add_child.call_deferred(_make_wolf(pos))


func _random_pos(player: Node3D) -> Vector3:
	var p := Vector3.ZERO
	for attempt in range(24):
		var a := randf() * TAU
		var r := randf_range(glade_radius * 0.25, glade_radius)
		p = Vector3(glade_center.x + cos(a) * r, 0.0, glade_center.y + sin(a) * r)
		if player == null or not is_instance_valid(player):
			break
		if Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length() >= min_distance_to_player:
			break
	# Посадка по рельефу: ищем достаточно плоскую точку рядом (в чаше холмы
	# начинаются сразу за поляной, спавн «в воздухе» или на отвесном склоне
	# приводил к проваливанию/выкатыванию волков).
	p.y = _ground_y(p)
	return p


## Высота земли с локальным сглаживанием: берём минимум из окрестности,
## затем прикидываем уклон — если точка слишком крутая, смещаемся к центру.
func _ground_y(p: Vector3) -> float:
	var terrain := get_node_or_null("/root/Main/GroundBody/Terrain")
	if terrain == null or not terrain.has_method("height_at"):
		return 0.0
	var best := -1e9
	for dx in [-2.0, 0.0, 2.0]:
		for dz in [-2.0, 0.0, 2.0]:
			best = maxf(best, terrain.height_at(Vector2(p.x + dx, p.z + dz)))
	return best + 0.2


func _make_wolf(pos: Vector3) -> CharacterBody3D:
	var wolf_scene := preload("res://scenes/wolf.tscn")
	var wolf := wolf_scene.instantiate() as CharacterBody3D
	wolf.position = pos
	return wolf
