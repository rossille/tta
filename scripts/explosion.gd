# explosion.gd
# A one-shot fire burst spawned locally on every peer when a bullet is destroyed.
# Not replicated — each peer creates and manages its own instance.

extends Node2D

func _ready() -> void:
	_add_layer(
		20,                          # amount
		0.5, 0.8,                    # lifetime min/max
		80.0, 180.0,                 # velocity min/max
		150.0, 220.0,                # damping min/max
		4.0, 10.0,                   # scale min/max
		Color(1.0, 0.9, 0.1, 1.0),  # color start — bright yellow core
		Color(1.0, 0.3, 0.0, 0.0)   # color end   — red, fully transparent
	)
	# Second layer: slower, bigger, darker embers drifting upward
	_add_layer(
		12,
		0.6, 1.1,
		20.0, 80.0,
		40.0, 80.0,
		6.0, 16.0,
		Color(1.0, 0.45, 0.0, 0.9),  # orange
		Color(0.3, 0.05, 0.0, 0.0)   # dark red, transparent
	)
	# Third layer: dark smoke puffs
	_add_layer(
		8,
		0.8, 1.3,
		10.0, 40.0,
		20.0, 50.0,
		8.0, 20.0,
		Color(0.2, 0.2, 0.2, 0.6),   # dark gray
		Color(0.1, 0.1, 0.1, 0.0)    # transparent
	)

	var max_lifetime := 1.3 + 0.15
	await get_tree().create_timer(max_lifetime).timeout
	queue_free()


func _add_layer(
		amount: int,
		lifetime_min: float, lifetime_max: float,
		vel_min: float, vel_max: float,
		damp_min: float, damp_max: float,
		scale_min: float, scale_max: float,
		color_start: Color, color_end: Color
) -> void:
	var p := CPUParticles2D.new()
	add_child(p)

	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lerp(lifetime_min, lifetime_max, 0.5)
	p.lifetime_randomness = (lifetime_max - lifetime_min) / lifetime_max

	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0

	# Bias upward: spread wide but tip the direction toward screen-up
	p.direction = Vector2(0.0, -1.0)
	p.spread = 120.0
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.angular_velocity_min = -120.0
	p.angular_velocity_max = 120.0
	p.damping_min = damp_min
	p.damping_max = damp_max
	# Gentle upward drift (negative Y = up in screen space)
	p.gravity = Vector2(0.0, -30.0)
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
	c.add_point(Vector2(1.0, 0.0))
	return c
