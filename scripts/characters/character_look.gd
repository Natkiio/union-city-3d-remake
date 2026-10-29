class_name CharacterLook
extends RefCounted
## Dresses a male_basic rig from an original-game character record (npc.json
## fields: sex, skinColour, hairColour, hair, clothesTop, clothesBottom,
## clothesShoe, faceAccessory, torsoAccessory, headAccessory, backpack).
## Static and autoload-free: call CharacterLook.apply(model_root, record) on
## any instance of scenes/characters/male_basic.tscn.
##
## The rig is ONE skinned mesh with two surfaces (Clothes, Skin). To tell shoes,
## trousers, top and sleeves apart the first call builds a patched copy of the
## mesh (cached, shared by all characters) whose vertex colour holds
## the rest-pose position; a small shader maps it to the colours of the record. Hair,
## hats, face gear, vests and backpacks are flat boxes on bone attachments.
##
## Handy for callers: accessory meshes are named "LookBox*" under bone
## attachments "LookHead"/"LookChest"; top_y(model_root) is the model-space height of the head top (name labels and
## quest markers go above it); set_highlight() is a brightness bump.

const HAIR_BONE := "Head"
const FEMALE_SCALE := Vector3(0.93, 0.97, 0.93)
## The rig faces its local -Z; rotation.y = -PI/2 turns it to face +X.

## COLOR carries the rest-pose position: r = y / 2, g = |x| * 2, a = 1 for the
## skin surface. Interpolating it (not a per-vertex id) keeps the colour bands
## clean on the long leg and arm polygons.
const SHADER_CODE := """
shader_type spatial;
uniform vec3 shoe : source_color;
uniform vec3 bottom : source_color;
uniform vec3 top : source_color;
uniform vec3 skin : source_color;
uniform float short_sleeves = 0.0;
uniform float boost = 0.0;
varying float ry;
varying float rx;
varying flat float is_skin;
void vertex() { ry = COLOR.r * 2.0; rx = COLOR.g * 0.5; is_skin = COLOR.a; }
void fragment() {
	vec3 c = skin;
	if (is_skin < 0.5) {
		if (ry < 0.11) c = shoe;
		else if (rx > 0.2 && ry > 0.6) c = (ry < 1.08 && short_sleeves > 0.5) ? skin : top;
		else if (ry < 0.86) c = bottom;
		else c = top;
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
	EMISSION = c * boost;
}
"""

static var _shader: Shader
static var _patched: Dictionary = {} # source mesh -> patched ArrayMesh

# ---------------------------------------------------------------- colours

const SKIN := {
	"white": Color(0.93, 0.76, 0.66), "tanned": Color(0.78, 0.58, 0.42),
	"tan": Color(0.78, 0.58, 0.42), "brown": Color(0.55, 0.38, 0.27),
	"black": Color(0.36, 0.24, 0.17), "olive": Color(0.72, 0.58, 0.4),
}
const HAIR := {
	"black": Color(0.07, 0.06, 0.06), "blonde": Color(0.88, 0.75, 0.4),
	"grey": Color(0.62, 0.62, 0.64), "red": Color(0.6, 0.22, 0.1),
	"dark brown": Color(0.2, 0.12, 0.07), "dark blonde": Color(0.65, 0.5, 0.25),
	"brown": Color(0.35, 0.2, 0.1), "light brown": Color(0.5, 0.35, 0.2),
}
## First keyword found in the lower-cased clothes name wins.
const TOPS := [
	["hospital", Color(0.62, 0.8, 0.7)], ["armytop", Color(0.33, 0.37, 0.22)],
	["biohazard", Color(0.92, 0.8, 0.1)], ["scrubs", Color(0.2, 0.62, 0.64)],
	["workapron", Color(0.58, 0.44, 0.28)], ["tls", Color(0.2, 0.26, 0.36)],
	["unionsec", Color(0.18, 0.3, 0.5)], ["herc", Color(0.14, 0.14, 0.16)],
	["police", Color(0.1, 0.14, 0.3)], ["military", Color(0.33, 0.37, 0.22)],
	["hazmat", Color(0.92, 0.8, 0.1)], ["suit", Color(0.38, 0.38, 0.42)],
	["checkers", Color(0.25, 0.35, 0.72)], ["hoody", Color(0.1, 0.1, 0.12)],
	["longsleeveblack", Color(0.2, 0.2, 0.24)], ["longsleevered", Color(0.5, 0.1, 0.16)],
	["longsleevewhite", Color(0.78, 0.82, 0.88)], ["_shirtblue", Color(0.5, 0.65, 0.88)],
	["blue", Color(0.2, 0.38, 0.8)], ["red", Color(0.75, 0.15, 0.15)],
	["green", Color(0.2, 0.55, 0.28)], ["black", Color(0.1, 0.1, 0.12)],
	["white", Color(0.9, 0.9, 0.88)], ["brown", Color(0.45, 0.3, 0.18)],
]
const BOTTOMS := [
	["army", Color(0.26, 0.3, 0.17)], ["biohazard", Color(0.85, 0.72, 0.08)],
	["hazmat", Color(0.85, 0.72, 0.08)], ["scrubs", Color(0.18, 0.55, 0.58)],
	["tls", Color(0.17, 0.2, 0.28)], ["herc", Color(0.1, 0.1, 0.12)],
	["police", Color(0.08, 0.1, 0.22)], ["camo", Color(0.38, 0.42, 0.24)],
	["jeansblue", Color(0.2, 0.3, 0.52)], ["jeansblack", Color(0.1, 0.1, 0.13)],
	["jeans", Color(0.2, 0.3, 0.52)], ["grey", Color(0.45, 0.45, 0.48)],
	["brown", Color(0.4, 0.28, 0.18)], ["black", Color(0.1, 0.1, 0.12)],
]
const SHOES := [
	["army", Color(0.22, 0.2, 0.12)], ["black", Color(0.07, 0.07, 0.08)],
	["brown", Color(0.34, 0.2, 0.1)], ["white", Color(0.92, 0.92, 0.9)],
]
const SHORT_SLEEVE_WORDS := ["tshirt", "scrubs", "hospital", "none", "apron", "tls"]

static func _lookup(table: Array, name: String, default: Color) -> Color:
	var n := "_" + name.to_lower().trim_prefix("male_").trim_prefix("female_") # "_" anchors the start
	for row in table:
		if n.contains(row[0]):
			return row[1]
	return default

static func skin_color(name: String) -> Color:
	return SKIN.get(name.to_lower(), SKIN["white"])

static func hair_color(name: String) -> Color:
	return HAIR.get(name.to_lower(), HAIR["brown"])

static func top_color(name: String, skin: Color = SKIN["white"]) -> Color:
	if name == "" or name.ends_with("_none") or name == "none":
		return skin
	return _lookup(TOPS, name, Color(0.5, 0.47, 0.42))

static func bottom_color(name: String) -> Color:
	if name == "" or name == "none":
		return Color(0.18, 0.18, 0.2) # shorts / underwear: dark
	return _lookup(BOTTOMS, name, Color(0.4, 0.38, 0.35))

static func shoe_color(name: String) -> Color:
	if name == "" or name == "none":
		return Color(0.35, 0.28, 0.25) # bare feet read as dark socks
	return _lookup(SHOES, name, Color(0.1, 0.1, 0.1))

# ---------------------------------------------------------------- crowds

const _SKINS := ["White", "White", "White", "Tanned", "Black", "Olive"]
const _HAIRC := ["Black", "Blonde", "Grey", "Dark Brown", "Brown", "Red", "Light Brown"]
const _HAIRS := ["none", "bald", "cropped", "short1", "short2", "short3", "medium1", "ponytail1", "long1", "afro"]
const _TOPS_M := ["male_tshirtBlue", "male_tshirtRed", "male_hoodyBlack", "male_longSleeveWhite", "male_shirtBlue", "male_checkersBlue", "male_tshirtBrown", "male_suitGrey", "male_armyTop", "male_workApron"]
const _TOPS_F := ["female_tshirtBlue", "female_tshirtRed", "female_longSleeveGreen", "female_shirtBlue", "female_tshirtWhite"]
const _BOTTOMS := ["jeansBlue", "jeansBlack", "pantsGrey", "pantsBrown"]
const _HEADS := ["none", "none", "none", "capBlue", "none"]
const _FACES := ["none", "none", "none", "glasses", "none", "sunglassesBig"]

static func random_record(rng: RandomNumberGenerator) -> Dictionary:
	var female := rng.randf() < 0.35
	var sex := "female" if female else "male"
	var tops: Array = _TOPS_F if female else _TOPS_M
	return {
		"sex": sex,
		"skinColour": _SKINS[rng.randi() % _SKINS.size()],
		"hairColour": _HAIRC[rng.randi() % _HAIRC.size()],
		"hair": _HAIRS[rng.randi() % _HAIRS.size()],
		"clothesTop": tops[rng.randi() % tops.size()],
		"clothesBottom": sex + "_" + _BOTTOMS[rng.randi() % _BOTTOMS.size()],
		"clothesShoe": ["shoeBlack", "shoeBrown", "shoeWhite"][rng.randi() % 3],
		"faceAccessory": _FACES[rng.randi() % _FACES.size()],
		"torsoAccessory": "none",
		"headAccessory": _HEADS[rng.randi() % _HEADS.size()],
		"backpack": rng.randf() < 0.2,
	}

# ---------------------------------------------------------------- apply

## Dresses `model_root` (a male_basic.tscn instance). Safe to call again.
## Optional record keys: bodyScale (float or Vector3, multiplies the sex scale).
static func apply(model_root: Node3D, record: Dictionary) -> void:
	var mi := _body_mesh(model_root)
	var skeleton := model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if mi == null or skeleton == null:
		push_warning("CharacterLook.apply: no skinned mesh under %s" % model_root.name)
		return
	var seed_val := hash(str(record.get("ref", record.get("name", record.get("hair", "")))) + str(record.get("clothesTop", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var rec := _resolve_random(record, rng)

	var skin := skin_color(str(rec["skinColour"]))
	var top_name := str(rec.get("clothesTop", ""))
	var short := false
	for w in SHORT_SLEEVE_WORDS:
		if top_name.to_lower().contains(w):
			short = true
	if top_name.to_lower().contains("longsleeve") or top_name.to_lower().contains("hoody"):
		short = false
	var top := top_color(top_name, skin)
	var cloth := _material()
	cloth.set_shader_parameter("skin", skin)
	cloth.set_shader_parameter("top", top)
	cloth.set_shader_parameter("bottom", bottom_color(str(rec.get("clothesBottom", ""))))
	cloth.set_shader_parameter("shoe", shoe_color(str(rec.get("clothesShoe", ""))))
	cloth.set_shader_parameter("short_sleeves", 1.0 if short else 0.0)
	var skin_mat := _material()
	for p in ["skin", "top", "bottom", "shoe"]:
		skin_mat.set_shader_parameter(p, skin)

	_patch_mesh(mi)
	mi.set_surface_override_material(0, cloth)
	mi.set_surface_override_material(1, skin_mat)
	model_root.set_meta("look_materials", [cloth, skin_mat])

	var female := str(rec.get("sex", "male")) == "female"
	var s: Vector3 = FEMALE_SCALE if female else Vector3.ONE
	var bs = rec.get("bodyScale", 1.0)
	s *= (bs if bs is Vector3 else Vector3.ONE * float(bs))
	model_root.scale = s
	_build_accessories(skeleton, rec, female, top, hair_color(str(rec.get("hairColour", "Brown"))))


## Brightness bump used for the hover highlight.
static func set_highlight(model_root: Node3D, on: bool) -> void:
	for m in model_root.get_meta("look_materials", []):
		(m as ShaderMaterial).set_shader_parameter("boost", 0.35 if on else 0.0)
	for n in model_root.find_children("LookBox*", "MeshInstance3D", true, false):
		var mat := (n as MeshInstance3D).material_override as StandardMaterial3D
		if mat != null:
			mat.emission_enabled = on
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 0.35


## Height (in model space, unscaled) of the top of the head including hair/hat.
static func top_y(model_root: Node3D) -> float:
	var y := 1.7
	for n in model_root.find_children("LookBox*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		y = maxf(y, (mi.global_transform * mi.get_aabb().end).y - model_root.global_position.y)
	return y / maxf(model_root.scale.y, 0.01)


static func _resolve_random(record: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var r := record.duplicate()
	var skin = r.get("skinColour", "White")
	if skin is String and skin == "random":
		r["skinColour"] = _SKINS[rng.randi() % _SKINS.size()]
	elif not (skin is String): # {"$expr": "player.skinColour"} and the like
		r["skinColour"] = "White"
	r["skinColour"] = r.get("skinColour", "White")
	var hc = r.get("hairColour", "random")
	if not (hc is String) or hc == "random":
		r["hairColour"] = _HAIRC[rng.randi() % _HAIRC.size()]
	if str(r.get("hair", "")) == "random":
		r["hair"] = _HAIRS[rng.randi() % _HAIRS.size()]
	return r


static func _body_mesh(root: Node) -> MeshInstance3D:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		if not str(n.name).begins_with("LookBox"):
			return n
	return null


static func _material() -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


## Builds (once per source mesh) a copy carrying the rest position in COLOR.
static func _patch_mesh(mi: MeshInstance3D) -> void:
	var src: Mesh = mi.mesh
	if src.has_meta("look_patched"):
		return
	if _patched.has(src):
		mi.mesh = _patched[src]
		return
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for i in verts.size():
			cols[i] = Color(verts[i].y / 2.0, absf(verts[i].x) * 2.0, 0.0, 1.0 if s == 1 else 0.0)
		arrays[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_name(s, src.surface_get_name(s))
	out.set_meta("look_patched", true)
	_patched[src] = out
	mi.mesh = out


# ---------------------------------------------------------------- accessories

static func _build_accessories(skeleton: Skeleton3D, rec: Dictionary, female: bool, top: Color, hair: Color) -> void:
	for old in ["LookHead", "LookChest"]:
		var o := skeleton.get_node_or_null(old)
		if o != null:
			skeleton.remove_child(o)
			o.queue_free()
	var head := _attach(skeleton, "Head")
	var chest := _attach(skeleton, "Chest")

	# Head frame: bone origin is the neck top; head centre about +0.15 up, face toward -Z.
	var style := str(rec.get("hair", "none"))
	var head_acc := str(rec.get("headAccessory", "none"))
	var hatted := head_acc != "none"
	if style not in ["none", "bald", "shaved", ""]:
		_hair(head, style, hair, female, hatted)
	_head_gear(head, head_acc)
	_face_gear(head, str(rec.get("faceAccessory", "none")))
	var vest := str(rec.get("torsoAccessory", "none"))
	if vest != "none":
		var vc := Color(0.14, 0.14, 0.16) if vest.to_lower().contains("herc") else (Color(0.3, 0.34, 0.2) if vest.to_lower().contains("army") else Color(0.16, 0.2, 0.3))
		_box(chest, Vector3(0.44, 0.36, 0.3), Vector3(0, 0.02, 0), vc)
	if rec.get("backpack", false):
		_box(chest, Vector3(0.3, 0.34, 0.14), Vector3(0, 0.0, 0.2), top.darkened(0.45))


static func _attach(skeleton: Skeleton3D, bone: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.name = "Look" + bone
	a.bone_name = bone
	skeleton.add_child(a)
	return a


static func _hair(head: Node3D, style: String, color: Color, female: bool, hatted: bool) -> void:
	if hatted:
		# under a hat only the back/sides show
		if style.begins_with("long") or style.begins_with("ponytail") or female:
			_box(head, Vector3(0.3, 0.2, 0.06), Vector3(0, 0.12, 0.13), color)
		return
	match style:
		"afro":
			_sphere(head, 0.23, Vector3(0, 0.22, 0.02), color)
			return
		"cropped", "short1", "short2", "short3", "special1", "special3":
			_box(head, Vector3(0.3, 0.07, 0.28), Vector3(0, 0.285, 0.0), color)
			if style != "cropped":
				_box(head, Vector3(0.3, 0.14, 0.05), Vector3(0, 0.22, 0.135), color)
			if style.begins_with("special"):
				_box(head, Vector3(0.05, 0.12, 0.2), Vector3(0.155, 0.22, 0.0), color)
				_box(head, Vector3(0.05, 0.12, 0.2), Vector3(-0.155, 0.22, 0.0), color)
		_:
			_box(head, Vector3(0.3, 0.07, 0.28), Vector3(0, 0.285, 0.0), color)
			var drop := 0.3 if (style.begins_with("long") or female) else 0.16
			_box(head, Vector3(0.3, drop, 0.06), Vector3(0, 0.27 - drop * 0.5, 0.14), color)
			if style.begins_with("long") or style.begins_with("medium"):
				_box(head, Vector3(0.04, 0.2, 0.2), Vector3(0.155, 0.19, 0.03), color)
				_box(head, Vector3(0.04, 0.2, 0.2), Vector3(-0.155, 0.19, 0.03), color)
			if style.begins_with("ponytail"):
				_box(head, Vector3(0.07, 0.24, 0.07), Vector3(0, 0.08, 0.2), color)


static func _head_gear(head: Node3D, kind: String) -> void:
	match kind:
		"none", "":
			return
		"armyKevlar":
			_box(head, Vector3(0.34, 0.14, 0.34), Vector3(0, 0.29, 0.0), Color(0.3, 0.34, 0.2))
		"helmetHERC":
			_box(head, Vector3(0.34, 0.16, 0.34), Vector3(0, 0.29, 0.0), Color(0.12, 0.12, 0.14))
		"bioHazardHat": # hood: crown, back and sides, face left open
			var y := Color(0.92, 0.8, 0.1)
			_box(head, Vector3(0.36, 0.1, 0.36), Vector3(0, 0.29, 0.0), y)
			_box(head, Vector3(0.36, 0.3, 0.07), Vector3(0, 0.15, 0.15), y)
			_box(head, Vector3(0.05, 0.3, 0.3), Vector3(0.16, 0.15, 0.0), y)
			_box(head, Vector3(0.05, 0.3, 0.3), Vector3(-0.16, 0.15, 0.0), y)
		"rebel":
			_box(head, Vector3(0.33, 0.08, 0.33), Vector3(0, 0.285, 0.0), Color(0.5, 0.1, 0.1))
		"crown":
			_box(head, Vector3(0.28, 0.1, 0.28), Vector3(0, 0.32, 0.0), Color(0.95, 0.78, 0.1))
		_: # caps
			_box(head, Vector3(0.33, 0.09, 0.33), Vector3(0, 0.285, 0.0), Color(0.2, 0.35, 0.75))
			_box(head, Vector3(0.28, 0.025, 0.14), Vector3(0, 0.255, -0.2), Color(0.17, 0.3, 0.65))


static func _face_gear(head: Node3D, kind: String) -> void:
	match kind:
		"none", "":
			return
		"glasses", "glassesBig":
			var w := 0.3 if kind == "glassesBig" else 0.27
			_box(head, Vector3(w, 0.06, 0.03), Vector3(0, 0.16, -0.14), Color(0.08, 0.08, 0.1))
		"sunglassesBig", "goggles":
			var c := Color(0.05, 0.05, 0.06) if kind == "sunglassesBig" else Color(0.2, 0.35, 0.3)
			_box(head, Vector3(0.3, 0.09, 0.04), Vector3(0, 0.16, -0.14), c)
		"gasMask":
			_box(head, Vector3(0.28, 0.22, 0.08), Vector3(0, 0.1, -0.15), Color(0.22, 0.24, 0.2))
			_box(head, Vector3(0.12, 0.1, 0.12), Vector3(0, 0.06, -0.2), Color(0.12, 0.13, 0.12))
		"medicalMask":
			_box(head, Vector3(0.28, 0.12, 0.05), Vector3(0, 0.07, -0.14), Color(0.8, 0.9, 0.95))
		"bandana":
			_box(head, Vector3(0.29, 0.12, 0.05), Vector3(0, 0.07, -0.14), Color(0.55, 0.1, 0.1))
		"HERCmask":
			_box(head, Vector3(0.28, 0.24, 0.06), Vector3(0, 0.12, -0.15), Color(0.08, 0.08, 0.1))
		_:
			_box(head, Vector3(0.27, 0.06, 0.03), Vector3(0, 0.16, -0.14), Color(0.08, 0.08, 0.1))


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	m.name = "LookBox"
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = _flat(color)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


static func _sphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	m.name = "LookBox"
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 10
	s.rings = 5
	m.mesh = s
	m.position = pos
	m.material_override = _flat(color)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


static func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat
