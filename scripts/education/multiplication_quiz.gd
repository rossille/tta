# multiplication_quiz.gd
# Pure logic for generating multiplication sessions and validating answers.
# No Godot scene dependencies — every method is static, the class extends
# RefCounted, and nothing here ever touches the tree, the audio, or paused
# state. That makes it trivial to reason about and easy to unit-test.
#
# Concepts:
#   - equation: { a: int, b: int, result: int }  (with a in TABLES, b a multiplier)
#   - session:  Array of distinct equations (3 by default)

class_name MultiplicationQuiz
extends RefCounted


## Generate a session of `count` DISTINCT equations.
## Picks `count` random (a, b) pairs without replacement, where
## a is drawn from `tables` and b is in [multiplier_min..multiplier_max].
##
## If the pool of possible pairs is smaller than `count`, returns the full
## pool (never raises).
static func generate_session(
		tables: Array,
		multiplier_min: int,
		multiplier_max: int,
		count: int
) -> Array:
	var pool: Array = []
	for a in tables:
		for b in range(multiplier_min, multiplier_max + 1):
			pool.append([a, b])
	pool.shuffle()

	var n: int = min(count, pool.size())
	var session: Array = []
	for i in range(n):
		var pair: Array = pool[i]
		session.append({
			"a": pair[0],
			"b": pair[1],
			"result": pair[0] * pair[1],
		})
	return session


## Pick one equation from the session, at random.
## Returns an empty dict if the session is empty.
static func pick_question(session: Array) -> Dictionary:
	if session.is_empty():
		return {}
	var idx: int = randi() % session.size()
	return session[idx]


## Validate an answer.
static func is_correct(equation: Dictionary, answer: int) -> bool:
	return int(equation.get("result", -1)) == answer
