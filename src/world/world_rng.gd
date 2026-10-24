class_name WorldRng
extends RefCounted
## Small deterministic random stream built on WorldHash.

var _seed: int
var _n: int = 0


func _init(seed_value: int) -> void:
	_seed = seed_value & WorldHash.M


func next_u32() -> int:
	_n += 1
	return WorldHash.mix(_seed ^ WorldHash.mix(_n))


func randf() -> float:
	return float(next_u32()) / 4294967296.0


## 0 .. n-1
func below(n: int) -> int:
	if n <= 1:
		return 0
	return next_u32() % n


func range_i(a: int, b: int) -> int:
	return a + below(b - a + 1)


func chance(p: float) -> bool:
	return randf() < p


func shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := below(i + 1)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp


func pick(items: Array) -> Variant:
	return items[below(items.size())]
