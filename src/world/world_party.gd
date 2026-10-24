class_name WorldParty
extends RefCounted
## The player's party on the world map: where it is, how many AP it has left today, and the
## calendar. Pure rules, no nodes, so it can be tested without a scene.

const SEASONS: PackedStringArray = ["spring", "summer", "autumn", "winter"]
## AP per day by season. Only winter differs; weather can take more away (see WorldWeather).
const SEASON_AP := {"spring": 4, "summer": 4, "autumn": 4, "winter": 3}
const MIN_DAILY_AP := 1
const DAYS_PER_SEASON := 28

var hex: int = 0
var ap_left: int = 0
var ap_spent: int = 0
var day: int = 1
var season_index: int = 0
var world_seed: int = 0
var weather: String = "clear"
## When set, this weather is used instead of the rolled one (for testing).
var forced_weather: String = ""


func _init(start_hex: int = 0, start_season: String = "spring", seed_value: int = 0) -> void:
	hex = start_hex
	world_seed = seed_value
	season_index = maxi(0, SEASONS.find(start_season))
	_refresh()


func season() -> String:
	return SEASONS[season_index]


func daily_ap() -> int:
	return maxi(MIN_DAILY_AP, int(SEASON_AP[season()]) + int(WorldWeather.AP_MOD[weather]))


func _refresh() -> void:
	weather = forced_weather if forced_weather != "" else WorldWeather.roll(world_seed, day, season())
	ap_left = maxi(0, daily_ap() - ap_spent)


func set_forced_weather(kind: String) -> void:
	forced_weather = kind
	_refresh()


## Day number inside the current season, 1-based.
func day_in_season() -> int:
	return (day - 1) % DAYS_PER_SEASON + 1


func end_day() -> void:
	day += 1
	ap_spent = 0
	if (day - 1) % DAYS_PER_SEASON == 0:
		season_index = (season_index + 1) % SEASONS.size()
	_refresh()


func set_season(name: String) -> void:
	var k := SEASONS.find(name)
	if k != -1:
		season_index = k
		_refresh()


## Least-cost route from the party to `target`, or empty if unreachable.
func plan(w: WorldData, target: int) -> PackedInt32Array:
	return WorldPathing.path(w, hex, target)


## How many steps of `route` (which starts on the party's hex) the party can afford today.
func affordable_steps(w: WorldData, route: PackedInt32Array) -> int:
	var budget := ap_left
	var steps := 0
	for k in range(1, route.size()):
		var cost := w.ap[route[k]]
		if cost < 0 or cost > budget:
			break
		budget -= cost
		steps += 1
	return steps


## Walks as far along `route` as today's AP allows. Returns the hexes entered, in order.
func move_along(w: WorldData, route: PackedInt32Array) -> PackedInt32Array:
	var entered := PackedInt32Array()
	var steps := affordable_steps(w, route)
	for k in range(1, steps + 1):
		ap_left -= w.ap[route[k]]
		ap_spent += w.ap[route[k]]
		hex = route[k]
		entered.append(route[k])
	return entered
