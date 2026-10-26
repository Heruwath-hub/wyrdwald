extends Control
## Start screen: a background image and three buttons. Combat Prototype opens the battle setup,
## World Map opens the world generation prototype.

const SETUP_SCENE := "res://scenes/ui/combat_setup.tscn"
const WORLD_SCENE := "res://scenes/world/world_map.tscn"

@onready var _play: Button = $Menu/PlayButton
@onready var _world: Button = $Menu/WorldButton
@onready var _quit: Button = $Menu/QuitButton


func _ready() -> void:
	for button: Button in [_play, _world, _quit]:
		MenuStyle.button(button)
	_play.pressed.connect(_on_play_pressed)
	_world.pressed.connect(_on_world_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	_play.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(SETUP_SCENE)


func _on_world_pressed() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
