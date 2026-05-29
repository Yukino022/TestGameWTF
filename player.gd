extends CharacterBody2D

const SPEED = 300.0
const JUMP_VELOCITY = -450.0
const GRAVITY = 1200.0

@onready var anim: AnimatedSprite2D = $PlayerSprite
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D

var facing_direction := 1
var is_attacking := false
var hit_targets := []


func _ready() -> void:
	add_to_group("player")

	if not anim.animation_finished.is_connected(_on_animation_finished):
		anim.animation_finished.connect(_on_animation_finished)

	if not attack_area.body_entered.is_connected(_on_attack_area_body_entered):
		attack_area.body_entered.connect(_on_attack_area_body_entered)

	attack_shape.disabled = true


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var direction := Input.get_axis("move_left", "move_right")

	if not is_attacking:
		if direction != 0:
			facing_direction = sign(direction)
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_attacking:
		velocity.y = JUMP_VELOCITY

	if Input.is_action_just_pressed("attack") and not is_attacking:
		start_attack()

	move_and_slide()
	update_animation()


func start_attack() -> void:
	is_attacking = true
	hit_targets.clear()

	# AttackArea всегда стоит в центре Player
	attack_area.position = Vector2.ZERO

	# Двигаем только саму форму удара вправо/влево
	attack_shape.position.x = 70 * facing_direction
	attack_shape.position.y = 0

	attack_shape.disabled = false

	if facing_direction > 0:
		play_anim("attack_right")
	else:
		play_anim("attack_left")
#получение урона
func take_damage(amount: int) ->void:
	print("Player took dmg:", amount)

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
		
func _on_animation_finished() -> void:
	if anim.animation == "attack_right" or anim.animation == "attack_left":
		is_attacking = false
		attack_shape.disabled = true
