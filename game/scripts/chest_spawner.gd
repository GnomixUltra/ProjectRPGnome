extends Node3D
## Раскидывает сундуки по чащам. Позиции — случайные при каждом запуске
## (сид меняется через RandomNumberGenerator.randomize()).

@export var chest_count := 7
@export var min_radius := 22.0     # не на поляне
@export var max_radius := 85.0     # в пределах карты
@export var terrain_path := NodePath("../GroundBody/Terrain")

var _terrain: Node3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)
	_rng.randomize()
	# Ждём построения ландшафта (он строится в кадре), потом спавним.
	get_tree().process_frame.connect(_spawn.bind(), CONNECT_ONE_SHOT)


func _height(x: float, z: float) -> float:
	return _terrain.height_at(Vector2(x, z))


func _spawn() -> void:
	var scene := load("res://scenes/chest.tscn") as PackedScene
	if scene == null or _terrain == null:
		push_warning("ChestSpawner: нет сцены сундука или Terrain")
		return
	var placed := 0
	var tries := 0
	while placed < chest_count and tries < 400:
		tries += 1
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(min_radius, max_radius)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := _height(x, z)
		# Не ставим в слишком крутые склоны — ищем более-менее ровное место.
		if absf(_height(x + 1.5, z) - h) > 1.6 or absf(_height(x, z + 1.5) - h) > 1.6:
			continue
		var c := scene.instantiate()
		add_child.call_deferred(c)
		c.set_deferred("global_position", Vector3(x, h + 0.35, z))
		c.set_deferred("rotation:y", _rng.randf() * TAU)
		placed += 1
	if placed == 0:
		push_warning("ChestSpawner: не нашлось ровных мест (%d попыток)" % tries)
