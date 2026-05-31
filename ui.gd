extends CanvasLayer

@onready var player_hp_bar = $PlayerHealthBar
@onready var boss_hp_bar = $BossHealthBar
@onready var player = $"../Player"
@onready var boss = $"../Enemy"
@onready var camera_effects_check_button = $CameraEffectsCheckButton
@onready var player_camera = $"../Player/Camera2D"

func _ready():
	print("UI: Скрипт запущен!")
	camera_effects_check_button.toggled.connect(_on_camera_effects_toggled)
	if player:
		player.health_changed.connect(_on_player_health_changed)
		print("UI: Подключился к игроку")
	
	if boss:
		boss.health_changed.connect(_on_boss_health_changed)
		boss.aggro_started.connect(_on_boss_aggro_started)
		print("UI: Подключился к боссу")
	else:
		print("UI ОШИБКА: Не нашел узел босса по пути!")
	# Сразу задаем значения полоскам при старте
	if player:
		_on_player_health_changed(player.current_health, player.max_health)
	
	if boss:
		# Для босса тоже задаем значения заранее, хоть полоска и скрыта
		boss_hp_bar.max_value = boss.max_health
		boss_hp_bar.value = boss.current_health
	
# Функция, которая срабатывает, когда меняется ХП игрока
func _on_player_health_changed(current_hp, max_hp):
	player_hp_bar.max_value = max_hp
	player_hp_bar.value = current_hp

# Функция, которая срабатывает, когда меняется ХП босса
func _on_boss_health_changed(current_hp, max_hp):
	print("UI: ХП БОССА ИЗМЕНИЛОСЬ!")
	boss_hp_bar.max_value = max_hp
	boss_hp_bar.value = current_hp
	if boss.current_health <= 0:
		boss_hp_bar.hide()

# Функция, которая срабатывает, когда босс агрится
func _on_boss_aggro_started():
	print("UI: Я ПОЛУЧИЛ СИГНАЛ АГРА!")
	boss_hp_bar.show() # Показываем полоску босса

func _on_camera_effects_toggled(enabled: bool) -> void:
	if player_camera and player_camera.has_method("set_camera_effects_enabled"):
		player_camera.set_camera_effects_enabled(enabled)
