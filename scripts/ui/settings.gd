class_name Settings
extends RefCounted
## Player settings, saved to user://settings.cfg. Static; no autoload.
## Read with Settings.get_value("head_shots_only"). Gameplay systems that care
## about a setting read it here; nothing is pushed except apply() below.

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "settings"
const BUSES := ["Master", "Sfx", "Music", "Ambient"]

const DEFAULTS := {
	"volume_Master": 1.0,
	"volume_Sfx": 1.0,
	"volume_Music": 0.8,
	"volume_Ambient": 0.8,
	"brightness": 0.5,           # 0..1, 0.5 = unchanged
	"head_shots_only": false,    # non-head hits on zombies do 1 damage
	"mode": "survivor",          # "survivor" or "runngun"
}

const KEY_HINTS := [
	["A / D", "Move"], ["Shift", "Run"], ["C", "Crouch"], ["Space", "Jump"],
	["Left click", "Attack / fire"], ["F", "Shove"], ["R", "Reload"], ["E", "Interact"],
	["I", "Inventory"], ["K", "Skills"], ["M", "Map"], ["Z", "Sleep or wait (safehouse)"],
	["1 / 2", "Fists / gun"], ["Esc", "Pause"],
]

static var path: String = DEFAULT_PATH
static var _values: Dictionary = {}
static var _loaded: bool = false


static func load_file() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		for k in DEFAULTS:
			if cfg.has_section_key(SECTION, k):
				var v: Variant = cfg.get_value(SECTION, k)
				if typeof(v) == typeof(DEFAULTS[k]):
					_values[k] = v
	_loaded = true


static func get_value(key: String, default: Variant = null) -> Variant:
	if not _loaded:
		load_file()
	if _values.has(key):
		return _values[key]
	return default if default != null else DEFAULTS.get(key)


static func set_value(key: String, value: Variant) -> void:
	if not _loaded:
		load_file()
	_values[key] = value


static func save() -> bool:
	if not _loaded:
		load_file()
	var cfg := ConfigFile.new()
	for k in _values:
		cfg.set_value(SECTION, k, _values[k])
	return cfg.save(path) == OK


## Forgets cached values so the next read comes from `path` (tests).
static func reload() -> void:
	_loaded = false


## Brightness setting (0..1, 0.5 = unchanged) as an environment brightness
## multiplier, 0.6..1.4. The original adds setting x 4 to every colour channel.
static func brightness_factor() -> float:
	return 0.6 + 0.8 * clampf(float(get_value("brightness")), 0.0, 1.0)


## Pushes settings into the systems that own the live state.
static func apply(tree: SceneTree) -> void:
	for n in tree.get_nodes_in_group("brightness_target"):
		if n.has_method("apply_brightness"):
			n.apply_brightness(brightness_factor())
	var sfx := tree.root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("set_volume"):
		for b in BUSES:
			sfx.set_volume(b, float(get_value("volume_" + b)))
	var surv := tree.root.get_node_or_null("Survival")
	if surv != null and surv.has_method("set_mode"):
		surv.set_mode(str(get_value("mode")))
