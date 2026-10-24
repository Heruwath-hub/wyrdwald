class_name MenuStyle
extends RefCounted
## Look shared by the menu screens: dark, gold-edged buttons and panels over the background art.

const TEXT := Color(0.93, 0.9, 0.8)
const MUTED := Color(0.75, 0.78, 0.7)
const FILL := Color(0.08, 0.1, 0.09, 0.78)
const FILL_HOVER := Color(0.16, 0.2, 0.17, 0.9)
const FILL_PRESSED := Color(0.05, 0.06, 0.05, 0.95)
const FILL_SELECTED := Color(0.28, 0.3, 0.2, 0.95)
const BORDER := Color(0.55, 0.5, 0.35)
const BORDER_HOVER := Color(0.9, 0.8, 0.5)


static func button(target: Button, font_size: int = 28) -> void:
	target.add_theme_font_size_override("font_size", font_size)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		target.add_theme_color_override(color_name, TEXT)
	target.add_theme_stylebox_override("normal", box(FILL, BORDER))
	target.add_theme_stylebox_override("hover", box(FILL_HOVER, BORDER_HOVER))
	target.add_theme_stylebox_override("pressed", box(FILL_SELECTED, BORDER_HOVER))
	target.add_theme_stylebox_override("hover_pressed", box(FILL_SELECTED, BORDER_HOVER))
	target.add_theme_stylebox_override("focus", box(FILL_HOVER, BORDER_HOVER))


static func box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 24
	style.content_margin_right = 24
	return style


static func panel(target: PanelContainer) -> void:
	var style := box(Color(0.04, 0.05, 0.045, 0.86), BORDER)
	style.set_content_margin_all(24)
	target.add_theme_stylebox_override("panel", style)
