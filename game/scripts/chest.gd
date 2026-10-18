extends StaticBody3D
## Сундук — случайный лут (RPG-переменные при каждом открытии).
## Открывается ударом кулака или клавишей E рядом с ним.

@export var open_sound_hint := "sfx_chest"

signal looted(reward: Dictionary)

var _opened := false

@onready var lid: MeshInstance3D = $Visual/Lid


func _ready() -> void:
	add_to_group("chests")


## Вызывается из player.gd при ударе/взаимодействии.
func interact() -> void:
	if _opened:
		return
	_opened = true
	var reward := _roll_reward()
	looted.emit(reward)
	# Анимация: крышка откидывается, сундук подсвечивается золотом.
	lid.rotation_degrees.x = -105.0
	collision_layer = 0
	set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)


func _roll_reward() -> Dictionary:
	## Таблица весов — «случайные переменные из RPG»: золото, зелье, усиление кулака.
	var roll := randf()
	if roll < 0.45:
		var gold := int(randf_range(3, 26))
		return {"type": "gold", "amount": gold, "text": "Найдено золота: %d" % gold}
	elif roll < 0.80:
		return {"type": "potion", "heal": 20, "text": "Зелье лечения (+20 HP)"}
	else:
		var bonus := int(randf_range(1, 4))
		return {"type": "gauntlet", "damage_bonus": bonus, "text": "Кулак +%d урона!" % bonus}
