extends Control
## HUD: полоски здоровья и выносливости. Подключается к игроку через сигнал.

@onready var health_bar: ProgressBar = %HealthBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var stamina_label: Label = %StaminaLabel


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_signal("stamina_changed"):
		player.stamina_changed.connect(_on_stamina_changed)


func _on_stamina_changed(current: float, maximum: float, exhausted: bool) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	if exhausted:
		stamina_bar.modulate = Color(0.6, 0.3, 0.3)
		stamina_label.text = "ВЫ ИСТОЩЕНЫ"
	else:
		stamina_bar.modulate = Color.WHITE
		stamina_label.text = "Выносливость: %d" % int(round(current))


func set_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
