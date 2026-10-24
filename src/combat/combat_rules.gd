class_name CombatRules
extends Resource
## Tunable combat rules. Each export is a design question that can be flipped while playtesting.

## How many enemy lanes a Pierce attack travels through, counted from the enemy Melee lane.
## 1 = stops at the enemy front lane, 3 = the whole column.
@export_range(1, 3) var pierce_enemy_lanes: int = 3

## If true, a card whose caster dies before it resolves is cancelled; otherwise it still fires.
@export var cancel_on_caster_death: bool = true

## If false, damaging attacks skip the caster's own side.
@export var friendly_fire: bool = false

## Which side places the first card each round: 0 = player, 1 = enemy, -1 = random.
## Sides then alternate one card at a time.
@export_range(-1, 1) var first_side: int = -1

## Cards each side may play per round, spread over its characters as it likes.
@export_range(1, 12) var cards_per_round: int = 7

## Most cards one character may place per round (each must be a different attack).
## Every card after a character's first loses `extra_card_penalty` initiative per card already placed.
@export_range(1, 4) var max_cards_per_character: int = 3
@export var extra_card_penalty: int = 6

## If true, a card can only be pointed at enemy lanes up to the depth of its caster's own lane:
## Melee characters reach the enemy Melee lane, Ranged characters the Melee and Ranged lanes,
## Magic characters every lane. Cards aimed at your own side are never restricted.
@export var restrict_lanes: bool = true

## Cards the enemy side may play per round; -1 = the same as `cards_per_round`.
@export_range(-1, 12) var enemy_cards_per_round: int = -1

## Chance that an enemy turn is a mistake: a random legal card in a random slot instead of the best one.
@export_range(0.0, 1.0) var enemy_mistakes: float = 0.0

## If true, cards of your characters that fall before they act still resolve (a last stand).
@export var player_last_stand: bool = false

## Initiative added to every enemy card (negative: the enemy acts later and your cards land first).
@export_range(-10, 10) var enemy_initiative: int = 0

## Chance per enemy turn that it reads the cards you have already placed. Otherwise it plays blind,
## like an opener: it still sees the ground and its own cards but does not counter yours.
@export_range(0.0, 1.0) var enemy_awareness: float = 1.0

## Difficulty tier of the next battle: 0 Easy, 1 Normal, 2 Hard (see BattleSetup.TIERS).
@export_range(0, 2) var difficulty: int = 1

## Ground the battlefield starts with: -1 = random, 0 = bare, 1 = Plainlands (dry grass), 2 = Wetlands (water).
@export_range(-1, 2) var biome: int = -1
