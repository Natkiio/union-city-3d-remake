extends "res://tests/test_base.gd"
## In-world text goes through WorldText: bounded size, wrapped, fixed on screen.

func run() -> void:
	var long_text := "Oh my God. Is that even human? I really do not want to find out what happened here."
	for k in [WorldText.Kind.PROMPT, WorldText.Kind.NAME, WorldText.Kind.BUBBLE, WorldText.Kind.MARKER]:
		var l := WorldText.make(long_text, k)
		var tag := str(WorldText.Kind.find_key(k))
		check("%s is fixed size" % tag, l.fixed_size and l.billboard == BaseMaterial3D.BILLBOARD_ENABLED)
		check("%s pixel_size small" % tag, l.pixel_size <= 0.001)
		check("%s font <= 40px" % tag, l.font_size <= 40)
		check("%s width <= 1/3 of 1600" % tag, l.width * WorldText.SCREEN_SCALE <= 1600.0 / 3.0)
		check("%s wraps" % tag, l.autowrap_mode != TextServer.AUTOWRAP_OFF)
		var f := ThemeDB.fallback_font
		var one := f.get_string_size(long_text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size)
		var wrapped := f.get_multiline_string_size(long_text, HORIZONTAL_ALIGNMENT_CENTER, l.width, l.font_size, -1, TextServer.BREAK_WORD_BOUND)
		if k != WorldText.Kind.MARKER:
			check("%s long text wraps to several lines" % tag, wrapped.y > one.y * 1.5 and wrapped.x <= l.width + 1.0)
		l.free()
	var sign := WorldText.make("EXIT", WorldText.Kind.SIGN)
	check("sign is world sized but width capped", not sign.fixed_size and sign.width * sign.pixel_size < 4.0)
	sign.free()
	var c := WorldText.make("Gun Cabinet\nLOCKED - NORMAL", WorldText.Kind.PROMPT)
	check("two line prompt keeps its break", c.text.contains("\n"))
	c.free()
