class_name WorldHash
extends RefCounted
## Own 32-bit integer hashing so a seed gives the same world on every platform and Godot version.
## Godot's built-in noise and random classes are deliberately not used.

const M := 0xFFFFFFFF


static func mix(x: int) -> int:
	x &= M
	x = (((x >> 16) ^ x) * 0x45d9f3b) & M
	x = (((x >> 16) ^ x) * 0x45d9f3b) & M
	return ((x >> 16) ^ x) & M


static func hash2(seed_value: int, a: int, b: int) -> int:
	var h := mix((seed_value & M) ^ 0x9E3779B9)
	h = mix(h ^ (a & M))
	return mix(h ^ (b & M))


static func str_hash(s: String) -> int:
	var h := 2166136261
	for byte in s.to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & M
	return h


## A stage or object gets its own seed from the world seed and a name.
static func sub(seed_value: int, stage: String) -> int:
	return mix((seed_value & M) ^ str_hash(stage))


## 0.0 <= result < 1.0
static func unit(h: int) -> float:
	return float(h & M) / 4294967296.0
