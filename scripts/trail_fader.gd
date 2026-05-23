# trail_fader.gd
# Owns a set of trail stamp nodes after the bullet that created them is freed.
# Fades them out and then frees itself.

extends Node

var stamps: Array = []
var fade_time: float = 0.18

func _process(delta: float) -> void:
	for i in range(stamps.size() - 1, -1, -1):
		var e: Dictionary = stamps[i]
		if not is_instance_valid(e.node):
			stamps.remove_at(i)
			continue
		var a: float = 1.0 - e.age / fade_time
		if a <= 0.0:
			e.node.queue_free()
			stamps.remove_at(i)
		else:
			e.node.modulate.a = a
			e.age += delta
	if stamps.is_empty():
		queue_free()
