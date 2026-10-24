class_name PlacedCard
extends RefCounted
## An attack card sitting in a lane slot. The slot is where the caster "stands" this round;
## the attack's pattern derives its targets from that slot.

var caster: CombatUnit
var attack: AttackData
var slot: int

## Order of placement within the round; breaks initiative ties (earlier resolves first).
var sequence: int

## Effective initiative: the attack's value minus the extra-card penalty and any delay.
var initiative: int


func lane() -> int:
	return caster.lane


func cell() -> Vector3i:
	return Vector3i(caster.side, caster.lane, slot)

## The cell an aimed card is pointed at (Enums.NO_CELL for ordinary attacks).
var aim: Vector3i = Enums.NO_CELL

## Initiative change from ground the card was placed on (haze, tripwire).
var init_mod := 0

## Set cards (traps, entities) took effect when placed and do not resolve.
var deployed := false

## A snare cancelled this card when it was placed.
var snared := false

## True once a trap sprang or a set card took effect: the card can no longer be taken back.
var committed := false


func has_aim() -> bool:
	return aim != Enums.NO_CELL


## A copy bound to `new_caster` (used when the whole engine state is cloned).
func copy(new_caster: CombatUnit) -> PlacedCard:
	var card := PlacedCard.new()
	card.caster = new_caster
	card.attack = attack
	card.slot = slot
	card.sequence = sequence
	card.initiative = initiative
	card.aim = aim
	card.init_mod = init_mod
	card.deployed = deployed
	card.snared = snared
	card.committed = committed
	return card
