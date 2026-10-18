extends Control
## HUD: красная полоска здоровья и зелёная полоска выносливости.
## Значения меняются в реальном времени через сигналы игрока.

@onready var health_bar: ProgressBar = %HealthBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var health_label: Label = %HealthLabel
@onready var stamina_label: Label = %StaminaLabel
@onready var stats_label: Label = %StatsLabel
@onready var toast: Label = %LootToast

var player: Node3D = null
var _toast_timer := 0.0


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	if player and player.has_signal("stamina_changed"):
		player.stamina_changed.connect(_on_stamina_changed)
	if player and player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player and player.has_signal("loot_received"):
		player.loot_received.connect(_on_loot_received)
	# Начальные значения.
	if player:
		if "health_max" in player:
			set_health(player.health_max, player.health_max)
		if "stamina_max" in player:
			_on_stamina_changed(player.stamina_max, player.stamina_max, false)
	_refresh_stats()


func _on_stamina_changed(current: float, maximum: float, exhausted: bool) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	if exhausted:
		stamina_bar.modulate = Color(0.45, 0.7, 0.45)
		stamina_label.text = "ВЫ ИСТОЩЕНЫ"
	else:
		stamina_bar.modulate = Color.WHITE
		stamina_label.text = "Выносливость: %d / %d" % [int(round(current)), int(round(maximum))]


func _on_health_changed(current: float, maximum: float) -> void:
	set_health(current, maximum)


## Обновляет красную полоску HP: чем меньше здоровья — тем темнее/насыщеннее красный.
func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	var ratio := clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	# От ярко-красного к тёмно-бордовому по мере убывания HP.
	health_bar.modulate = Color(1.0, 0.35 + 0.25 * ratio, 0.35 + 0.2 * ratio).lerp(Color(0.55, 0.1, 0.1), 1.0 - ratio)
	health_label.text = "Здоровье: %d / %d" % [int(round(current)), int(round(maximum))]


func _on_loot_received(reward: Dictionary) -> void:
	if toast != null:
		toast.text = String(reward.get("text", ""))
		toast.modulate = Color(1, 1, 1, 1)
		toast.visible = true
		if toast.has_method("get_tree"):
			pass
	_toast_timer = 3.0
	_refresh_stats()


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and toast != null:
			toast.visible = false


func _refresh_stats() -> void:
	if player == null or not is_instance_valid(player):
		return
	if stats_label != null:
		stats_label.text = "Золото: %d   |   Урон кулака: %d" % [
			int(player.gold), int(round(player.punch_damage + player.punch_bonus))
		]
