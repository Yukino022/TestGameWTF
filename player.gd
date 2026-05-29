extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -450.0
const GRAVITY = 1200.0
const GROUND_ATTACK_DURATION = 0.35
const AIR_ATTACK_DURATION = 0.28
const AIR_COMBO_RESET_TIME = 0.5
const AIR_COMBO_MAX=3


@onready var anim: AnimatedSprite2D = $PlayerSprite
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D

var facing_direction := 1
var is_attacking := false
#воздушные атаки
var attack_is_air := false 
var air_combo_step := 0
var last_air_attack_time:= 0.0

var hit_targets := []


func _ready() -> void:
	add_to_group("player")
	if not attack_area.body_entered.is_connected(_on_attack_area_body_entered):
		attack_area.body_entered.connect(_on_attack_area_body_entered)

	attack_shape.disabled = true

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		air_combo_step = 0

	var direction := Input.get_axis("move_left", "move_right")

	if direction >0:
		facing_direction = 1
	elif  direction <0:
		facing_direction = -1
	
	if is_attacking:
		if attack_is_air:
		#позволяет двигаться в воздухе
			if direction !=0:
				velocity.x = direction *SPEED
		else:
			#afk на земле во время атаки (в будущем меняем)
			velocity.x = move_toward(velocity.x, 0, SPEED)
	else:
		if direction != 0:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
	#Jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY
	if Input.is_action_just_pressed("attack"):
		try_start_attack()

	move_and_slide()
	update_animation()

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
	
	# AttackArea всегда стоит в центре Player
	attack_area.position = Vector2.ZERO
	# Двигаем только саму форму удара вправо/влево
	attack_shape.position.x = 70 * facing_direction
	attack_shape.position.y = 0
	attack_shape.disabled = false
	if attack_is_air:
		update_air_combo()
		play_air_attack_animation()
	else:
		if facing_direction > 0:
			play_anim("attack_right")
		else:
			play_anim("attack_left")
	if facing_direction > 0:
		play_anim("attack_right")
	else:
		play_anim("attack_left")
	# Ждём 1 физический кадр, чтобы Godot обновил пересечения
	await get_tree().physics_frame
		# Если враг уже был внутри хитбокса, проверяем вручную
	for body in attack_area.get_overlapping_bodies():
		_on_attack_area_body_entered(body)

	# Разная длительность для земли и воздуха
	var duration := AIR_ATTACK_DURATION if attack_is_air else GROUND_ATTACK_DURATION

	await get_tree().create_timer(duration).timeout
	
	is_attacking = false
	attack_is_air = false
	attack_shape.disabled = true
	
	update_animation()
func update_air_combo() -> void:
	var current_time := Time.get_ticks_msec() /1000
	if current_time - last_air_attack_time > AIR_COMBO_RESET_TIME:
		air_combo_step = 0
	air_combo_step += 1
	if air_combo_step > AIR_COMBO_MAX:
		air_combo_step = 1
	last_air_attack_time = current_time
	
#получение урона
func take_damage(amount: int) ->void:
	print("Player took dmg:", amount)
#обновление анимаций
func update_animation() -> void:
	if is_attacking:
		return

	if not is_on_floor():
		if facing_direction > 0:
			play_anim("jump_right")
		else:
			play_anim("jump_left")
		return

	if abs(velocity.x) > 10:
		if velocity.x > 0:
			play_anim("walk_right")
		else:
			play_anim("walk_left")
		return

	play_anim("idle")
func play_air_attack_animation() -> void:
	var direction_name := "right" if facing_direction > 0 else "left"

	var combo_animation := "air_attack_%d_%s" % [air_combo_step, direction_name]
	var fallback_animation := "air_attack_%s" % direction_name
	var ground_fallback := "attack_%s" % direction_name

	if anim.sprite_frames != null and anim.sprite_frames.has_animation(combo_animation):
		play_anim(combo_animation)
	elif anim.sprite_frames != null and anim.sprite_frames.has_animation(fallback_animation):
		play_anim(fallback_animation)
	else:
		play_anim(ground_fallback)
func play_anim(animation_name: String) -> void:
	if anim.animation != animation_name:
		anim.play(animation_name)
#позволяет атаковать врага и не получать урон от самого себя, сюда же можно добавить переменную с уроном в последнюю строчку
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
		
