extends Camera2D

# Насколько камера смотрит вперёд по X
const LOOK_AHEAD_X = 30.0

# Насколько быстро камера догоняет target offset
const CAMERA_SMOOTH_SPEED = 8.0

# Покачивание при ходьбе/беге
const WALK_BOB_AMOUNT = 2.0
const RUN_BOB_AMOUNT = 4.0
const BOB_SPEED = 10.0

# Скорость затухания толчка от атаки
const KICK_RETURN_SPEED = 10.0

@onready var player = get_parent()


var camera_effects_enabled := true
var current_offset := Vector2.ZERO
var kick_offset := Vector2.ZERO
var shake_offset := Vector2.ZERO

var shake_strength := 0.0
var shake_time := 0.0

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func _process(delta: float) -> void:
	var target_offset := Vector2.ZERO

	# 1. Look ahead — камера смотрит немного в сторону движения/направления игрока
	if abs(player.velocity.x) > 20:
		target_offset.x = sign(player.velocity.x) * LOOK_AHEAD_X
	else:
		target_offset.x = player.facing_direction * LOOK_AHEAD_X * 0.35

	# 2. Bob — лёгкое покачивание при движении по земле
	if camera_effects_enabled and player.is_on_floor() and abs(player.velocity.x) > 20 and not player.is_attacking:
		var bob_amount := WALK_BOB_AMOUNT

		if Input.is_action_pressed("run"):
			bob_amount = RUN_BOB_AMOUNT

		var time := Time.get_ticks_msec() / 1000.0
		target_offset.y += sin(time * BOB_SPEED) * bob_amount

	# Плавно двигаем камеру к нужному offset
	current_offset = current_offset.lerp(target_offset, CAMERA_SMOOTH_SPEED * delta)

	# 3. Attack kick постепенно возвращается в 0
	kick_offset = kick_offset.lerp(Vector2.ZERO, KICK_RETURN_SPEED * delta)

	# 4. Screenshake
	update_shake(delta)

	# Финальный offset камеры
	offset = current_offset + kick_offset + shake_offset

func set_camera_effects_enabled(value: bool) -> void:
	camera_effects_enabled = value

	if not camera_effects_enabled:
		kick_offset = Vector2.ZERO
		shake_offset = Vector2.ZERO
		shake_strength = 0.0
		shake_time = 0.0
		offset = current_offset


func attack_kick(direction: int) -> void:
	# Маленький толчок камеры в сторону удара
	if not camera_effects_enabled:
		return
	kick_offset.x += 6.0 * direction
	kick_offset.y -= 1.0


func shake(strength: float, duration: float) -> void:
	if not camera_effects_enabled:
		return
	shake_strength = max(shake_strength, strength)
	shake_time = max(shake_time, duration)


func update_shake(delta: float) -> void:
	if shake_time > 0:
		shake_time -= delta

		shake_offset = Vector2(
			rng.randf_range(-shake_strength, shake_strength),
			rng.randf_range(-shake_strength, shake_strength)
		)

		if shake_time <= 0:
			shake_offset = Vector2.ZERO
	else:
		shake_offset = Vector2.ZERO
