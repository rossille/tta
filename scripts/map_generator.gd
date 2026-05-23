# map_generator.gd
# Generates a randomised symmetric arena layout each match.
#
# Grid: 64px cells, 20×11. Walls are WALL_T px thick (matching outer walls),
# 2–6 cells long. Generated in the top half only, mirrored 180° around centre.
#
# Exposes the static `build_wall_at` helper used by both the host (during
# generation) and clients (when reconstructing walls from the RPC'd segment
# list) so every peer ends up with visually identical walls. Consumers should
# `preload` this script and call `MapGenerator.build_wall_at(...)` on the
# preloaded reference — we deliberately avoid `class_name` so dynamically-
# loaded scenes (e.g. arena.gd loaded from lobby.gd at runtime) don't depend
# on the editor having pre-scanned the global class registry.

extends RefCounted

const CELL      := 64
const COLS      := 20
const ROWS      := 11
const OFFSET_Y  := 16     # px gap above the grid to centre it in 720px
const CENTRE    := Vector2(640, 360)
const WALL_TEXTURE := preload("res://assets/wall_tile.png")

# Wall thickness in pixels — matches the outer border walls
const WALL_T    := 32

# Minimum cell gap between wall segments (1 = just no touching)
const MIN_GAP   := 1

# Spawn-safe zone radius in cells around each corner
const SPAWN_SAFE := 2

# How many segments to place in the half-arena
const MIN_WALLS := 2
const MAX_WALLS := 4


func generate(parent: Node2D) -> Dictionary:
	var occupied := {}

	# Mark border cells
	for c in range(COLS):
		occupied[Vector2i(c, 0)]        = true
		occupied[Vector2i(c, ROWS - 1)] = true
	for r in range(ROWS):
		occupied[Vector2i(0, r)]        = true
		occupied[Vector2i(COLS - 1, r)] = true

	# Spawn corners and their safe zones
	var spawn_corners := [
		Vector2i(1, 1),
		Vector2i(COLS - 2, ROWS - 2),
		Vector2i(COLS - 2, 1),
		Vector2i(1, ROWS - 2),
	]
	for sc in spawn_corners:
		for dr in range(-SPAWN_SAFE, SPAWN_SAFE + 1):
			for dc in range(-SPAWN_SAFE, SPAWN_SAFE + 1):
				occupied[Vector2i(sc.x + dc, sc.y + dr)] = true

	# Also mark the mirror of each spawn corner safe zone so the mirrored
	# walls don't land on top of spawns either
	for sc in spawn_corners:
		var m := Vector2i(COLS - 1 - sc.x, ROWS - 1 - sc.y)
		for dr in range(-SPAWN_SAFE, SPAWN_SAFE + 1):
			for dc in range(-SPAWN_SAFE, SPAWN_SAFE + 1):
				occupied[Vector2i(m.x + dc, m.y + dr)] = true

	# Generation zone: full arena minus border and spawn-safe zones
	# We work in the top half (rows 1..ROWS/2) but can use all columns 1..COLS-2
	# to give more room. Mirror handles the bottom half.
	var half_rows: int = ROWS / 2   # = 5

	var segments: Array = []
	var attempts := 0
	var target: int = randi_range(MIN_WALLS, MAX_WALLS)

	while segments.size() < target and attempts < 400:
		attempts += 1

		var horizontal: bool = randf() > 0.5
		# Horizontal walls are long; vertical walls are shorter to fit in the
		# top half (5 rows) with room for spawn-safe zones and the mirror
		var length: int = randi_range(4, 8) if horizontal else randi_range(2, 3)

		# Place by centre position so long walls don't cluster toward one side.
		# Centre of the wall must be at least half-length from each border.
		var half_len: int = length / 2

		var min_centre_c := 1 + half_len
		var max_centre_c := (COLS - 2) - half_len
		var min_centre_r := 1 + (0 if horizontal else half_len)
		var max_centre_r := (half_rows - 1) - (0 if horizontal else half_len)

		if max_centre_c <= min_centre_c or max_centre_r <= min_centre_r:
			continue

		var centre_c: int = randi_range(min_centre_c, max_centre_c)
		var centre_r: int = randi_range(min_centre_r, max_centre_r)

		# Derive top-left corner from centre
		var col: int = centre_c - half_len
		var row: int = centre_r - (half_len if not horizontal else 0)

		var seg := Rect2i(col, row,
			length if horizontal else 1,
			1      if horizontal else length)

		if not _can_place(seg, occupied):
			continue

		# Mark the segment cells as occupied
		for dc in range(seg.size.x):
			for dr in range(seg.size.y):
				occupied[Vector2i(seg.position.x + dc, seg.position.y + dr)] = true

		segments.append(seg)

	# Build walls for each segment and its 180° mirror
	for seg in segments:
		_build_wall(parent, seg)
		_build_wall(parent, _mirror_segment(seg))

	return _compute_spawns(spawn_corners)


# ---------------------------------------------------------------------------
# Placement check — reject if too close to any occupied cell
# ---------------------------------------------------------------------------
func _can_place(seg: Rect2i, occupied: Dictionary) -> bool:
	var check := Rect2i(
		seg.position.x - MIN_GAP,
		seg.position.y - MIN_GAP,
		seg.size.x + MIN_GAP * 2,
		seg.size.y + MIN_GAP * 2
	)
	for dc in range(check.size.x):
		for dr in range(check.size.y):
			if occupied.has(Vector2i(check.position.x + dc, check.position.y + dr)):
				return false
	return true


# ---------------------------------------------------------------------------
# Mirror a cell rect 180° around the centre
# ---------------------------------------------------------------------------
func _mirror_segment(seg: Rect2i) -> Rect2i:
	var br := Vector2i(seg.position.x + seg.size.x - 1,
	                   seg.position.y + seg.size.y - 1)
	var m_tl := Vector2i(COLS - 1 - br.x, ROWS - 1 - br.y)
	return Rect2i(m_tl, seg.size)


# ---------------------------------------------------------------------------
# Build one wall node — WALL_T px thick in the narrow dimension
# ---------------------------------------------------------------------------
func _build_wall(parent: Node2D, seg: Rect2i) -> void:
	# A horizontal wall: full length in X, WALL_T in Y (centred on grid line)
	# A vertical wall:   WALL_T in X, full length in Y
	var horizontal: bool = seg.size.x > seg.size.y

	var px_w: float
	var px_h: float
	var px_x: float
	var px_y: float

	if horizontal:
		px_w = seg.size.x * CELL
		px_h = WALL_T
		px_x = seg.position.x * CELL + px_w / 2.0
		# Centre the thin wall on the cell's horizontal midline
		px_y = OFFSET_Y + seg.position.y * CELL + CELL / 2.0
	else:
		px_w = WALL_T
		px_h = seg.size.y * CELL
		px_x = seg.position.x * CELL + CELL / 2.0
		px_y = OFFSET_Y + seg.position.y * CELL + px_h / 2.0

	build_wall_at(parent, Vector2(px_x, px_y), Vector2(px_w, px_h))


# ---------------------------------------------------------------------------
# Build a fully-styled wall (StaticBody2D + collision + textured visual) at a
# given world-space centre. Used by both the host (during generation) and
# clients (when reconstructing walls from the RPC'd segment list) so every
# peer ends up with visually identical walls.
# ---------------------------------------------------------------------------
static func build_wall_at(parent: Node2D, centre: Vector2, sz: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 2
	body.add_to_group("nav_wall")
	body.position = centre

	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = sz
	shape_node.shape = shape
	body.add_child(shape_node)

	# Scale the tile so its short side (256px) = WALL_T screen px
	const TILE_SCALE := WALL_T / 256.0
	var visual := Sprite2D.new()
	visual.texture = WALL_TEXTURE
	visual.scale = Vector2(TILE_SCALE, TILE_SCALE)
	visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visual.region_enabled = true
	visual.region_rect = Rect2(0, 0, sz.x / TILE_SCALE, sz.y / TILE_SCALE)
	body.add_child(visual)

	parent.add_child(body)


# ---------------------------------------------------------------------------
# Compute 4 spawn points (2 symmetric pairs) facing inward
# ---------------------------------------------------------------------------
func _compute_spawns(spawn_corners: Array) -> Dictionary:
	var points: Array    = []
	var rotations: Array = []

	for i in [0, 2]:   # TL and TR corners
		var sc: Vector2i = spawn_corners[i]
		var world := Vector2(
			sc.x * CELL + CELL / 2.0,
			OFFSET_Y + sc.y * CELL + CELL / 2.0
		)
		points.append(world)
		rotations.append((CENTRE - world).angle())

		# 180° mirror around CENTRE
		var mirrored := Vector2(2.0 * CENTRE.x - world.x, 2.0 * CENTRE.y - world.y)
		points.append(mirrored)
		rotations.append((CENTRE - mirrored).angle())

	return { "spawn_points": points, "spawn_rotations": rotations }
