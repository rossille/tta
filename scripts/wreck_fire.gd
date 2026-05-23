# wreck_fire.gd
# Hellfire inferno on a destroyed tank. Looping, never self-frees.

extends Node2D

var _layers: Array = []
var _wind_age: float = 0.0

func _process(delta: float) -> void:
	_wind_age += delta
	# Slowly rotate the wind direction using two overlapping sine waves
	var angle: float = sin(_wind_age * 0.4) * 3.6 + sin(_wind_age * 0.17 + 1.3) * 2.4
	var dir := Vector2(sin(angle), cos(angle))
	for p in _layers:
		if is_instance_valid(p):
			p.direction = dir


const TANK_RADIUS := 21.0  # half the tank body width in px

func _ready() -> void:
	_spawn_fire_at(self, 1.0)
	# Debris color palette — warm rusty tones
	var debris_colors := [
		Color(0.55, 0.25, 0.05, 0.85),  # rusty brown
		Color(0.60, 0.30, 0.08, 0.85),  # warm rust
		Color(0.65, 0.35, 0.10, 0.85),  # scorched orange-brown
		Color(0.50, 0.22, 0.06, 0.85),  # dark rust
		Color(0.58, 0.28, 0.07, 0.85),  # mid rust
	]

	# 5 debris fires ejected from tank center to random positions
	for i in range(5):
		var angle := randf() * TAU
		var dist  := randf_range(TANK_RADIUS * 1.0, TANK_RADIUS * 2.0)
		var size_factor := randf_range(0.5, 1.5)
		var debris_scale := 0.25 * size_factor
		var target_pos := Vector2(cos(angle), sin(angle)) * dist

		var pivot := Node2D.new()
		pivot.position = Vector2.ZERO
		add_child(pivot)

		_spawn_fire_at(pivot, debris_scale)

		var ext := Vector2(18.0, 10.0) * debris_scale * 1.2
		var resting_color: Color = debris_colors[i % debris_colors.size()]
		var glow := ColorRect.new()
		glow.size = ext
		glow.pivot_offset = ext / 2.0
		glow.position = -ext / 2.0
		glow.rotation = randf() * TAU
		glow.color = resting_color
		pivot.add_child(glow)

		# Spin direction and speed — random, decelerates to zero on landing
		var spin_speed := randf_range(6.0, 14.0) * (1.0 if randf() > 0.5 else -1.0)
		var duration := 0.9
		var delay := randf_range(0.0, 0.3)

		var tween := create_tween()
		tween.tween_interval(delay)
		tween.set_parallel(true)
		# Fly to target
		tween.tween_property(pivot, "position", target_pos, duration) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		# Spin and decelerate to rest
		var target_rot := pivot.rotation + spin_speed
		tween.tween_property(pivot, "rotation", target_rot, duration) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)



func _spawn_fire_at(parent: Node2D, scale_factor: float) -> void:
	var ext := Vector2(18.0, 10.0) * scale_factor
	_add_layer(parent,
		int(480 * scale_factor), 0.8, 1.4,
		20.0, 60.0, 10.0, 25.0,
		0.5, 1.5, 0.3,
		Color(1.0, 1.0, 0.85, 0.35),
		Color(1.0, 0.6, 0.0, 0.0), ext
	)
	_add_layer(parent,
		int(600 * scale_factor), 1.0, 1.8,
		15.0, 50.0, 8.0, 20.0,
		0.8, 2.5, 0.25,
		Color(1.0, 0.55, 0.0, 0.3),
		Color(0.9, 0.1, 0.0, 0.0), ext
	)
	_add_layer(parent,
		int(400 * scale_factor), 1.2, 2.2,
		10.0, 40.0, 5.0, 15.0,
		1.0, 3.0, 0.2,
		Color(0.9, 0.15, 0.0, 0.275),
		Color(0.4, 0.0, 0.0, 0.0), ext
	)
	_add_layer(parent,
		int(320 * scale_factor), 2.5, 4.5,
		15.0, 45.0, 2.0, 8.0,
		1.5, 4.0, 0.15,
		Color(0.08, 0.08, 0.08, 0.25),
		Color(0.03, 0.03, 0.03, 0.0), ext
	)
	_add_layer(parent,
		int(240 * scale_factor), 0.8, 1.6,
		30.0, 80.0, 20.0, 50.0,
		0.3, 1.0, 0.5,
		Color(1.0, 0.95, 0.4, 0.4),
		Color(1.0, 0.2, 0.0, 0.0), ext
	)


func _add_layer(
		parent: Node2D,
		amount: int,
		lifetime_min: float, lifetime_max: float,
		vel_min: float, vel_max: float,
		damp_min: float, damp_max: float,
		scale_min: float, scale_max: float,
		explosiveness: float,
		color_start: Color, color_end: Color,
		emit_extents: Vector2 = Vector2(18.0, 10.0)
) -> void:
	var p := CPUParticles2D.new()
	parent.add_child(p)
	_layers.append(p)

	p.emitting = true
	p.one_shot = false
	p.explosiveness = explosiveness
	p.amount = amount
	p.lifetime = lerp(lifetime_min, lifetime_max, 0.5)
	p.lifetime_randomness = (lifetime_max - lifetime_min) / lifetime_max

	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = emit_extents

	p.direction = Vector2(0.0, 1.0)  # overridden each frame by _process
	p.spread = 80.0
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.damping_min = damp_min
	p.damping_max = damp_max
	p.gravity = Vector2.ZERO
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max
	p.scale_amount_curve = _make_shrink_curve()

	var gradient := Gradient.new()
	gradient.set_color(0, color_start)
	gradient.set_color(1, color_end)
	p.color_ramp = gradient


func _make_shrink_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.3, 1.2))  # briefly expand then shrink
	c.add_point(Vector2(1.0, 0.0))
	return c
