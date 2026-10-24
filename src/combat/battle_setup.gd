class_name BattleSetup
extends RefCounted
## Preset teams for the combat prototype. A character's lane comes from its class; its slot
## is chosen every round when the card is placed.

## Placeholder hit points by lane index (Melee, Ranged, Magic).
const HP_BY_LANE := [40, 30, 25]

const PLAYER_TEAM := [
	{"class": "warrior", "name": "Brann"},
	{"class": "hunter", "name": "Isolde"},
	{"class": "rogue", "name": "Tarn"},
	{"class": "healer", "name": "Mira"},
	{"class": "witch", "name": "Vesna"},
]

## Enemy squad. Four enemies against your five is a close fight; add {"class": "witch", "name": "Dread"}
## for a fifth and it turns hard.
const ENEMY_TEAM := [
	{"class": "reaver", "name": "Gnaw"},
	{"class": "trickster", "name": "Skeld"},
	{"class": "druid", "name": "Hush"},
	{"class": "rogue", "name": "Nix"},
]


## Difficulty tiers double as progression tiers: each adds characters and skills. An entry lists a
## class, a name and optionally "attacks", the only skill ids that character may use (default: all).
## Easy drops one Ranged character and keeps three skills each, with one trap to learn on.
## Normal is the full party of five with four skills each, still dropping the least central ones.
## Hard fields every skill against a bigger enemy squad.
const TIER_NAMES := ["Easy", "Normal", "Hard"]

const TIERS := [
	{
		"player_hp": 1.0,
		"enemy_cards": 6,
		"enemy_mistakes": 0.0,
		"enemy_initiative": -2,
		"enemy_awareness": 0.7,
		"last_stand": true,
		"player": [
			{"class": "warrior", "name": "Brann", "attacks": ["cleave", "shield_bash", "shield_wall"]},
			{"class": "hunter", "name": "Isolde", "attacks": ["aimed_shot", "volley", "spike_pit", "flame_trap"]},
			{"class": "healer", "name": "Mira", "attacks": ["mend", "soothing_rain", "lifebloom"]},
			{"class": "witch", "name": "Vesna", "attacks": ["hex_bolt", "chain_lightning", "ruin"]},
		],
		"enemy": [
			{"class": "reaver", "name": "Gnaw", "attacks": ["rend", "frenzy", "night_terror"]},
			{"class": "trickster", "name": "Skeld", "attacks": ["dirty_trick", "ricochet", "smoke_bomb"]},
			{"class": "druid", "name": "Hush", "attacks": ["thorn_lash", "entangle", "wild_surge"]},
		],
	},
	{
		"player_hp": 1.0,
		"enemy_cards": -1,
		"enemy_mistakes": 0.0,
		"enemy_initiative": -1,
		"enemy_awareness": 0.85,
		"last_stand": true,
		"player": [
			{"class": "warrior", "name": "Brann", "attacks": ["cleave", "shield_bash", "sweeping_strike", "shield_wall"]},
			{"class": "hunter", "name": "Isolde", "attacks": ["aimed_shot", "volley", "spike_pit", "flame_trap"]},
			{"class": "rogue", "name": "Tarn", "attacks": ["quick_stab", "fan_of_knives", "tripwire", "disarm"]},
			{"class": "healer", "name": "Mira", "attacks": ["mend", "soothing_rain", "lifebloom", "cleanse"]},
			{"class": "witch", "name": "Vesna", "attacks": ["hex_bolt", "chain_lightning", "ruin", "hex_totem"]},
		],
		"enemy": [
			{"class": "reaver", "name": "Gnaw", "attacks": ["rend", "frenzy", "night_terror"]},
			{"class": "trickster", "name": "Skeld", "attacks": ["dirty_trick", "ricochet", "smoke_bomb", "oil_flask"]},
			{"class": "druid", "name": "Hush", "attacks": ["thorn_lash", "entangle", "wild_surge", "rain"]},
			{"class": "rogue", "name": "Nix", "attacks": ["quick_stab", "fan_of_knives", "tripwire", "disarm"]},
		],
	},
	{
		"player_hp": 1.0,
		"enemy_cards": -1,
		"enemy_mistakes": 0.0,
		"enemy_initiative": 0,
		"enemy_awareness": 1.0,
		"last_stand": false,
		"player": [
			{"class": "warrior", "name": "Brann"},
			{"class": "hunter", "name": "Isolde"},
			{"class": "rogue", "name": "Tarn"},
			{"class": "healer", "name": "Mira"},
			{"class": "witch", "name": "Vesna"},
		],
		"enemy": [
			{"class": "reaver", "name": "Gnaw"},
			{"class": "trickster", "name": "Skeld"},
			{"class": "druid", "name": "Hush"},
			{"class": "rogue", "name": "Nix"},
			{"class": "witch", "name": "Dread"},
		],
	},
]


## Fills both sides for a difficulty tier (0 Easy, 1 Normal, 2 Hard).
static func setup_tier(engine: CombatEngine, tier: int, content: Node) -> void:
	var entry: Dictionary = TIERS[clampi(tier, 0, TIERS.size() - 1)]
	engine.rules.enemy_cards_per_round = entry["enemy_cards"]
	engine.rules.enemy_mistakes = entry["enemy_mistakes"]
	engine.rules.enemy_initiative = entry["enemy_initiative"]
	engine.rules.enemy_awareness = entry["enemy_awareness"]
	engine.rules.player_last_stand = entry["last_stand"]
	add_team(engine, 0, entry["player"], content, entry["player_hp"])
	add_team(engine, 1, entry["enemy"], content)


## `content` is the ContentDB autoload, passed in so this class stays free of scene-tree globals.
static func add_team(engine: CombatEngine, side: int, team: Array, content: Node, hp_scale: float = 1.0) -> void:
	for entry in team:
		var class_data: ClassData = content.get_class_data(entry["class"])
		if class_data == null:
			push_error("Unknown class '%s' in battle setup." % entry["class"])
			continue
		var unit := CombatUnit.new(
			engine.board.units.size() + 1,
			entry["name"],
			side,
			class_data,
			roundi(HP_BY_LANE[class_data.lane()] * hp_scale)
		)
		unit.attacks = content.attacks_for_class(class_data)
		if entry.has("attacks"):
			var allowed: Array = entry["attacks"]
			var kept: Array[AttackData] = []
			kept.assign(unit.attacks.filter(func(attack: AttackData) -> bool: return allowed.has(attack.id)))
			unit.attacks = kept
		engine.board.add_unit(unit)
