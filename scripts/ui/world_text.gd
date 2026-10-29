class_name WorldText
extends Label3D
## One place for in-world text (Label3D): prompts, names, bubbles, markers, signs.
## Screen-space kinds (PROMPT, NAME, BUBBLE, MARKER) are fixed_size: a constant
## on-screen size at any camera distance, wrapped to a width and nudged back
## inside the window when they would run off an edge. SIGN kinds sit on walls and
## scale with the scene, so they stay world-sized but are capped in width.

enum Kind { PROMPT, NAME, BUBBLE, MARKER, TITLE, SIGN }

## On-screen pixels per font pixel for a fixed_size label at pixel_size FIXED_PS.
const FIXED_PS := 0.0007
const SCREEN_SCALE := 1.0
const SCREEN_MARGIN := 10.0
const OUTLINE := Color(0.05, 0.04, 0.04)
const MAX_SCREEN_WIDTH := 1.0 / 3.0 ## of the window, for any screen-space kind

## kind -> [font_size (= on-screen px), wrap width in font px, outline px, fixed]
const SPEC := {
	Kind.PROMPT: [24, 260, 7, true],
	Kind.NAME: [24, 260, 7, true],
	Kind.BUBBLE: [24, 280, 7, true],
	Kind.MARKER: [40, 80, 10, true],
	Kind.TITLE: [30, 640, 8, false],
	Kind.SIGN: [28, 420, 8, false],
}

var kind: int = Kind.PROMPT
var clamp_to_screen := false


## A ready label. `color` defaults to white; world-sized kinds ignore font_px
## unless given (wall signs pick their own size).
static func make(text: String, k: int = Kind.PROMPT, color: Color = Color.WHITE, font_px: int = 0) -> WorldText:
	var l := WorldText.new()
	l.kind = k
	var s: Array = SPEC[k]
	var fixed: bool = s[3]
	l.font_size = font_px if font_px > 0 else int(s[0])
	l.width = float(s[1])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.outline_size = int(s[2])
	l.outline_modulate = OUTLINE
	l.modulate = color
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.shaded = false
	l.double_sided = false
	l.text = text
	if fixed:
		l.fixed_size = true
		l.pixel_size = FIXED_PS
		l.no_depth_test = true
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.clamp_to_screen = true
	else:
		l.pixel_size = 0.006
	return l


## Largest on-screen width, px, this label can take (fixed kinds only).
func max_screen_px(viewport_w: float) -> float:
	return minf(width * SCREEN_SCALE, viewport_w * MAX_SCREEN_WIDTH) if fixed_size else width * SCREEN_SCALE


func _process(_delta: float) -> void:
	if not clamp_to_screen or not visible or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(global_position):
		return
	var vp := get_viewport().get_visible_rect().size
	var f: Font = font if font != null else ThemeDB.fallback_font
	var size := f.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size)
	var half := (minf(size.x, width) * 0.5 + outline_size) * SCREEN_SCALE
	var sx := cam.unproject_position(global_position).x
	var shift := 0.0
	if sx - half < SCREEN_MARGIN:
		shift = SCREEN_MARGIN - (sx - half)
	elif sx + half > vp.x - SCREEN_MARGIN:
		shift = (vp.x - SCREEN_MARGIN) - (sx + half)
	offset.x = shift / SCREEN_SCALE
