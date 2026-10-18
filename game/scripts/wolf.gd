extends CharacterBody3D
## Волк — враждебный NPC на поляне.
## Поведение: патрулирует окрестности точки спавна, замечает игрока в радиусе
## aggros_range — преследует и кусает; потерял игрока за leash_range — возвращается.
## Простая атака «по касанию»: Area3D у головы наносит урон игроку с кулдауном.
## Волка можно убить прыжком на голову (тогда он теряет всё HP).

# --- Характеристики ---
@export var max_health := 40.0
@export var walk_speed := 2.6             # скорость патрулирования
@export var chase_speed := 6.5            # скорость преследования (быстрее шага игрока)
@export var bite_damage := 12.0           # урон укуса
@export var bite_interval := 1.4          # с — кулдаун укусов
@export var aggro_range := 18.0           # дистанция обнаружения игрока
@export var attack_range := 1.9           # дистанция укуса
@export var leash_range := 34.0           # дальше этой дистанции от дома — отступать
@export var patrol_radius := 9.0          # радиус патрулирования вокруг дома
@export var turn_speed := 7.0             # рад/с — поворот к цели

var level := 1                            # случайный уровень волка (1..3)

signal health_changed(current: float, maximum: float)
signal died(wolf: Node3D)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

var _health := max_health
var _home := Vector3.ZERO
var _patrol_target := Vector3.ZERO
var _state := "idle"                  # idle | patrol | chase | flee_home
var _wait_timer := 0.0
var _bite_cd := 0.0
var _dead := false
# Оригинальные цвета материалов волка (для возврата после красной вспышки урона).
var _base_colors := {}

@onready var head: Node3D = $Visual/Head
@onready var bite_area: Area3D = $Visual/Head/BiteArea


func _ready() -> void:
	_home = global_position
	_health = max_health
	add_to_group("enemies")
	# Случайные RPG-переменные каждого волка: уровень 1..3 (HP/урон/размер).
	level = int(randi_range(1, 3))
	max_health += (level - 1) * 8.0
	bite_damage += (level - 1) * 2.0
	scale = Vector3.ONE * (1.0 + (level - 1) * 0.15)
	_health = max_health
	_wait_timer = randf_range(0.5, 2.5)
	_pick_patrol_point()
	bite_area.body_entered.connect(_on_bite_body)
	# Запоминаем исходные цвета всех override-материалов (в scene они общие на
	# инстансы — поэтому вспышка делается копией материала для каждого MeshInstance).
	for mi in $Visual.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if m.material_override is StandardMaterial3D:
			_base_colors[m.name] = m.material_override.albedo_color


func _pick_patrol_point() -> void:
	var a := randf() * TAU
	var r := randf_range(patrol_radius * 0.35, patrol_radius)
	_patrol_target = _home + Vector3(cos(a) * r, 0.0, sin(a) * r)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	_bite_cd = maxf(0.0, _bite_cd - delta)

	var player := get_tree().get_first_node_in_group("player") as Node3D
	var to_player := Vector3.ZERO
	var dist_to_player := INF
	if player and is_instance_valid(player):
		to_player = player.global_position - global_position
		dist_to_player = Vector2(to_player.x, to_player.z).length()

	# Выбор состояния.
	match _state:
		"idle":
			_wait_timer -= delta
			if dist_to_player <= aggro_range:
				_state = "chase"
			elif _wait_timer <= 0.0:
				_pick_patrol_point()
				_state = "patrol"
		"patrol":
			if dist_to_player <= aggro_range:
				_state = "chase"
			elif global_position.distance_to(_patrol_target) < 1.2:
				_state = "idle"
				_wait_timer = randf_range(1.5, 4.0)
		"chase":
			if dist_to_player > leash_range:
				_state = "flee_home"
			elif dist_to_player > aggro_range * 1.6:
				_state = "flee_home"
		"flee_home":
			if global_position.distance_to(_home) < 2.0:
				_state = "idle"
				_wait_timer = randf_range(1.0, 3.0)
			elif dist_to_player <= aggro_range * 0.7:
				_state = "chase"

	# Целевая точка и скорость.
	var target_pos := _patrol_target
	var speed := walk_speed
	if _state == "chase" and player:
		target_pos = player.global_position
		speed = chase_speed
	elif _state == "flee_home":
		target_pos = _home

	var to := target_pos - global_position
	to.y = 0.0
	var flat := Vector2(global_position.x, global_position.z)
	var tflat := Vector2(target_pos.x, target_pos.z)
	var dist := flat.distance_to(tflat)

	var desired := Vector3.ZERO
	if dist > 0.4:
		desired = to.normalized() * speed
	velocity.x = move_toward(velocity.x, desired.x, speed * 6.0 * delta)
	velocity.z = move_toward(velocity.z, desired.z, speed * 6.0 * delta)

	# Поворот «мордой» к цели (без рывков).
	if dist > 0.2:
		var want_yaw := atan2(-to.x, -to.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, minf(1.0, turn_speed * delta))

	# На месте «нюхает землю» — лёгкое покачивание головы.
	if velocity.length() < 0.3:
		head.rotation.x = sin(Time.get_ticks_msec() * 0.002) * 0.12
	else:
		head.rotation.x = 0.0

	move_and_slide()


## Укус по касанию области головы игрока.
func _on_bite_body(body: Node3D) -> void:
	if _dead or _bite_cd > 0.0:
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(bite_damage)
		_bite_cd = bite_interval


## Урон волку (например, удар игрока). Смертельные прыжки на голову идут через stomped().
func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	_flash_hurt()
	_health = maxf(0.0, _health - amount)
	health_changed.emit(_health, max_health)
	# Рана переключает в агрессию, если игрок рядом.
	if _state in ["idle", "patrol"]:
		_state = "chase"
	if _health <= 0.0:
		_die()


## Вспышка «красного урона»: материалы волка кратковременно краснеют и возвращаются.
func _flash_hurt() -> void:
	for mi in $Visual.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		if not (m.material_override is StandardMaterial3D):
			continue
		var base: Color = _base_colors.get(m.name, m.material_override.albedo_color)
		# Копия материала — чтобы не перекрашивать сразу всех волков (общий ресурс).
		var mat: StandardMaterial3D = m.material_override.duplicate()
		m.material_override = mat
		mat.albedo_color = Color(1.0, 0.12, 0.12, 1.0)
		var tw := create_tween()
		tw.tween_interval(0.14)
		tw.tween_property(mat, "albedo_color", base, 0.35).set_trans(Tween.TRANS_SINE)


## Прыжок игрока на голову — мгновенная смерть.
func stomped() -> void:
	if _dead:
		return
	_health = 0.0
	health_changed.emit(0.0, max_health)
	_die()


func _die() -> void:
	_dead = true
	died.emit(self)
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	bite_area.monitoring = false
	# Падаем «на бок» и исчезаем.
	var tw := create_tween()
	tw.tween_property(self, "rotation:x", deg_to_rad(90), 0.5)
	tw.parallel().tween_property(self, "global_position:y", global_position.y - 0.4, 0.5)
	tw.tween_interval(1.5)
	tw.tween_callback(queue_free)
