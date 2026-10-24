class_name WorldWeather
extends RefCounted
## Daily weather. It follows the season and the world seed, so the same seed and day always give
## the same weather. Bad weather takes AP away from the party. Placeholder odds, for tuning.

const KINDS: PackedStringArray = ["clear", "rain", "storm", "snow"]
## AP change per weather.
const AP_MOD := {"clear": 0, "rain": -1, "storm": -2, "snow": -1}
## Percent chance of [clear, rain, storm, snow] per season.
const ODDS := {
	"spring": [55, 35, 10, 0],
	"summer": [70, 20, 10, 0],
	"autumn": [45, 40, 15, 0],
	"winter": [40, 0, 15, 45],
}


static func roll(world_seed: int, day: int, season: String) -> String:
	var odds: Array = ODDS.get(season, ODDS["spring"])
	var pick := WorldHash.hash2(WorldHash.sub(world_seed, "weather"), day, 0) % 100
	var sum := 0
	for k in KINDS.size():
		sum += int(odds[k])
		if pick < sum:
			return KINDS[k]
	return "clear"
