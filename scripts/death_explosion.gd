# death_explosion.gd
# Large fire explosion when a tank is destroyed.
# Spawned locally on every peer — not replicated.

extends Node2D

func _ready() -> void:
	# Large bright core burst
	_add_layer(30, 0.6, 1.0, 120.0, 280.0, 80.0, 160.0, 8.0, 20.0,
		Color(1.0, 0.95, 0.3, 1.0), Color(1.0, 0.2, 0.0, 0.0))
	# Heavy orange fire body drifting up
	_add_layer(20, 0.8, 1.4, 40.0, 130.0, 30.0, 70.0, 12.0, 32.0,
		Color(1.0, 0.4, 0.0, 1.0), Color(0.4, 0.05, 0.0, 0.0))
	# Large smoke puffs
	_add_layer(14, 1.0, 1.8, 15.0, 60.0, 15.0, 40.0, 16.0, 40.0,
		Color(0.25, 0.25, 0.25, 0.7), Color(0.1, 0.1, 0.1, 0.0))
	# Debris sparks
	_add_layer(16, 0.3, 0.6, 150.0, 320.0, 200.0, 350.0, 2.0, 5.0,
		Color(1.0, 1.0, 0.6, 1.0), Color(1.0, 0.3, 0.0, 0.0))

	await get_tree().create_timer(2.0).timeout
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
	p.explosiveness = 0.85
	p.amount = amount
	p.lifetime = lerp(lifetime_min, lifetime_max, 0.5)
	p.lifetime_randomness = (lifetime_max - lifetime_min) / lifetime_max

	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0

	p.direction = Vector2(0.0, -1.0)
	p.spread = 140.0
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.damping_min = damp_min
	p.damping_max = damp_max
	p.gravity = Vector2(0.0, -20.0)
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
