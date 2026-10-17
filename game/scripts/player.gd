extends CharacterBody3D
## Контроллер игрока от первого лица: WASD, бег на Shift, прыжок, выносливость.

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

signal stamina_changed(current: float, maximum: float, exhausted: bool)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _stamina := stamina_max
var _exhausted := false
var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	_stamina = stamina_max
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.current = true


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


func _physics_process(delta: float) -> void:
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
