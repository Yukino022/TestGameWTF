extends CharacterBody2D
#Основные константы 
const SPEED = 300.0
const JUMP_VELOCITY = -450.0
const GRAVITY = 1200.0
#Константы для атак
const ATTACK_ACTIVE_TIME = 0.12
const GROUND_ATTACK_DURATION = 0.35
const GROUND_ATTACK_RECOVERY_TIME = 0.20
const AIR_ATTACK_DURATION = 0.28
const AIR_ATTACK_RECOVERY_TIME = 0.12
const INVINCIBILITY_TIME = 0.7
const ATTACK_MOVE_MULTIPLIER = 0.45
const ROLL_SPEED = 350.0
const ROLL_DURATION = 0.6

@onready var anim: AnimatedSprite2D = $FullBodySprite
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
#Переменные 
var facing_direction := 1
var current_weapon := "unarmed"

var can_cancel_attack := false
var attack_id := 0
var is_attacking := false
var attack_is_air := false
var is_invincible := false
var is_rolling = false
var hit_targets := []

signal health_changed(current_hp, max_hp)

var max_health := 100
var current_health := 100

#MAIN FUNCTIONS 
signal player_died
var is_dead = false

func _ready() -> void:
	add_to_group("player")

	if not attack_area.body_entered.is_connected(_on_attack_area_body_entered):
		attack_area.body_entered.connect(_on_attack_area_body_entered)

	attack_shape.disabled = true
	
	current_health = max_health
	health_changed.emit(current_health, max_health)

func _physics_process(delta: float) -> void:
	# Гравитация
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var direction := Input.get_axis("move_left", "move_right")
	
	if Input.is_action_just_pressed("roll") and is_on_floor() and not is_rolling:
		# Можно кувыркаться, если не атакуем ИЛИ если атаку можно отменить
		if not is_attacking or can_cancel_attack:
			if is_attacking:
				cancel_attack() # Отменяем удар, если кувыркнулись во время него
			start_roll()

	# Если кувырок начался, мы просто катимся и выходим из физики
	if is_rolling:
		move_and_slide()
		return
		
	# Запоминаем направление взгляда
	if direction > 0:
		facing_direction = 1
	elif direction < 0:
		facing_direction = -1

	update_sprite_direction()

	# Движение
	if is_attacking:
		if attack_is_air:
			# В воздухе во время атаки можно двигаться
			if direction != 0:
				velocity.x = direction * SPEED
		else:
			if can_cancel_attack:
				if direction !=0:
					velocity.x = direction * SPEED * ATTACK_MOVE_MULTIPLIER
				else:
					velocity.x = move_toward(velocity.x, 0, SPEED)
			else:
				velocity.x = move_toward(velocity.x, 0, SPEED)
	else:
		if direction != 0:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Прыжок
	if Input.is_action_just_pressed("jump") and is_on_floor():
		if is_attacking:
			if can_cancel_attack:
				cancel_attack()
				velocity.y = JUMP_VELOCITY
		else:
			velocity.y = JUMP_VELOCITY
# Смена оружия
	if Input.is_action_just_pressed("weapon_unarmed"):
		equip_weapon("unarmed")

	if Input.is_action_just_pressed("weapon_katana"):
		equip_weapon("katana")

	if Input.is_action_just_pressed("weapon_sword"):
		equip_weapon("sword")
# Атака
	if Input.is_action_just_pressed("attack"):
		try_start_attack()

	move_and_slide()
	update_animation()
	
	
func update_sprite_direction() -> void:
	var should_flip := facing_direction < 0
	anim.flip_h = should_flip

func update_sprite_direction() -> void:
	var should_flip := facing_direction < 0
	anim.flip_h = should_flip
#Ralated to attack functions
func equip_weapon(weapon_name: String) -> void:
	if is_attacking:
		return

	if current_weapon == weapon_name:
		return

	current_weapon = weapon_name
	update_animation()
func try_start_attack() -> void:
	if is_attacking:
		return

	start_attack()
func start_attack() -> void:
	if is_attacking:
		return

	attack_id += 1
	var current_attack_id := attack_id

	is_attacking = true
	can_cancel_attack = false
	attack_is_air = not is_on_floor()
	hit_targets.clear()

	# AttackArea всегда остаётся в центре Player
	attack_area.position = Vector2.ZERO

	# Двигаем только форму удара вправо/влево
	attack_shape.position.x = 70 * facing_direction
	attack_shape.position.y = 0
	attack_shape.disabled = false

	# Выбор анимации атаки
	if attack_is_air:
		play_anim("jump")
		play_anim("air_attack")
	else:
		play_anim("attack")

	# Ждём 1 физический кадр, чтобы Godot обновил пересечения
	await get_tree().physics_frame

	for body in attack_area.get_overlapping_bodies():
		_on_attack_area_body_entered(body)

	# Active frames: здесь удар реально наносит урон
	await get_tree().create_timer(ATTACK_ACTIVE_TIME).timeout

	if current_attack_id != attack_id:
		return

	# После active frames хитбокс выключаем
	attack_shape.disabled = true

	# Теперь атаку можно отменить
	can_cancel_attack = true

	var recovery_time := AIR_ATTACK_RECOVERY_TIME if attack_is_air else GROUND_ATTACK_RECOVERY_TIME

	await get_tree().create_timer(recovery_time).timeout

	if current_attack_id != attack_id:
		return

	end_attack()
func cancel_attack() -> void:
	if not is_attacking:
		return

	if not can_cancel_attack:
		return

	attack_id += 1
	end_attack()
func _on_attack_area_body_entered(body: Node) -> void:
	if not is_attacking:
		return

	# Не бьём самого себя
	if body == self:
		return

	# Бьём только врагов
	if not body.is_in_group("enemy"):
		return

	# Не бьём одного и того же врага дважды за одну атаку
	if body in hit_targets:
		return

	if body.has_method("take_damage"):
		hit_targets.append(body)
		body.take_damage(1)
func end_attack() -> void:
	is_attacking = false
	attack_is_air = false
	can_cancel_attack = false
	attack_shape.disabled = true

	update_animation()
#CHARACTER RELATED (DMG TAKEN ETC.)
func take_damage(amount: int) -> void:
	if is_rolling:
		print("Уворот! Урон проигнорирован.")
		return 

	# 2. Если мы просто в ай-фреймах после прошлого удара - игнорируем
	if is_invincible:
		return

	is_invincible = true

	print("Player took dmg:", amount)

	current_health -= amount

	if current_health < 0:
		current_health = 0

	health_changed.emit(current_health, max_health)

	if current_health == 0:
		die()
		return

	# Таймер неуязвимости ПОСЛЕ получения урона
	await get_tree().create_timer(INVINCIBILITY_TIME).timeout
	is_invincible = false

func start_roll():
	is_rolling = true
	play_anim("roll")
	
	var direction = Input.get_axis("move_left", "move_right")
	if direction == 0:
		direction = facing_direction
		
	velocity.x = direction * ROLL_SPEED
	
	await get_tree().create_timer(ROLL_DURATION).timeout
	
	if is_dead: return # Защита: вдруг убили во время кувырка
	
	# Заканчиваем кувырок
	is_rolling = false
	velocity.x = 0
	update_animation() # Возвращаем анимацию ходьбы/стояния

func die() -> void:
	print("Игрок умер")
	if is_dead: return
	
	is_dead = true
	player_died.emit() # Отправляем сигнал интерфейсу показать текст
	
	# Выключаем физику, чтобы труп не ходил
	set_physics_process(false) 
	
	anim.play("death") 
	anim.offset = Vector2(0, 0)
	
	# Ждем 2 секунды (чтобы игрок посмотрел анимацию и осознал поражение)
	await get_tree().create_timer(2.0).timeout
	
	#  (респаун)
	get_tree().reload_current_scene()

func update_animation() -> void:
	if is_attacking:
		return

	if not is_on_floor():
		play_anim("jump")
		return

	var direction := Input.get_axis("move_left", "move_right")

	if direction != 0:
		play_movement_anim("run")
		return

	play_movement_anim("idle")
func play_anim(animation_name: String) -> void:
	if anim.animation != animation_name:
		anim.play(animation_name)
func play_movement_anim(base_name: String) -> void:
	var weapon_anim := "%s_%s" % [base_name, current_weapon]

	if anim.sprite_frames != null and anim.sprite_frames.has_animation(weapon_anim):
		play_anim(weapon_anim)
		return

	if base_name == "idle" and current_weapon == "katana":
		if anim.sprite_frames != null and anim.sprite_frames.has_animation("idle_sword"):
			play_anim("idle_sword")
			return

	if base_name == "run" and current_weapon == "sword":
		if anim.sprite_frames != null and anim.sprite_frames.has_animation("run_unarmed"):
			play_anim("run_unarmed")
			return

	var unarmed_fallback := "%s_unarmed" % base_name

	if anim.sprite_frames != null and anim.sprite_frames.has_animation(unarmed_fallback):
		play_anim(unarmed_fallback)
		return

	if anim.sprite_frames != null and anim.sprite_frames.has_animation(base_name):
		play_anim(base_name)
		return

	play_anim("idle_unarmed")
