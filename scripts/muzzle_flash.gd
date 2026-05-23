# muzzle_flash.gd
# Brief spark burst at the barrel tip when a tank fires.
# Spawned locally on every peer — not replicated.

extends Node2D

func _ready() -> void:
	var p := CPUParticles2D.new()
	add_child(p)

	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10
	p.lifetime = 0.12
	p.speed_scale = 1.0

	# Narrow forward cone
	p.direction = Vector2(1.0, 0.0)
	p.spread = 35.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 200.0
	p.damping_min = 300.0
	p.damping_max = 500.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 0.6, 1.0))  # bright white-yellow
	gradient.set_color(1, Color(1.0, 0.5, 0.0, 0.0))  # orange, transparent
	p.color_ramp = gradient

	await get_tree().create_timer(p.lifetime + 0.05).timeout
	queue_free()
