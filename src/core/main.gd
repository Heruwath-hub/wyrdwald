extends Node
## Boot scene. Confirms the content database loads and is internally consistent, then opens the main menu.

const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"


func _ready() -> void:
	print("Wyrdwald: %d races, %d classes, %d attacks loaded." % [
		ContentDB.races.size(),
		ContentDB.classes.size(),
		ContentDB.attacks.size(),
	])
	var problems := ContentDB.validate()
	if problems.is_empty():
		print("Content validation passed.")
	else:
		for problem in problems:
			push_error(problem)
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU_SCENE)
