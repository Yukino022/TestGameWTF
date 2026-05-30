extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -450.0
const GRAVITY = 1200.0

const GROUND_ATTACK_DURATION = 0.35
const AIR_ATTACK_DURATION = 0.28
const INVINCIBILITY_TIME = 0.7

@onready var anim: AnimatedSprite2D = $FullBodySprite
@onready var upper_body_anim: AnimatedSprite2D = $UpperBodySprite
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D

var facing_direction := 1
var is_attacking := false
var attack_is_air := false
var is_invincible := false

var hit_targets := []

signal health_changed(current_hp, max_hp)

var max_health := 100
var current_health := 100


func _ready() -> void:
	add_to_group("player")

	if not attack_area.body_entered.is_connected(_on_attack_area_body_entered):
		attack_area.body_entered.connect(_on_attack_area_body_entered)

	attack_shape.disabled = true
	upper_body_anim.visible = false
	
	current_health = max_health
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	# Гравитация
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var direction := Input.get_axis("move_left", "move_right")

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
			# На земле во время атаки персонаж тормозит
			velocity.x = move_toward(velocity.x, 0, SPEED)
	else:
		if direction != 0:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Прыжок
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY

	# Атака
	if Input.is_action_just_pressed("attack"):
		try_start_attack()

	move_and_slide()
	update_animation()


func update_sprite_direction() -> void:
	var should_flip := facing_direction < 0
	anim.flip_h = should_flip
	upper_body_anim.flip_h = should_flip


func try_start_attack() -> void:
	if is_attacking:
		return

	start_attack()


func start_attack() -> void:
	if is_attacking:
		return

	is_attacking = true
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
		upper_body_anim.visible = true
		upper_body_anim.frame = 0
		upper_body_anim.play("air_attack")
	else:
		upper_body_anim.visible = false
		play_anim("attack")

	# Ждём 1 физический кадр, чтобы Godot обновил пересечения
	await get_tree().physics_frame

	# Если враг уже был внутри хитбокса, проверяем вручную
	for body in attack_area.get_overlapping_bodies():
		_on_attack_area_body_entered(body)

	var duration := AIR_ATTACK_DURATION if attack_is_air else GROUND_ATTACK_DURATION

	await get_tree().create_timer(duration).timeout

	is_attacking = false
	attack_is_air = false
	attack_shape.disabled = true
	upper_body_anim.visible = false

	update_animation()


func take_damage(amount: int) -> void:
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

	await get_tree().create_timer(INVINCIBILITY_TIME).timeout
	is_invincible = false


func die() -> void:
	print("Игрок умер")
	# Тут позже добавим смерть / рестарт / анимацию


func update_animation() -> void:
	if is_attacking:
		return

	if not is_on_floor():
		play_anim("jump")
		return

	if abs(velocity.x) > 10:
		play_anim("run")
		return

	play_anim("idle")


func play_anim(animation_name: String) -> void:
	if anim.animation != animation_name:
		anim.play(animation_name)


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
