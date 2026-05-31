extends CharacterBody2D

const GRAVITY = 1200.0
const JUMP_FORCE = -550.0
const AOE_DAMAGE = 20
const SELF_DAMAGE_ON_LAND = 5

@onready var anim: AnimatedSprite2D = $EnemySprite
@onready var aoe_area: Area2D = $AOEArea
@onready var aoe_shape: CollisionShape2D = $AOEArea/CollisionShape2D
@onready var aoe_visual: AnimatedSprite2D = $AOEArea/AOEVisual
@onready var attack_timer: Timer = $AttackTimer

signal health_changed(current_hp, max_hp)
signal aggro_started # Сигнал, что босс сагрился

var max_health = 500
var current_health = 500
var is_aggroed = false # Состояние агра
var is_awake := false
var is_attacking := false
var has_left_floor := false
var already_hit_targets := []

func _ready() -> void:
	current_health = max_health
	add_to_group("enemy")

	anim.play("idle_unaware")

	aoe_visual.visible = false
	aoe_shape.disabled = true

	attack_timer.wait_time = 2.0
	attack_timer.one_shot = true

	if not attack_timer.timeout.is_connected(_on_attack_timer_timeout):
		attack_timer.timeout.connect(_on_attack_timer_timeout)

	if not aoe_area.body_entered.is_connected(_on_aoe_body_entered):
		aoe_area.body_entered.connect(_on_aoe_body_entered)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	move_and_slide()

	# Враг реально оторвался от пола
	if is_attacking and not is_on_floor():
		has_left_floor = true

	# AOE только после того, как он сначала оторвался, а потом приземлился
	if is_attacking and has_left_floor and is_on_floor():
		land_attack()

func take_damage(amount: int) -> void:
	print("БОСС ПОЛУЧИЛ УРОН!")
	
	current_health -= amount
	
	# Если босс еще не был в агре, переводим его в агро и шлем сигнал
	if not is_aggroed:
		is_aggroed = true
		is_awake = true
		aggro_started.emit()
		if attack_timer.is_stopped():
			attack_timer.start() 
		print("БОСС: Я проснулся и запустил таймер атаки!")
		
	if current_health < 0:
		current_health = 0
		
	health_changed.emit(current_health, max_health)
	
	if current_health == 0:
		die()

func die():
	print("Босс повержен")
	queue_free() # Удаляем босса

func wake_up() -> void:
	is_awake = true
	anim.play("idle_combat")
	attack_timer.start()

func _on_attack_timer_timeout() -> void:
	if is_awake and not is_attacking:
		start_jump_attack()

func start_jump_attack() -> void:
	print("Enemy jumps")

	is_attacking = true
	has_left_floor = false
	already_hit_targets.clear()

	anim.play("jump_attack")
	velocity.y = JUMP_FORCE

func land_attack() -> void:
	print("Enemy landed, AOE attack")

	is_attacking = false
	has_left_floor = false
	velocity.y = 0

# Самоповреждение босса при ударе об землю
	current_health -= SELF_DAMAGE_ON_LAND
	print("Enemy hurt himself. HP: ", current_health)
	
	# Сообщаем интерфейсу, что ХП босса изменилось после удара об землю
	health_changed.emit(current_health, max_health)

	if current_health <= 0:
		queue_free()
		return

	# Показываем AOE-картинку
	aoe_visual.visible = true
	aoe_visual.frame = 0

	# Если AOEVisual всё ещё AnimatedSprite2D
	if aoe_visual.sprite_frames != null and aoe_visual.sprite_frames.has_animation("aoe"):
		aoe_visual.play("aoe")

	# Включаем AOE-хитбокс
	already_hit_targets.clear()
	aoe_shape.disabled = false

	# Ждём один физический кадр, чтобы Godot обновил пересечения
	await get_tree().physics_frame

	# Проверяем тех, кто уже стоял внутри зоны
	for body in aoe_area.get_overlapping_bodies():
		_on_aoe_body_entered(body)

	# Хитбокс урона активен 0.2 секунды
	await get_tree().create_timer(0.2).timeout
	aoe_shape.disabled = true

	# Картинку AOE можно оставить чуть дольше для визуала
	await get_tree().create_timer(0.15).timeout

	aoe_visual.visible = false
	aoe_visual.stop()

	anim.play("idle_combat")

	print("Enemy starts waiting for next attack")
	attack_timer.start()

	# Визуальная AOE-анимация
	aoe_visual.visible = true
	aoe_visual.frame = 0
	aoe_visual.play("aoe")

	# Включаем AOE-хитбокс
	already_hit_targets.clear()
	aoe_shape.disabled = false

	await get_tree().physics_frame

	# Проверяем тех, кто уже стоял внутри AOE
	for body in aoe_area.get_overlapping_bodies():
		_on_aoe_body_entered(body)

	# Окно урона
	await get_tree().create_timer(0.2).timeout
	aoe_shape.disabled = true

	# Ждём конец анимации AOE
	
	await get_tree().create_timer(0.15).timeout
	aoe_visual.visible = false
	aoe_visual.stop()

	anim.play("idle_combat")
	attack_timer.start()

func _on_aoe_body_entered(body: Node) -> void:
	if body in already_hit_targets:
		return

	# AOE бьёт только игрока.
	# Самоповреждение босса уже происходит в land_attack()
	if not body.is_in_group("player"):
		return

	if body.has_method("take_damage"):
		already_hit_targets.append(body)
		body.take_damage(AOE_DAMAGE)
		
