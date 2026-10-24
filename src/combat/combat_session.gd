class_name CombatSession
extends RefCounted
## Settings handed from the combat setup screen to the combat screen. Both read the same rules
## object, so what is chosen before the battle is what the battle uses, and changes made in the
## combat screen's Rules panel carry back to the setup screen.

static var _rules: CombatRules = null

## True once the player has been through the setup screen and pressed Start.
static var configured := false


static func current() -> CombatRules:
	if _rules == null:
		_rules = CombatRules.new()
	return _rules


## Back to the default rules, with the gentlest difficulty selected.
static func reset() -> CombatRules:
	_rules = CombatRules.new()
	_rules.difficulty = 0
	return _rules
