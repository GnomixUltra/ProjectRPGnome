extends CharacterBody3D
## Контроллер игрока от первого лица: WASD, бег на Shift, прыжок, выносливость,
## удар кулаком (ЛКМ) — можно отбиваться от волков и убивать их.

# --- Скорости ---
@export var walk_speed := 5.0
@export var sprint_speed := 9.0
@export var jump_velocity := 6.0          # м/с вверх
@export var mouse_sensitivity := 0.0025   # радиан на пиксель

# --- Выносливость ---
@export var stamina_max := 100.0
@export var stamina_drain := 22.0         # трата за секунду бега
@export var stamina_regen := 14.0         # восстановление за секунду
@export var exhausted_threshold := 15.0   # ниже — истощение, бег недоступен до восстановления выше
@export var recover_above := 40.0         # пороговое значение для выхода из истощения

# --- Здоровье ---
@export var health_max := 100.0
@export var health_regen_rate := 1.5      # HP/с — медленная регенерация в покое
@export var health_regen_delay := 6.0     # с — пауза после урона перед регенерацией

# --- Кулак (ближний бой) ---
@export var punch_damage := 14.0          # урон кулака по врагу
@export var punch_cooldown := 0.45        # с — минимальная пауза между ударами
@export var punch_stamina_cost := 6.0     # трата выносливости за удар
@export var punch_range := 2.3            # м — дистанция поражения удара
@export var punch_arc_degrees := 70.0     # ° — конус «в поле зрения» для попадания

signal stamina_changed(current: float, maximum: float, exhausted: bool)
signal health_changed(current: float, maximum: float)
signal died
signal punched                       # для анимации/звука (зарезервировано)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var fist_pivot: Node3D = $Head/Camera3D/FistPivot
@onready var fist: Node3D = $Head/Camera3D/FistPivot/Fist

var _stamina := stamina_max
var _exhausted := false
var _health := health_max
var _hurt_time := 999.0                   # время последней раны (для регенерации)
var _dead := false
var _yaw := 0.0
var _pitch := 0.0
var _punch_cd := 0.0                      # кулдаун удара, с
var _punching := false                    # идёт ли анимация замаха


func _ready() -> void:
	_stamina = stamina_max
	_health = health_max
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true


func _process(delta: float) -> void:
	if _dead:
		return
	_punch_cd = maxf(0.0, _punch_cd - delta)
	# Медленная регенерация здоровья, если давно не получали урон.
	if _health < health_max and _hurt_time >= health_regen_delay:
		_health = minf(health_max, _health + health_regen_rate * delta)
		health_changed.emit(_health, health_max)
	_hurt_time += delta


## Нанести урон игроку (вызывается волками и прочими источниками).
func take_damage(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	_health = maxf(0.0, _health - amount)
	_hurt_time = 0.0
	health_changed.emit(_health, health_max)
	if _health <= 0.0:
		_die()


func heal(amount: float) -> void:
	if _dead or amount <= 0.0:
		return
	_health = minf(health_max, _health + amount)
	health_changed.emit(_health, health_max)


func _die() -> void:
	_dead = true
	died.emit()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Респавн через пару секунд.
	var tree := get_tree()
	await tree.create_timer(2.0).timeout
	_respawn()


func _respawn() -> void:
	_health = health_max
	_stamina = stamina_max
	_exhausted = false
	_dead = false
	health_changed.emit(_health, health_max)
	stamina_changed.emit(_stamina, stamina_max, false)
	global_position = Vector3(0.0, 2.0, 0.0)
	velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Обзор мышью
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-89.0), deg_to_rad(89.0))
		rotation.y = _yaw
		head.rotation.x = _pitch
	# Отпустить мышь — ESC, вернуть — клик по окну
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_ENTER:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Удар кулаком — левая кнопка мыши (или клавиша F).
	var punch_pressed := false
	if event is InputEventMouseButton:
		punch_pressed = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventKey:
		punch_pressed = event.pressed and not event.echo and event.keycode == KEY_F
	if punch_pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_punch()


## Попытка удара кулаком: проверка кулдауна/стамины, замах, поражение врагов в конусе.
func _try_punch() -> void:
	if _dead or _punching or _punch_cd > 0.0:
		return
	if _stamina < punch_stamina_cost:
		return
	_punching = true
	_punch_cd = punch_cooldown
	_stamina = maxf(0.0, _stamina - punch_stamina_cost)
	if _stamina <= 0.0:
		_exhausted = true
	stamina_changed.emit(_stamina, stamina_max, _exhausted)
	punched.emit()

	# Поражение целей из группы "enemies" в конусе перед игроком.
	var from := global_position + Vector3(0.0, 1.4, 0.0)
	var fwd := -global_transform.basis.z.normalized()
	for body in get_tree().get_nodes_in_group("enemies"):
		if not (body is Node3D) or not is_instance_valid(body):
			continue
		var b := body as Node3D
		var to := b.global_position + Vector3(0.0, 1.2, 0.0) - from
		var dist := to.length()
		if dist > punch_range:
			continue
		if to.normalized().dot(fwd) < cos(deg_to_rad(punch_arc_degrees * 0.5)):
			continue
		# Проверка «линии удара» только против статичной геометрии мира (слой World):
		# земля/камни блокируют удар, враги и персонажи — нет. Точка цели берётся
		# чуть выше головы врага, чтобы луч не цеплял траву под ногами.
		var ray_from := global_position + Vector3(0.0, 1.7, 0.0)
		var ray_to := b.global_position + Vector3(0.0, 1.9, 0.0)
		var hit := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1, [get_rid()])
		var obstacle := get_world_3d().direct_space_state.intersect_ray(hit)
		if not obstacle.is_empty():
			continue
		if b.has_method("take_damage"):
			b.take_damage(punch_damage)

	# Анимация замаха: быстрый выпад вперёд, возврат в исходную позицию.
	fist.visible = true
	var rest := Vector3(0.32, -0.26, -0.45)
	var out := Vector3(0.22, -0.16, -0.95)
	fist.position = rest
	var tw := create_tween()
	tw.tween_property(fist, "position", out, 0.09).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.04)
	tw.tween_property(fist, "position", rest, 0.16).set_ease(Tween.EASE_IN)
	tw.tween_callback(_finish_punch)


func _finish_punch() -> void:
	_punching = false
	fist.visible = false


func _physics_process(delta: float) -> void:
	if _dead:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	# Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Прыжок
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Бег / выносливость
	var wants_sprint := Input.is_action_pressed("sprint")
	var moving := false

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	moving = direction != Vector3.ZERO

	var sprinting := wants_sprint and moving and not _exhausted and is_on_floor()

	if sprinting:
		_stamina -= stamina_drain * delta
		if _stamina <= 0.0:
			_stamina = 0.0
			_exhausted = true
	else:
		_stamina = min(stamina_max, _stamina + stamina_regen * delta)
		if _exhausted and _stamina >= recover_above:
			_exhausted = false
	stamina_changed.emit(_stamina, stamina_max, _exhausted)

	# Движение
	var target := Vector3.ZERO
	var speed := sprint_speed if sprinting else walk_speed
	if direction != Vector3.ZERO:
		target = direction * speed
	velocity.x = move_toward(velocity.x, target.x, speed * 10.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, speed * 10.0 * delta)

	move_and_slide()
