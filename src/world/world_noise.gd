class_name WorldNoise
extends RefCounted
## Value noise and fractal noise on WorldHash. Output is 0..1.


static func value(seed_value: int, x: float, y: float) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var v00 := WorldHash.unit(WorldHash.hash2(seed_value, x0, y0))
	var v10 := WorldHash.unit(WorldHash.hash2(seed_value, x0 + 1, y0))
	var v01 := WorldHash.unit(WorldHash.hash2(seed_value, x0, y0 + 1))
	var v11 := WorldHash.unit(WorldHash.hash2(seed_value, x0 + 1, y0 + 1))
	return lerpf(lerpf(v00, v10, sx), lerpf(v01, v11, sx), sy)


static func fbm(seed_value: int, x: float, y: float, octaves: int = 4) -> float:
	var total := 0.0
	var amp := 1.0
	var norm := 0.0
	var freq := 1.0
	for o in octaves:
		total += amp * value(seed_value + o * 101, x * freq, y * freq)
		norm += amp
		amp *= 0.5
		freq *= 2.0
	return total / norm
