class_name HexGrid
extends RefCounted
## Axial hex maths (q, r), pointy-top. One hex has circumradius `size` (default 1.0).

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const SQRT3 := 1.7320508075688772


static func distance(a: Vector2i, b: Vector2i) -> int:
	var dq := a.x - b.x
	var dr := a.y - b.y
	return (absi(dq) + absi(dr) + absi(dq + dr)) / 2


## Centre of a hex on the ground plane (x, z).
static func to_world(c: Vector2i, size: float = 1.0) -> Vector2:
	return Vector2(size * SQRT3 * (c.x + c.y * 0.5), size * 1.5 * c.y)


static func from_world(p: Vector2, size: float = 1.0) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - 1.0 / 3.0 * p.y) / size
	var r := (2.0 / 3.0 * p.y) / size
	return _round(q, r)


static func _round(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))


static func neighbor(c: Vector2i, dir: int) -> Vector2i:
	return c + DIRS[dir]


## All hexes within `radius` of `center`, centre first.
static func disc(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			out.append(center + Vector2i(q, r))
	return out
