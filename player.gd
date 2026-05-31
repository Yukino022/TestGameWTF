extends CharacterBody2D

# =============================================================================
# PLAYER SCRIPT
# -----------------------------------------------------------------------------
# Отвечает за:
# - движение игрока
# - прыжок и jump-анимацию по velocity.y
# - смену оружия
# - атаки, урон, cancel window
# - roll / dodge
# - soft/hard landing
# - получение урона, i-frames, смерть
# =============================================================================


# =============================================================================
# 1. BASE MOVEMENT SETTINGS
# =============================================================================
const SPEED = 300.0
const JUMP_VELOCITY = -450.0
const GRAVITY = 1200.0

const WALK_SPEED = 180.0
const RUN_SPEED = 300.0

# =============================================================================
# 2. ATTACK SETTINGS
# -----------------------------------------------------------------------------
# ATTACK_ACTIVE_TIME — сколько времени работает хитбокс удара.
# CANCEL_TIME — момент, с которого атаку можно отменить.
# TOTAL_TIME — полная длительность атаки, если игрок её не отменил.
#
# Важно:
# ATTACK_ACTIVE_TIME < CANCEL_TIME < TOTAL_TIME
# =============================================================================
const ATTACK_ACTIVE_TIME = 0.12
const CANCEL_INPUT_BUFFER_TIME = 0.15

const GROUND_ATTACK_CANCEL_TIME = 0.22
const AIR_ATTACK_CANCEL_TIME = 0.16

const GROUND_ATTACK_TOTAL_TIME = 0.55
const AIR_ATTACK_TOTAL_TIME = 0.40

const ATTACK_MOVE_MULTIPLIER = 0.45


# =============================================================================
# 3. DAMAGE / INVINCIBILITY SETTINGS
# =============================================================================
const INVINCIBILITY_TIME = 0.7


# =============================================================================
# 4. ROLL SETTINGS
# =============================================================================
const ROLL_SPEED = 350.0
const ROLL_DURATION = 0.6


# =============================================================================
# 5. LANDING SETTINGS
# -----------------------------------------------------------------------------
# Soft landing:
# - обычное приземление
# - проигрывает последние кадры land-анимации
# - не блокирует движение
#
# Hard landing:
# - падение с большой высоты
# - проигрывает всю land-анимацию
# - временно блокирует движение
# =============================================================================
const SOFT_LAND_MIN_FALL_SPEED = 250.0
const HARD_LAND_MIN_FALL_SPEED = 650.0

const SOFT_LAND_START_FRAME = 4
const HARD_LAND_START_FRAME = 0

const SOFT_LAND_SPEED_SCALE = 1.8
const HARD_LAND_SPEED_SCALE = 1.0


# =============================================================================
# 6. WEAPON DATA
# -----------------------------------------------------------------------------
# damage       — урон оружия.
# range        — насколько далеко от игрока находится хитбокс атаки.
# attack_speed — множитель скорости атаки и attack-анимации.
#
# attack_speed > 1.0 = быстрее
# attack_speed = 1.0 = обычная скорость
# attack_speed < 1.0 = медленнее
# =============================================================================
const WEAPON_DATA := {
	"unarmed": {
		"damage": 5,
		"range": 45.0,
		"attack_speed": 1.25,
		"hit_frames": [4],
		"cancel_frame": 5
	},
	"katana": {
		"damage": 8,
		"range": 80.0,
		"attack_speed": 1.15,
		"hit_frames": [1, 5],
		"cancel_frame": 7
	},
	"sword": {
		"damage": 24,
		"range": 70.0,
		"attack_speed": 1,
		"hit_frames": [3],
		"cancel_frame": 5
	}
}


# =============================================================================
# 7. NODE REFERENCES
# =============================================================================
@onready var anim: AnimatedSprite2D = $FullBodySprite
@onready var attack_area: Area2D = $AttackArea
@onready var attack_shape: CollisionShape2D = $AttackArea/CollisionShape2D
@onready var player_camera = $Camera2D

# =============================================================================
# 8. SIGNALS
# =============================================================================
signal health_changed(current_hp, max_hp)
signal player_died


# =============================================================================
# 9. PLAYER STATE VARIABLES
# =============================================================================
var facing_direction := 1
var current_weapon := "unarmed"

var max_health := 100
var current_health := 100

var is_dead := false
var is_invincible := false


# =============================================================================
# 10. ATTACK STATE VARIABLES
# =============================================================================
var is_attacking := false
var attack_is_air := false
var can_cancel_attack := false
var attack_id := 0
var hit_targets := []
var current_attack_damage := 1
var buffered_cancel_action := ""
var buffered_cancel_time := -999.0

# =============================================================================
# 11. ROLL STATE VARIABLES
# =============================================================================
var is_rolling := false


# =============================================================================
# 12. LANDING STATE VARIABLES
# =============================================================================
var is_landing := false
var landing_blocks_movement := false
var landing_id := 0


# =============================================================================
# 13. GODOT MAIN FUNCTIONS
# =============================================================================
func _ready() -> void:
	add_to_group("player")

	# Подключаем сигнал попадания в AttackArea только один раз.
	if not attack_area.body_entered.is_connected(_on_attack_area_body_entered):
		attack_area.body_entered.connect(_on_attack_area_body_entered)

	# Хитбокс атаки должен быть выключен, пока игрок не атакует.
	attack_shape.disabled = true

	# Инициализация HP.
	current_health = max_health
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	# Сохраняем состояние пола ДО move_and_slide(), чтобы отследить момент приземления.
	var was_on_floor := is_on_floor()
	var fall_speed_before_slide := velocity.y

	# Гравитация.
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var direction := Input.get_axis("move_left", "move_right")

	# Soft landing можно отменить движением, чтобы не было визуального скольжения.
	if is_landing and not landing_blocks_movement and direction != 0:
		end_landing()

	# Roll / dodge.
	if Input.is_action_just_pressed("roll") and is_on_floor() and not is_rolling:
		if is_attacking:
			if can_cancel_attack:
				cancel_attack()
				start_roll()
			else:
				queue_cancel_action("roll")
		else:
			start_roll()

	# Во время roll игрок просто катится, остальная логика временно не работает.
	if is_rolling:
		move_and_slide()
		return

	# Запоминаем направление взгляда.
	if direction > 0:
		facing_direction = 1
	elif direction < 0:
		facing_direction = -1

	update_sprite_direction()

	# Hard landing блокирует движение.
	if is_landing and landing_blocks_movement:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		move_and_slide()
		update_animation()
		return

	update_horizontal_movement(direction)
	handle_jump_input()
	handle_weapon_input()
	handle_attack_input()

	move_and_slide()

	# Если игрок только что коснулся пола — проверяем soft/hard landing.
	if not was_on_floor and is_on_floor():
		try_start_landing(fall_speed_before_slide)

	update_animation()


# =============================================================================
# 14. INPUT HELPERS
# =============================================================================
func handle_jump_input() -> void:
	if not Input.is_action_just_pressed("jump"):
		return

	if not is_on_floor():
		return

	if is_attacking:
		if can_cancel_attack:
			cancel_attack()
			velocity.y = JUMP_VELOCITY
		else:
			queue_cancel_action("jump")
		return

	velocity.y = JUMP_VELOCITY


func handle_weapon_input() -> void:
	if Input.is_action_just_pressed("weapon_unarmed"):
		equip_weapon("unarmed")

	if Input.is_action_just_pressed("weapon_katana"):
		equip_weapon("katana")

	if Input.is_action_just_pressed("weapon_sword"):
		equip_weapon("sword")


func handle_attack_input() -> void:
	if Input.is_action_just_pressed("attack"):
		try_start_attack()


func is_movement_pressed() -> bool:
	return Input.get_axis("move_left", "move_right") != 0


# =============================================================================
# 15. MOVEMENT
# =============================================================================
func update_horizontal_movement(direction: float) -> void:
	if is_attacking:
		if attack_is_air:
			# В воздухе во время атаки можно двигаться.
			if direction != 0:
				velocity.x = direction * SPEED
		else:
			# На земле до cancel window игрок почти стопорится.
			if can_cancel_attack:
				if direction != 0:
					velocity.x = direction * SPEED * ATTACK_MOVE_MULTIPLIER
				else:
					velocity.x = move_toward(velocity.x, 0, SPEED)
			else:
				velocity.x = move_toward(velocity.x, 0, SPEED)
		return

	
	# Обычное движение.
	var move_speed := get_current_move_speed()
	if direction != 0:
		velocity.x = direction * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)


func update_sprite_direction() -> void:
	anim.flip_h = facing_direction < 0


func get_current_move_speed() -> float:
	if Input.is_action_pressed("run"):
		return RUN_SPEED

	return WALK_SPEED

# =============================================================================
# 16. WEAPON SYSTEM
# =============================================================================
func equip_weapon(weapon_name: String) -> void:
	# Нельзя менять оружие во время атаки или roll.
	if is_attacking or is_rolling:
		return

	# Защита от неправильного имени оружия.
	if not WEAPON_DATA.has(weapon_name):
		return

	if current_weapon == weapon_name:
		return

	current_weapon = weapon_name
	update_animation()


func get_weapon_data() -> Dictionary:
	if WEAPON_DATA.has(current_weapon):
		return WEAPON_DATA[current_weapon]

	return WEAPON_DATA["unarmed"]


func get_weapon_damage() -> int:
	return int(get_weapon_data()["damage"])


func get_weapon_range() -> float:
	return float(get_weapon_data()["range"])


func get_weapon_attack_speed() -> float:
	return float(get_weapon_data()["attack_speed"])


func get_scaled_attack_time(base_time: float) -> float:
	return base_time / get_weapon_attack_speed()


func get_weapon_hit_frames() -> Array:
	var data := get_weapon_data()

	if data.has("hit_frames"):
		return data["hit_frames"]

	return [3]


func get_weapon_cancel_frame() -> int:
	var data := get_weapon_data()

	if data.has("cancel_frame"):
		return int(data["cancel_frame"])

	return 4

# =============================================================================
# 17. ATTACK SYSTEM
# =============================================================================
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

	# Запоминаем параметры оружия на момент начала атаки
	current_attack_damage = get_weapon_damage()
	var attack_speed := get_weapon_attack_speed()

	# Ускоряем/замедляем attack-анимацию под оружие
	anim.speed_scale = attack_speed

	# AttackArea всегда в центре Player
	attack_area.position = Vector2.ZERO

	# Дальность хитбокса зависит от оружия
	attack_shape.position.x = get_weapon_range() * facing_direction
	attack_shape.position.y = 0

	# ВАЖНО: теперь хитбокс НЕ включается сразу
	attack_shape.disabled = true

	# Выбираем конкретную анимацию атаки
	var attack_base_name := "air_attack" if attack_is_air else "attack"
	var attack_animation_name := get_weapon_animation_name(attack_base_name)

	play_anim(attack_animation_name)
	if player_camera.has_method("attack_kick"):
		player_camera.attack_kick(facing_direction)
	var elapsed_time := 0.0
	var hit_frames := get_weapon_hit_frames()

	# Один или несколько hit ticks
	for hit_frame in hit_frames:
		var hit_time := get_animation_time_to_frame(attack_animation_name, int(hit_frame), attack_speed)
		var wait_time := hit_time - elapsed_time

		if wait_time > 0:
			await get_tree().create_timer(wait_time).timeout
			elapsed_time += wait_time

		if current_attack_id != attack_id:
			return

		# Каждый hit tick может ударить врага заново
		hit_targets.clear()

		attack_shape.disabled = false

		# Ждём физический кадр, чтобы Godot обновил overlaps
		await get_tree().physics_frame

		for body in attack_area.get_overlapping_bodies():
			_on_attack_area_body_entered(body)
			
		var hitbox_time := get_scaled_attack_time(ATTACK_ACTIVE_TIME)
		await get_tree().create_timer(hitbox_time).timeout
		elapsed_time += hitbox_time

		if current_attack_id != attack_id:
			return

		attack_shape.disabled = true

	# Ждём до cancel frame
	var cancel_time := get_animation_time_to_frame(
		attack_animation_name,
		get_weapon_cancel_frame(),
		attack_speed
	)

	var time_until_cancel := cancel_time - elapsed_time

	if time_until_cancel > 0:
		await get_tree().create_timer(time_until_cancel).timeout
		elapsed_time += time_until_cancel

	if current_attack_id != attack_id:
		return

	# Теперь можно отменять атаку
	can_cancel_attack = true
	
	if try_use_buffered_cancel_action():
		return

	# Если игрок не отменил атаку, ждём конец анимации
	var total_time := get_animation_total_time(attack_animation_name, attack_speed)
	var remaining_time := total_time - elapsed_time

	if remaining_time > 0:
		await get_tree().create_timer(remaining_time).timeout

	if current_attack_id != attack_id:
		return

	end_attack()


func queue_cancel_action(action_name: String) -> void:
	buffered_cancel_action = action_name
	buffered_cancel_time = Time.get_ticks_msec() / 1000.0


func has_buffered_cancel_action() -> bool:
	if buffered_cancel_action == "":
		return false

	var current_time := Time.get_ticks_msec() / 1000.0
	return current_time - buffered_cancel_time <= CANCEL_INPUT_BUFFER_TIME


func clear_buffered_cancel_action() -> void:
	buffered_cancel_action = ""
	buffered_cancel_time = -999.0


func try_use_buffered_cancel_action() -> bool:
	if not has_buffered_cancel_action():
		clear_buffered_cancel_action()
		return false

	var action_name := buffered_cancel_action
	clear_buffered_cancel_action()

	if action_name == "jump":
		if is_on_floor():
			cancel_attack()
			velocity.y = JUMP_VELOCITY
			return true

	if action_name == "roll":
		if is_on_floor() and not is_rolling:
			cancel_attack()
			start_roll()
			return true

	return false


func cancel_attack() -> void:
	if not is_attacking:
		return

	if not can_cancel_attack:
		return

	# Увеличиваем id, чтобы старые await из start_attack больше не могли завершить атаку повторно.
	attack_id += 1
	end_attack()


func end_attack() -> void:
	is_attacking = false
	attack_is_air = false
	can_cancel_attack = false
	attack_shape.disabled = true

	# Возвращаем нормальную скорость анимаций после attack speed.
	anim.speed_scale = 1.0

	update_animation()


func _on_attack_area_body_entered(body: Node) -> void:
	if not is_attacking:
		return

	# Не бьём самого себя.
	if body == self:
		return

	# Бьём только врагов.
	if not body.is_in_group("enemy"):
		return

	# Один враг получает урон только один раз за один удар.
	if body in hit_targets:
		return

	if body.has_method("take_damage"):
		hit_targets.append(body)
		body.take_damage(current_attack_damage)
		if player_camera.has_method("shake"):
			player_camera.shake(0.8, 0.04)

# =============================================================================
# 18. LANDING SYSTEM
# =============================================================================
func try_start_landing(fall_speed: float) -> void:
	if is_dead:
		return

	if is_attacking or is_rolling:
		return

	if fall_speed < SOFT_LAND_MIN_FALL_SPEED:
		return

	if fall_speed >= get_hard_landing_threshold():
		start_landing(HARD_LAND_START_FRAME, HARD_LAND_SPEED_SCALE, true)
		return

	# Soft landing не должен ломать бег.
	if is_movement_pressed():
		return

	start_landing(SOFT_LAND_START_FRAME, SOFT_LAND_SPEED_SCALE, false)


func get_hard_landing_threshold() -> float:
	# В будущем dual_blades будут более мобильным оружием.
	# Поэтому им можно дать более высокий порог hard landing.
	if current_weapon == "dual_blades":
		return 850.0

	return HARD_LAND_MIN_FALL_SPEED


func start_landing(start_frame: int, speed_scale: float, blocks_movement: bool) -> void:
	landing_id += 1
	var current_landing_id := landing_id

	is_landing = true
	landing_blocks_movement = blocks_movement
	if blocks_movement:
		if player_camera.has_method("shake"):
			player_camera.shake(4.0, 0.10)

	anim.speed_scale = speed_scale
	anim.play("land")
	anim.set_frame_and_progress(start_frame, 0.0)

	var duration := get_animation_time_from_frame("land", start_frame, speed_scale)

	await get_tree().create_timer(duration).timeout

	if current_landing_id != landing_id:
		return

	end_landing()


func end_landing() -> void:
	is_landing = false
	landing_blocks_movement = false
	anim.speed_scale = 1.0
	update_animation()


func get_animation_time_from_frame(animation_name: String, start_frame: int, speed_scale: float) -> float:
	if anim.sprite_frames == null:
		return 0.15

	if not anim.sprite_frames.has_animation(animation_name):
		return 0.15

	var frame_count: int = anim.sprite_frames.get_frame_count(animation_name)
	var fps: float = anim.sprite_frames.get_animation_speed(animation_name)

	if fps <= 0:
		return 0.15

	var frames_left: int = frame_count - start_frame

	if frames_left < 1:
		frames_left = 1

	return float(frames_left) / fps / speed_scale


# =============================================================================
# 19. ROLL / DODGE SYSTEM
# =============================================================================
func start_roll() -> void:
	is_rolling = true
	play_anim("roll")

	var direction := Input.get_axis("move_left", "move_right")

	if direction == 0:
		direction = facing_direction

	velocity.x = direction * ROLL_SPEED

	await get_tree().create_timer(ROLL_DURATION).timeout

	# Защита на случай, если игрок умер во время roll.
	if is_dead:
		return

	is_rolling = false
	velocity.x = 0
	update_animation()


# =============================================================================
# 20. DAMAGE / DEATH SYSTEM
# =============================================================================
func take_damage(amount: int) -> void:
	# Roll работает как dodge: урон игнорируется.
	if is_rolling:
		print("Уворот! Урон проигнорирован.")
		return

	# I-frames после предыдущего удара.
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
	if is_dead:
		return

	print("Игрок умер")

	is_dead = true
	player_died.emit()

	# Выключаем физику, чтобы игрок не мог ходить после смерти.
	set_physics_process(false)

	anim.play("death")
	anim.offset = Vector2(0, 0)

	await get_tree().create_timer(2.0).timeout

	# Временный респаун через перезагрузку сцены.
	get_tree().reload_current_scene()


# =============================================================================
# 21. ANIMATION SYSTEM
# =============================================================================
func update_animation() -> void:
	if is_landing:
		return

	if is_attacking:
		return

	if not is_on_floor():
		update_jump_animation()
		return

	var direction := Input.get_axis("move_left", "move_right")

	if direction != 0:
		if Input.is_action_pressed("run"):
			play_movement_anim("run")
		else:
			play_movement_anim("walk")
		return

	play_movement_anim("idle")


func update_jump_animation() -> void:
	# Прыжок вручную привязан к velocity.y, а не просто к FPS анимации.
	# velocity.y < 0  = персонаж летит вверх.
	# velocity.y ~= 0 = пик прыжка.
	# velocity.y > 0  = персонаж падает.
	if anim.animation != "jump":
		anim.play("jump")
		anim.pause()

	if velocity.y < -300:
		anim.frame = 0
		return

	if velocity.y < -120:
		anim.frame = 1
		return

	if velocity.y < -30:
		anim.frame = 2
		return

	if abs(velocity.y) <= 60:
		anim.frame = 3
		return

	if velocity.y < 250:
		anim.frame = 4
		return

	anim.frame = 5


func play_anim(animation_name: String) -> void:
	if anim.animation != animation_name:
		anim.play(animation_name)


func get_weapon_animation_name(base_name: String) -> String:
	var weapon_anim := "%s_%s" % [base_name, current_weapon]

	# 1. Точная анимация под оружие
	if anim.sprite_frames != null and anim.sprite_frames.has_animation(weapon_anim):
		return weapon_anim

	# 2. Если idle_katana нет, используем idle_sword
	if base_name == "idle" and current_weapon == "katana":
		if anim.sprite_frames != null and anim.sprite_frames.has_animation("idle_sword"):
			return "idle_sword"

	# 3. Если run_sword нет, используем run_unarmed
	if base_name == "run" and current_weapon == "sword":
		if anim.sprite_frames != null and anim.sprite_frames.has_animation("run_unarmed"):
			return "run_unarmed"

	# 4. Универсальный fallback на unarmed
	var unarmed_fallback := "%s_unarmed" % base_name

	if anim.sprite_frames != null and anim.sprite_frames.has_animation(unarmed_fallback):
		return unarmed_fallback

	# 5. Обычная анимация без suffix
	if anim.sprite_frames != null and anim.sprite_frames.has_animation(base_name):
		return base_name

	return "idle_unarmed"


func get_animation_time_to_frame(animation_name: String, target_frame: int, speed_scale: float) -> float:
	if anim.sprite_frames == null:
		return 0.0

	if not anim.sprite_frames.has_animation(animation_name):
		return 0.0

	var frame_count: int = anim.sprite_frames.get_frame_count(animation_name)
	var fps: float = anim.sprite_frames.get_animation_speed(animation_name)

	if fps <= 0:
		return 0.0

	var safe_frame: int = target_frame

	if safe_frame < 0:
		safe_frame = 0

	if safe_frame >= frame_count:
		safe_frame = frame_count - 1

	var time := 0.0

	for i in range(safe_frame):
		var frame_duration: float = anim.sprite_frames.get_frame_duration(animation_name, i)
		time += frame_duration / fps

	return time / speed_scale


func get_animation_total_time(animation_name: String, speed_scale: float) -> float:
	if anim.sprite_frames == null:
		return 0.2

	if not anim.sprite_frames.has_animation(animation_name):
		return 0.2

	var frame_count: int = anim.sprite_frames.get_frame_count(animation_name)
	var fps: float = anim.sprite_frames.get_animation_speed(animation_name)

	if fps <= 0:
		return 0.2

	var time := 0.0

	for i in range(frame_count):
		var frame_duration: float = anim.sprite_frames.get_frame_duration(animation_name, i)
		time += frame_duration / fps

	return time / speed_scale


func play_movement_anim(base_name: String) -> void:
	play_anim(get_weapon_animation_name(base_name))
