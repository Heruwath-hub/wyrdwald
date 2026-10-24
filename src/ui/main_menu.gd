extends Control
## Start screen: a background image and two buttons. Play Prototype opens the battle setup.

const SETUP_SCENE := "res://scenes/ui/combat_setup.tscn"

@onready var _play: Button = $Menu/PlayButton
@onready var _quit: Button = $Menu/QuitButton


func _ready() -> void:
	for button: Button in [_play, _quit]:
		MenuStyle.button(button)
	_play.pressed.connect(_on_play_pressed)
	_quit.pressed.connect(_on_quit_pressed)
	_play.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(SETUP_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
