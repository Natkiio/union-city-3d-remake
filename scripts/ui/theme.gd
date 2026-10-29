class_name UITheme
extends RefCounted
## One place for the UI look: colours, font sizes, panel styles. Every screen
## calls UITheme.theme() and the helpers below; nothing else hard-codes a colour.

const BG := Color(0.05, 0.05, 0.06)
const PANEL := Color(0.09, 0.09, 0.10, 0.94)
const PANEL_EDGE := Color(0.28, 0.27, 0.25)
const TEXT := Color(0.86, 0.84, 0.80)
const TEXT_DIM := Color(0.55, 0.54, 0.51)
const ACCENT := Color(0.72, 0.12, 0.10)
const ACCENT_HI := Color(0.88, 0.22, 0.16)
const GOOD := Color(0.30, 0.65, 0.34)
const WARN := Color(0.90, 0.68, 0.18)
const BAD := Color(0.85, 0.15, 0.15)
const STAMINA := Color(0.80, 0.72, 0.28)
const XP := Color(0.35, 0.55, 0.80)
const DIM := Color(0, 0, 0, 0.62)

const FS_SMALL := 14
const FS_BODY := 17
const FS_HEAD := 26
const FS_TITLE := 60

static var _theme: Theme = null


static func box(bg: Color, edge: Color = PANEL_EDGE, border: int = 1, radius: int = 3, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = FS_BODY
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_stylebox("normal", "Button", box(Color(0.14, 0.13, 0.13), PANEL_EDGE, 1, 3, 10))
	t.set_stylebox("hover", "Button", box(Color(0.30, 0.09, 0.08), ACCENT_HI, 1, 3, 10))
	t.set_stylebox("pressed", "Button", box(ACCENT, ACCENT_HI, 1, 3, 10))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT_HI, 2, 3, 10))
	t.set_stylebox("disabled", "Button", box(Color(0.09, 0.09, 0.09), Color(0.18, 0.18, 0.18), 1, 3, 10))
	t.set_stylebox("panel", "PanelContainer", box(PANEL))
	t.set_stylebox("panel", "Panel", box(PANEL))
	t.set_stylebox("background", "ProgressBar", box(Color(0.04, 0.04, 0.04, 0.85), Color(0.2, 0.2, 0.2), 1, 2, 0))
	t.set_stylebox("fill", "ProgressBar", box(GOOD, GOOD, 0, 2, 0))
	_theme = t
	return t


static func label(text: String, size: int = FS_BODY, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 40)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## A thin themed bar. `color` is the fill colour.
static func bar(color: Color, height: float = 14.0, width: float = 240.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(width, height)
	p.max_value = 100.0
	p.value = 100.0
	set_bar_color(p, color)
	return p


static func set_bar_color(p: ProgressBar, color: Color) -> void:
	p.add_theme_stylebox_override("fill", box(color, color, 0, 2, 0))


## Draws text with a dark outline so it reads over the game world.
static func outline(l: Label) -> Label:
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l
