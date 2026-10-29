class_name CutoutRig
extends Node3D
## Flat 2D cutout character living in the 3D scene. Origin = the feet (y=0),
## figure faces +X when facing == 1, parts sit in thin Z layers around Z=0.
## Contract: apply_look(look), play(anim), set_facing(dir), set_aim(pitch),
## signal animation_finished(anim). Gameplay never touches the parts.
## Animation is procedural: every frame a pose (joint angles) is computed from
## (anim, time) and eased into the joints. Angle convention for limbs: 0 hangs
## straight down, positive swings forward (towards facing).

signal animation_finished(anim: String)

const ANIMS := ["idle", "walk", "run", "punch", "shove", "aim", "hurt", "die", "crawl", "rise"]
const ONESHOT := {"punch": 0.4, "shove": 0.46, "hurt": 0.36, "die": 0.95, "rise": 1.4}
const JOINTS := ["hip_x", "hip_y", "hip_rot", "torso", "head", "af_u", "af_l", "ab_u", "ab_l",
	"lf_u", "lf_l", "lf_ft", "lb_u", "lb_l", "lb_ft", "wrot"]
const FOOT_H := 0.07

var look: Dictionary = {}
var tweaks: Dictionary = {}
var facing: float = 1.0
var aim_pitch: float = 0.0
var anim: String = "idle"
var anim_speed: float = 1.0

var _t: float = 0.0
var _return_anim: String = "idle"
var _finished: bool = false
var _dead: bool = false
var _snap: bool = true
var _cur: Dictionary = {}
var _j: Dictionary = {}      # joint name -> Node3D
var _m: Dictionary = {}      # part name -> MeshInstance3D
var _dims: Dictionary = {}
var _wclass: String = "none"
var _flip: Node3D


func _init() -> void:
	for k in JOINTS:
		_cur[k] = 0.0
	_build_skeleton()
	apply_look({})


# ---------------------------------------------------------------- public API

func apply_look(new_look: Dictionary) -> void:
	look = Look.normalize(new_look)
	_wclass = Look.weapon_class(str(look["weapon"]))
	_rebuild()


## Rig tweaks (used by ZombieLooks): posture "stand"|"hunch"|"crawl"|"dog", hunch, gait,
## limp, arms_out, width, height, belly, tatter, zombie, armor[], shield.
func apply_tweaks(t: Dictionary) -> void:
	tweaks = t.duplicate(true)
	_rebuild()


func set_weapon(ref: String) -> void:
	var l := look.duplicate()
	l["weapon"] = ref
	apply_look(l)


func play(new_anim: String) -> void:
	if not ANIMS.has(new_anim):
		push_warning("CutoutRig: unknown anim '%s'" % new_anim)
		return
	if _dead and new_anim != "rise":
		return
	if new_anim == anim and not _finished:
		return
	if ONESHOT.has(anim) and not _finished and not ONESHOT.has(new_anim) and anim != "die":
		_return_anim = new_anim   # let the one-shot finish, then continue
		return
	if not ONESHOT.has(new_anim):
		_return_anim = new_anim
	anim = new_anim
	_t = 0.0
	_finished = false
	if new_anim == "rise":
		_dead = false


func set_facing(dir: float) -> void:
	if absf(dir) < 0.001:
		return
	facing = signf(dir)
	_apply_scale()


## Pitch in radians, positive = up, relative to the facing direction.
func set_aim(pitch: float) -> void:
	aim_pitch = clampf(pitch, -1.4, 1.4)


func is_dead() -> bool:
	return _dead


func mesh_count() -> int:
	var n := 0
	for c in find_children("*", "MeshInstance3D", true, false):
		if c.visible and (c as MeshInstance3D).mesh != null:
			n += 1
	return n


## Position of a named joint in rig space (e.g. "hand_f", "head"); handy for muzzle/hit effects.
func joint_position(joint: String) -> Vector3:
	var n: Node3D = _j.get(joint)
	return to_local(n.global_position) if n != null else Vector3.ZERO


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	var dt := delta * anim_speed
	_t += dt
	if ONESHOT.has(anim) and not _finished and _t >= ONESHOT[anim]:
		_finished = true
		var done := anim
		if done == "die":
			_dead = true
			_t = ONESHOT["die"]
		else:
			anim = _return_anim if _return_anim != done else "idle"
			_t = 0.0
		animation_finished.emit(done)
	var pose := _compute_pose(anim, _t)
	var k := 1.0 - exp(-delta * (40.0 if ONESHOT.has(anim) else 24.0))
	if _snap:
		k = 1.0
		_snap = false
	for j in JOINTS:
		_cur[j] = lerpf(_cur[j], pose[j], k)
	_apply_joints()


# ------------------------------------------------------------------- skeleton

func _node(parent: Node3D, node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	_j[node_name] = n
	return n


func _mesh(parent: Node3D, part: String, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part
	mi.position.z = z
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	_m[part] = mi
	return mi


func _build_skeleton() -> void:
	_flip = _node(self, "flip")
	var hip := _node(_flip, "hip")
	var torso := _node(hip, "torso")
	_mesh(torso, "m_backpack", -0.045)
	_mesh(torso, "m_torso", 0.0)
	var neck := _node(torso, "head")
	_mesh(neck, "m_head", 0.03)
	for side in ["f", "b"]:
		var az := 0.10 if side == "f" else -0.10
		var lz := 0.06 if side == "f" else -0.08
		var au := _node(torso, "a%s_u" % side)
		au.position.z = az
		_mesh(au, "m_a%s_u" % side, 0.0)
		var al := _node(au, "a%s_l" % side)
		_mesh(al, "m_a%s_l" % side, 0.0)
		var hand := _node(al, "hand_%s" % side)
		hand.position = Vector3.ZERO
		var lu := _node(hip, "l%s_u" % side)
		lu.position.z = lz
		_mesh(lu, "m_l%s_u" % side, 0.0)
		var ll := _node(lu, "l%s_l" % side)
		_mesh(ll, "m_l%s_l" % side, 0.0)
		var ft := _node(ll, "l%s_ft" % side)
		_mesh(ft, "m_l%s_ft" % side, 0.0)
	var w := _node(torso, "wrot")
	w.position.z = 0.08
	_mesh(w, "m_weapon", 0.0)


func _rebuild() -> void:
	_compute_dims()
	_layout()
	_build_meshes()
	_apply_scale()
	_snap = true


func _compute_dims() -> void:
	var post: String = tweaks.get("posture", "stand")
	var female: bool = look["sex"] == "female"
	var d := {"leg_up": 0.45, "leg_lo": 0.40, "arm_up": 0.30, "arm_lo": 0.27, "torso_h": 0.56,
		"tw": 0.9 if female else 1.08, "scale": 0.96 if female else 1.0}
	if post == "dog":
		d = {"leg_up": 0.25, "leg_lo": 0.25, "arm_up": 0.24, "arm_lo": 0.24, "torso_h": 0.62,
			"tw": 1.0, "scale": 1.0}
	d["tw"] = float(d["tw"]) * float(tweaks.get("width", 1.0))
	d["scale"] = float(d["scale"]) * float(tweaks.get("height", 1.0))
	d["hip_y"] = float(d["leg_up"]) + float(d["leg_lo"]) + FOOT_H
	_dims = d


func _layout() -> void:
	var d := _dims
	var dog: bool = tweaks.get("posture", "") == "dog"
	_j["hip"].position = Vector3(0, d["hip_y"], 0)
	_j["head"].position = Vector3(0.0, d["torso_h"], 0.0)
	var sh := Vector3(0.015, float(d["torso_h"]) - 0.07, 0)
	if dog:
		sh = Vector3(0.0, float(d["torso_h"]) - 0.06, 0)
	for side in ["f", "b"]:
		var au: Node3D = _j["a%s_u" % side]
		au.position = Vector3(sh.x, sh.y, au.position.z)
		_j["a%s_l" % side].position = Vector3(0, -d["arm_up"], 0)
		_j["hand_%s" % side].position = Vector3(0, -d["arm_lo"], 0)
		var lu: Node3D = _j["l%s_u" % side]
		var lx := (0.02 if side == "f" else -0.02)
		if dog:
			lx = 0.03 if side == "f" else -0.01
		lu.position = Vector3(lx, 0, lu.position.z)
		_j["l%s_l" % side].position = Vector3(0, -d["leg_up"], 0)
		_j["l%s_ft" % side].position = Vector3(0, -d["leg_lo"], 0)
	_j["wrot"].position = Vector3(sh.x, sh.y, _j["wrot"].position.z)


func _apply_scale() -> void:
	var s: float = _dims.get("scale", 1.0)
	_flip.scale = Vector3(facing * s, s, s)


func _apply_joints() -> void:
	var c := _cur
	_j["hip"].position = Vector3(c["hip_x"], _dims["hip_y"] + c["hip_y"], 0)
	_j["hip"].rotation.z = c["hip_rot"]
	for k in ["torso", "head", "af_u", "af_l", "ab_u", "ab_l", "lf_u", "lf_l", "lf_ft", "lb_u", "lb_l", "lb_ft", "wrot"]:
		_j[k].rotation.z = c[k]
	# a back arm that grips a gun sits in front of the weapon
	var two_hand := _wclass == "pistol" or _wclass == "long"
	_j["ab_u"].position.z = 0.085 if two_hand and anim != "die" else -0.10


# ------------------------------------------------------------------ meshes

func _skin() -> Color:
	var c := Look.skin_color(look["skinColour"])
	if tweaks.get("zombie", false):
		c = c.lerp(Color(0.5, 0.58, 0.46), 0.65).darkened(0.12)
	return c


func _cloth(c: Color) -> Color:
	if tweaks.get("tatter", false):
		return c.lerp(Color(0.3, 0.29, 0.27), 0.4).darkened(0.18)
	return c


func _set_part(part: String, items: Array) -> void:
	var mi: MeshInstance3D = _m[part]
	if items.is_empty():
		mi.mesh = null
		mi.visible = false
	else:
		mi.mesh = CutShapes.make_mesh(items)
		mi.visible = true


func _build_meshes() -> void:
	var d := _dims
	var skin := _skin()
	var top := Look.top_style(look["clothesTop"])
	var bot := Look.bottom_style(look["clothesBottom"])
	var top_c := _cloth(top["c"]) if not top["over"].has("skin") else skin
	var bot_c := _cloth(bot["c"]) if bot["kind"] != "none" else skin
	var shoe_c := Look.shoe_color(look["clothesShoe"]) if look["clothesShoe"] != "none" else skin
	var armor: Array = tweaks.get("armor", [])
	var post: String = tweaks.get("posture", "stand")
	var dog := post == "dog"
	var tw: float = d["tw"]
	# limbs
	var sleeve_u := top_c if top["sleeve"] != "none" else skin
	var sleeve_l := top_c if top["sleeve"] == "long" else skin
	if dog:
		sleeve_u = skin
		sleeve_l = skin
		bot_c = skin
	var aw := 0.125 * (1.0 + (tw - 1.0) * 0.5)
	for side in ["f", "b"]:
		var shade := 1.0 if side == "f" else 0.82
		var a_items := [CutShapes.item(CutShapes.capsule(d["arm_up"], aw, aw * 0.85), _sh(sleeve_u, shade))]
		_set_part("m_a%s_u" % side, a_items)
		var l_items := [CutShapes.item(CutShapes.capsule(d["arm_lo"], aw * 0.85, aw * 0.7), _sh(sleeve_l, shade))]
		if armor.has("elbows"):
			l_items.append(CutShapes.item(CutShapes.ellipse(0.0, 0.0, 0.07, 0.07, 8), _sh(Color(0.17, 0.18, 0.2), shade)))
		var hand_c := Color(0.15, 0.15, 0.16) if (armor.has("gloves")) else skin
		var hr := 0.048 if not dog else 0.04
		l_items.append(CutShapes.item(CutShapes.ellipse(0, -float(d["arm_lo"]) - 0.01, hr, hr, 8), _sh(hand_c, shade)))
		_set_part("m_a%s_l" % side, l_items)
		var lw := 0.18 * (1.0 + (tw - 1.0) * 0.6)
		_set_part("m_l%s_u" % side, [CutShapes.item(CutShapes.capsule(d["leg_up"], lw, lw * 0.78), _sh(bot_c, shade))])
		var sh_items := [CutShapes.item(CutShapes.capsule(d["leg_lo"], lw * 0.78, lw * 0.6), _sh(bot_c, shade))]
		if armor.has("shins"):
			sh_items.append(CutShapes.item(CutShapes.capsule(float(d["leg_lo"]) * 0.7, lw * 0.9, lw * 0.75).duplicate(), _sh(Color(0.15, 0.16, 0.19), shade)))
		_set_part("m_l%s_l" % side, sh_items)
		_set_part("m_l%s_ft" % side, [CutShapes.item(_foot_poly(dog), _sh(shoe_c if not dog else skin.darkened(0.2), shade))])
	# core parts
	if dog:
		_set_part("m_torso", _dog_body(skin))
		_set_part("m_head", _dog_head(skin))
		_set_part("m_backpack", [])
	else:
		_set_part("m_torso", _torso_items(top, top_c, skin, armor))
		_set_part("m_head", _head_items(skin))
		_set_part("m_backpack", _backpack_items() if look["backpack"] else [])
	_set_part("m_weapon", _weapon_items())
	_j["wrot"].visible = _wclass != "none"


static func _sh(c: Color, f: float) -> Color:
	return Color(c.r * f, c.g * f, c.b * f, 1.0)


func _foot_poly(dog: bool) -> PackedVector2Array:
	if dog:
		return PackedVector2Array([Vector2(-0.04, 0.03), Vector2(0.05, 0.03), Vector2(0.09, -0.04), Vector2(-0.04, -0.06)])
	return PackedVector2Array([Vector2(-0.05, 0.035), Vector2(0.04, 0.04), Vector2(0.10, 0.0), Vector2(0.17, -0.02),
		Vector2(0.17, -0.07), Vector2(-0.06, -0.07)])


func _torso_items(top: Dictionary, top_c: Color, skin: Color, armor: Array) -> Array:
	var d := _dims
	var H: float = d["torso_h"]
	var w: float = d["tw"]
	var belly: float = tweaks.get("belly", 0.0)
	var female: bool = look["sex"] == "female"
	var items: Array = []
	var over: Array = top["over"]
	if over.has("hood"):
		items.append(CutShapes.item(CutShapes.ellipse(-0.08 * w, H - 0.03, 0.1, 0.09, 10), top_c.darkened(0.15)))
	var bust := 0.02 if female else 0.0
	var pts := PackedVector2Array([
		Vector2(-0.10 * w, 0.0), Vector2(-0.135 * w, 0.20), Vector2(-0.125 * w, 0.42), Vector2(-0.085 * w, H - 0.04),
		Vector2(-0.035 * w, H + 0.01), Vector2(0.05 * w, H), Vector2(0.11 * w, H - 0.08),
		Vector2(0.13 * w + bust, 0.36), Vector2(0.115 * w + belly, 0.22), Vector2(0.105 * w + belly * 0.7, 0.04)])
	var hem := PackedVector2Array()
	if tweaks.get("tatter", false):
		var xs := [0.105 * w + belly * 0.5, 0.075 * w, 0.04 * w, 0.0, -0.04 * w, -0.08 * w, -0.11 * w]
		for i in xs.size():
			hem.append(Vector2(xs[i], -0.01 - (0.09 if i % 2 == 1 else 0.0)))
	else:
		hem = PackedVector2Array([Vector2(0.105 * w + belly * 0.7, -0.01), Vector2(-0.10 * w, -0.01)])
	# polygon order: back side up, front side down, then hem back to start
	var full := PackedVector2Array()
	for i in 9:
		full.append(pts[i])
	full.append(Vector2(0.105 * w + belly * 0.7, 0.04))
	for v in hem:
		full.append(v)
	items.append(CutShapes.item(full, top_c))
	if over.has("apron"):
		items.append(CutShapes.item(CutShapes.box(0.0, 0.0, 0.125 * w + belly, 0.4), Color(0.28, 0.22, 0.17)))
	if over.has("pockets"):
		items.append(CutShapes.item(CutShapes.box(0.04 * w, 0.28, 0.115 * w, 0.37), top_c.darkened(0.25)))
		items.append(CutShapes.item(CutShapes.box(0.04 * w, 0.1, 0.11 * w, 0.18), top_c.darkened(0.25)))
	if over.has("hazard"):
		items.append(CutShapes.item(CutShapes.box(-0.13 * w, 0.22, 0.13 * w, 0.28), Color(0.1, 0.1, 0.1)))
	if over.has("badge"):
		items.append(CutShapes.item(CutShapes.ellipse(0.075 * w, H - 0.17, 0.028, 0.032, 6), Color(0.7, 0.68, 0.5)))
	if over.has("stripe"):
		items.append(CutShapes.item(CutShapes.box(-0.135 * w, 0.16, 0.135 * w, 0.2), Color(0.75, 0.42, 0.12)))
	if over.has("plaid"):
		items.append(CutShapes.item(CutShapes.box(-0.13 * w, 0.31, 0.13 * w, 0.34), top_c.lightened(0.25)))
		items.append(CutShapes.item(CutShapes.box(-0.13 * w, 0.14, 0.13 * w, 0.17), top_c.lightened(0.25)))
		items.append(CutShapes.item(CutShapes.box(0.0, 0.0, 0.03, H - 0.05), top_c.darkened(0.3)))
	if over.has("tie"):
		items.append(CutShapes.item(PackedVector2Array([Vector2(0.09 * w, H - 0.03), Vector2(0.12 * w, H - 0.06), Vector2(0.115 * w, 0.2), Vector2(0.095 * w, 0.22)]), Color(0.45, 0.12, 0.14)))
	if over.has("gown"):
		items.append(CutShapes.item(PackedVector2Array([Vector2(0.06 * w, H - 0.01), Vector2(0.12 * w, H - 0.07), Vector2(0.06 * w, H - 0.14)]), skin))
	var tacc: String = look["torsoAccessory"]
	if tacc != "none" or armor.has("chest"):
		var vc := Color(0.17, 0.17, 0.19)
		if tacc.to_lower().contains("army"):
			vc = Color(0.22, 0.25, 0.16)
		elif tacc.contains("HERC"):
			vc = Color(0.12, 0.12, 0.13)
		var vest := PackedVector2Array([Vector2(-0.13 * w, 0.08), Vector2(-0.14 * w, 0.4), Vector2(-0.07 * w, H - 0.06),
			Vector2(0.09 * w, H - 0.08), Vector2(0.14 * w + belly, 0.34), Vector2(0.12 * w + belly, 0.08)])
		items.append(CutShapes.item(vest, vc))
		items.append(CutShapes.item(CutShapes.box(0.02 * w, 0.14, 0.12 * w, 0.24), vc.lightened(0.1)))
		if armor.has("chest"):
			items.append(CutShapes.item(CutShapes.box(-0.15 * w, H - 0.14, 0.15 * w, H - 0.07), vc.lightened(0.06)))
	if tweaks.get("zombie", false):
		items.append(CutShapes.item(CutShapes.ellipse(0.05 * w, 0.2, 0.05, 0.07, 7), Color(0.32, 0.05, 0.05)))
		items.append(CutShapes.item(CutShapes.ellipse(-0.06 * w, 0.4, 0.035, 0.05, 6), Color(0.28, 0.05, 0.05)))
	return items


func _backpack_items() -> Array:
	var c := Color(0.27, 0.3, 0.2) if look["clothesTop"].contains("army") else Color(0.3, 0.2, 0.15)
	var w: float = _dims["tw"]
	var poly := PackedVector2Array([Vector2(-0.12 * w, 0.06), Vector2(-0.26 * w, 0.1), Vector2(-0.29 * w, 0.3),
		Vector2(-0.24 * w, 0.5), Vector2(-0.12 * w, 0.48)])
	return [CutShapes.item(poly, c), CutShapes.item(CutShapes.box(-0.27 * w, 0.28, -0.18 * w, 0.42), c.lightened(0.15))]


# --- heads ---

func _head_items(skin: Color) -> Array:
	var cx := 0.01
	var cy := 0.2
	var rx := 0.118
	var ry := 0.138
	var zombie: bool = tweaks.get("zombie", false)
	var items: Array = []
	var D := PI / 180.0
	var hc := Look.hair_color(look["hairColour"])
	if zombie:
		hc = hc.darkened(0.35)
	var hair: String = look["hair"]
	var front: Array = []
	var back: Array = []
	var inner_pts := func(a0: float, a1: float, gx: float, gy: float) -> PackedVector2Array:
		return CutShapes.arc(cx, cy, rx * gx, ry * gy, a0 * D, a1 * D, 7)
	match hair:
		"short1":
			front.append(inner_pts.call(30, 205, 1.14, 1.12) + inner_pts.call(190, 45, 0.8, 0.82))
		"short2":
			front.append(inner_pts.call(12, 210, 1.17, 1.15) + inner_pts.call(195, 40, 0.74, 0.78))
		"short3":
			var sp := PackedVector2Array()
			for i in 9:
				var a := lerpf(25.0, 205.0, i / 8.0)
				var g := 1.32 if i % 2 == 1 else 1.1
				sp.append(Vector2(cx + cos(a * D) * rx * g, cy + sin(a * D) * ry * g))
			front.append(sp + inner_pts.call(190, 45, 0.8, 0.82))
		"cropped":
			front.append(inner_pts.call(35, 200, 1.07, 1.06) + inner_pts.call(190, 45, 0.88, 0.9))
		"shaved":
			front.append(inner_pts.call(35, 200, 1.04, 1.04) + inner_pts.call(190, 45, 0.9, 0.92))
			hc = hc.lerp(skin, 0.55)
		"long1", "medium1", "medium2":
			var drop: float = {"long1": 0.42, "medium1": 0.12, "medium2": 0.24}[hair]
			var bk: PackedVector2Array = inner_pts.call(70, 235, 1.2, 1.15)
			bk.append(Vector2(cx - rx * 1.25, cy - drop))
			bk.append(Vector2(cx - rx * 0.3, cy - drop - 0.02))
			bk.append(Vector2(cx + rx * 0.1, cy - ry * 0.4))
			back.append(bk)
			front.append(inner_pts.call(20, 200, 1.15, 1.13) + inner_pts.call(190, 40, 0.76, 0.8))
		"ponytail1":
			front.append(inner_pts.call(30, 205, 1.14, 1.12) + inner_pts.call(190, 45, 0.8, 0.82))
			back.append(CutShapes.shift(CutShapes.rotated(CutShapes.capsule(0.3, 0.09, 0.03), -0.75), Vector2(cx - 0.1, cy + 0.04)))
		"afro":
			back.append(CutShapes.ellipse(cx - 0.02, cy + 0.04, rx * 1.55, ry * 1.4, 16))
			front.append(inner_pts.call(40, 170, 1.12, 1.1) + inner_pts.call(165, 45, 0.9, 0.9))
		"mohawk", "special1":
			var mp := PackedVector2Array()
			for i in 7:
				var a := lerpf(50.0, 160.0, i / 6.0)
				mp.append(Vector2(cx + cos(a * D) * rx * 1.45, cy + sin(a * D) * ry * 1.55) if i % 2 == 1 else Vector2(cx + cos(a * D) * rx * 1.05, cy + sin(a * D) * ry * 1.05))
			front.append(mp)
		"special2":
			front.append(inner_pts.call(15, 215, 1.2, 1.18) + inner_pts.call(200, 55, 0.7, 0.72))
		"special3":
			back.append(CutShapes.ellipse(cx - 0.04, cy + 0.1, 0.11, 0.09, 9))
			front.append(CutShapes.ellipse(cx + 0.03, cy + 0.15, 0.08, 0.07, 9))
			front.append(CutShapes.ellipse(cx - 0.07, cy + 0.12, 0.07, 0.07, 9))
		"bald", "none":
			pass
	for b in back:
		items.append(CutShapes.item(b, hc))
	# neck + head + ear + eye
	items.append(CutShapes.item(CutShapes.box(-0.045, -0.04, 0.05, 0.12), skin.darkened(0.12)))
	var hp := CutShapes.ellipse(cx, cy, rx, ry, 16)
	hp[0] = Vector2(cx + rx + 0.018, cy - 0.015)   # nose tip
	hp[15] = Vector2(cx + rx * 0.9, cy - ry * 0.32)
	items.append(CutShapes.item(hp, skin))
	items.append(CutShapes.item(CutShapes.ellipse(cx - 0.035, cy - 0.01, 0.022, 0.035, 6), skin.darkened(0.2)))
	if zombie:
		items.append(CutShapes.item(CutShapes.ellipse(cx + 0.055, cy + 0.04, 0.026, 0.022, 6), Color(0.85, 0.82, 0.45)))
		items.append(CutShapes.item(CutShapes.box(cx + 0.03, cy - 0.075, cx + 0.1, cy - 0.055), Color(0.2, 0.04, 0.04)))
	else:
		items.append(CutShapes.item(CutShapes.ellipse(cx + 0.058, cy + 0.04, 0.014, 0.017, 6), Color(0.06, 0.05, 0.06)))
	# facial hair
	var fh: String = look["facialHair"]
	var fc := hc
	match fh:
		"shadow":
			items.append(CutShapes.item(CutShapes.arc(cx, cy, rx * 1.02, ry * 1.02, PI * 1.05, PI * 1.9, 7) + CutShapes.arc(cx, cy, rx * 0.85, ry * 0.7, PI * 1.9, PI * 1.05, 5), skin.lerp(hc, 0.4)))
		"fullBeard":
			items.append(CutShapes.item(CutShapes.arc(cx, cy, rx * 1.08, ry * 1.1, PI * 0.95, PI * 1.95, 8) + CutShapes.arc(cx, cy + 0.03, rx * 0.75, ry * 0.5, PI * 1.9, PI * 1.0, 6), fc))
		"1980s":
			items.append(CutShapes.item(CutShapes.box(cx + 0.045, cy - 0.065, cx + rx + 0.02, cy - 0.04), fc))
		"soulPatch":
			items.append(CutShapes.item(CutShapes.box(cx + 0.06, cy - 0.11, cx + 0.085, cy - 0.08), fc))
		"lincoln":
			items.append(CutShapes.item(CutShapes.arc(cx, cy, rx * 1.05, ry * 1.08, PI * 1.25, PI * 1.9, 6) + CutShapes.arc(cx, cy, rx * 0.88, ry * 0.9, PI * 1.9, PI * 1.25, 4), fc))
		"goatee":
			items.append(CutShapes.item(CutShapes.ellipse(cx + 0.07, cy - 0.11, 0.032, 0.04, 6), fc))
			items.append(CutShapes.item(CutShapes.box(cx + 0.045, cy - 0.065, cx + rx + 0.02, cy - 0.04), fc))
	# face accessories
	var fa: String = look["faceAccessory"]
	var eye := Vector2(cx + 0.055, cy + 0.04)
	match fa:
		"glasses", "glassesBig":
			var r := 0.034 if fa == "glasses" else 0.045
			items.append(CutShapes.item(CutShapes.ellipse(eye.x, eye.y, r, r, 9), Color(0.55, 0.65, 0.7)))
			items.append(CutShapes.item(CutShapes.box(cx - 0.04, eye.y - 0.005, eye.x, eye.y + 0.008), Color(0.08, 0.08, 0.09)))
		"sunglassesBig":
			items.append(CutShapes.item(CutShapes.ellipse(eye.x, eye.y, 0.05, 0.04, 9), Color(0.05, 0.05, 0.06)))
			items.append(CutShapes.item(CutShapes.box(cx - 0.05, eye.y - 0.005, eye.x, eye.y + 0.01), Color(0.05, 0.05, 0.06)))
		"goggles":
			items.append(CutShapes.item(CutShapes.box(cx - rx, eye.y - 0.012, cx + rx, eye.y + 0.016), Color(0.1, 0.1, 0.1)))
			items.append(CutShapes.item(CutShapes.ellipse(eye.x, eye.y, 0.044, 0.04, 9), Color(0.7, 0.55, 0.2)))
		"gasMask":
			items.append(CutShapes.item(CutShapes.ellipse(cx + 0.05, cy - 0.04, 0.085, 0.085, 10), Color(0.2, 0.22, 0.2)))
			items.append(CutShapes.item(CutShapes.ellipse(cx + 0.125, cy - 0.07, 0.04, 0.04, 8), Color(0.34, 0.36, 0.3)))
			items.append(CutShapes.item(CutShapes.ellipse(eye.x, eye.y, 0.036, 0.036, 8), Color(0.06, 0.08, 0.07)))
		"medicalMask":
			items.append(CutShapes.item(CutShapes.box(cx - 0.02, cy - ry * 0.8, cx + rx + 0.02, cy - 0.005), Color(0.72, 0.78, 0.8)))
		"bandana":
			items.append(CutShapes.item(CutShapes.box(cx - 0.02, cy - ry * 0.9, cx + rx + 0.01, cy - 0.01), Color(0.5, 0.15, 0.13)))
		"HERCmask":
			items.append(CutShapes.item(CutShapes.box(cx - 0.02, cy - ry * 0.9, cx + rx + 0.03, cy - 0.005), Color(0.1, 0.1, 0.11)))
			items.append(CutShapes.item(CutShapes.box(cx + 0.03, cy + 0.03, cx + rx + 0.03, cy + 0.05), Color(0.8, 0.45, 0.1)))
	for f in front:
		items.append(CutShapes.item(f, hc))
	# head accessories
	var ha: String = look["headAccessory"]
	var dome: Callable = func(a0: float, a1: float, g: float, col: Color) -> void:
		var p := CutShapes.arc(cx, cy + 0.01, rx * g, ry * g, a0 * D, a1 * D, 9)
		items.append(CutShapes.item(p, col))
	match ha:
		"capBlue":
			dome.call(-5, 205, 1.18, Color(0.15, 0.22, 0.4))
			items.append(CutShapes.item(CutShapes.box(cx + 0.05, cy + 0.06, cx + rx + 0.12, cy + 0.095), Color(0.12, 0.18, 0.34)))
		"armyKevlar":
			dome.call(-25, 215, 1.28, Color(0.24, 0.28, 0.17))
		"rebel":
			items.append(CutShapes.item(CutShapes.box(cx - rx * 1.05, cy + 0.07, cx + rx * 1.05, cy + 0.12), Color(0.55, 0.14, 0.12)))
			items.append(CutShapes.item(PackedVector2Array([Vector2(cx - rx, cy + 0.1), Vector2(cx - rx - 0.1, cy + 0.14), Vector2(cx - rx - 0.08, cy + 0.02)]), Color(0.55, 0.14, 0.12)))
		"bioHazardHat":
			dome.call(-40, 220, 1.36, Color(0.7, 0.6, 0.17))
		"helmetHERC":
			dome.call(-30, 215, 1.3, Color(0.13, 0.13, 0.15))
			items.append(CutShapes.item(CutShapes.box(cx + 0.0, cy + 0.015, cx + rx + 0.03, cy + 0.07), Color(0.78, 0.42, 0.1)))
		"beanie":
			dome.call(0, 200, 1.17, Color(0.3, 0.12, 0.12))
			items.append(CutShapes.item(CutShapes.box(cx - rx * 1.1, cy + 0.07, cx + rx * 1.1, cy + 0.11), Color(0.22, 0.09, 0.09)))
		"crown":
			var cp := PackedVector2Array([Vector2(cx - rx, cy + ry), Vector2(cx - rx, cy + ry + 0.08), Vector2(cx - 0.05, cy + ry + 0.03),
				Vector2(cx, cy + ry + 0.1), Vector2(cx + 0.05, cy + ry + 0.03), Vector2(cx + rx, cy + ry + 0.08), Vector2(cx + rx, cy + ry)])
			items.append(CutShapes.item(cp, Color(0.78, 0.65, 0.2)))
	for a in tweaks.get("armor", []):
		match a:
			"helmet_riot":
				dome.call(-35, 220, 1.32, Color(0.12, 0.13, 0.16))
				items.append(CutShapes.item(CutShapes.box(cx + 0.02, cy + 0.0, cx + rx + 0.05, cy + 0.075), Color(0.4, 0.5, 0.55)))
			"helmet_army":
				dome.call(-25, 215, 1.28, Color(0.24, 0.28, 0.17))
			"cap_police":
				dome.call(0, 200, 1.2, Color(0.08, 0.1, 0.18))
				items.append(CutShapes.item(CutShapes.box(cx + 0.05, cy + 0.07, cx + rx + 0.11, cy + 0.1), Color(0.05, 0.06, 0.1)))
				items.append(CutShapes.item(CutShapes.ellipse(cx + 0.08, cy + 0.12, 0.022, 0.022, 6), Color(0.75, 0.65, 0.3)))
	return items


func _dog_head(skin: Color) -> Array:
	var c := skin
	return [CutShapes.item(PackedVector2Array([Vector2(-0.06, -0.02), Vector2(-0.07, 0.1), Vector2(-0.02, 0.17), Vector2(0.06, 0.16),
		Vector2(0.16, 0.08), Vector2(0.2, 0.06), Vector2(0.2, 0.0), Vector2(0.1, -0.03), Vector2(0.03, -0.06)]), c),
		CutShapes.item(PackedVector2Array([Vector2(-0.04, 0.14), Vector2(-0.07, 0.26), Vector2(0.01, 0.2)]), c.darkened(0.2)),
		CutShapes.item(CutShapes.ellipse(0.08, 0.11, 0.022, 0.02, 6), Color(0.85, 0.8, 0.4)),
		CutShapes.item(PackedVector2Array([Vector2(0.1, 0.0), Vector2(0.19, 0.0), Vector2(0.19, 0.03)]), Color(0.45, 0.06, 0.06))]


func _dog_body(skin: Color) -> Array:
	var c := skin.darkened(0.1)
	var body := PackedVector2Array([Vector2(-0.13, -0.1), Vector2(-0.17, 0.1), Vector2(-0.14, 0.45), Vector2(-0.07, 0.66),
		Vector2(0.04, 0.66), Vector2(0.14, 0.4), Vector2(0.15, 0.1), Vector2(0.1, -0.1)])
	var tail := PackedVector2Array([Vector2(-0.1, -0.08), Vector2(-0.13, -0.28), Vector2(-0.09, -0.3), Vector2(-0.05, -0.1)])
	return [CutShapes.item(tail, c), CutShapes.item(body, c),
		CutShapes.item(CutShapes.ellipse(0.02, 0.2, 0.06, 0.09, 7), Color(0.32, 0.05, 0.05))]


# --- weapons ---

func _weapon_items() -> Array:
	var ref: String = look["weapon"]
	var steel := Color(0.18, 0.18, 0.2)
	var wood := Color(0.34, 0.22, 0.13)
	var light := Color(0.62, 0.64, 0.66)
	match _wclass:
		"pistol":
			return [CutShapes.item(CutShapes.box(0.38, 0.0, 0.64, 0.055), steel),
				CutShapes.item(PackedVector2Array([Vector2(0.38, 0.0), Vector2(0.46, 0.0), Vector2(0.44, -0.11), Vector2(0.37, -0.1)]), steel.lightened(0.12))]
		"long":
			var wt: String = str((Look._weapon_table().get(ref, {}) as Dictionary).get("weaponType", ""))
			var stock := wood if wt in ["boltAction", "pumpAction", "bigRifle"] else steel.lightened(0.08)
			var len := 1.0 if wt in ["boltAction", "bigRifle", "lmg"] else 0.88
			var it := [CutShapes.item(PackedVector2Array([Vector2(0.14, 0.04), Vector2(0.4, 0.06), Vector2(0.4, -0.04), Vector2(0.26, -0.1), Vector2(0.14, -0.08)]), stock),
				CutShapes.item(CutShapes.box(0.38, -0.035, 0.7, 0.06), steel),
				CutShapes.item(CutShapes.box(0.68, 0.0, len, 0.035), steel.darkened(0.1))]
			if wt in ["assaultRifle", "assaultRifleSlow", "smg", "lmg", "bullpup"]:
				it.append(CutShapes.item(PackedVector2Array([Vector2(0.45, -0.035), Vector2(0.52, -0.035), Vector2(0.5, -0.15), Vector2(0.44, -0.14)]), steel.lightened(0.15)))
			if ref.contains("scope") or wt == "boltAction" or wt == "bigRifle":
				it.append(CutShapes.item(CutShapes.box(0.42, 0.06, 0.62, 0.095), Color(0.1, 0.1, 0.11)))
			return it
		"melee":
			return _melee_items(ref, steel, wood, light)
		"shield":
			return [CutShapes.item(CutShapes.box(0.34, -0.55, 0.46, 0.52), Color(0.27, 0.33, 0.39)),
				CutShapes.item(CutShapes.box(0.38, 0.2, 0.47, 0.42), Color(0.62, 0.72, 0.76)),
				CutShapes.item(CutShapes.box(0.38, -0.4, 0.43, 0.1), Color(0.34, 0.41, 0.47))]
	return []


func _melee_items(ref: String, steel: Color, wood: Color, light: Color) -> Array:
	var axes := ["hatchet", "cleaver", "clawHammer", "fireAxe", "battleAxe", "sledge", "mace", "shovel"]
	var blades := ["kitchenKnife", "pocketKnife", "machete", "katana", "sickle"]
	var handle := CutShapes.item(CutShapes.box(0.3, -0.02, 0.5, 0.02), wood)
	if ref in blades:
		var bl: float = {"kitchenKnife": 0.22, "pocketKnife": 0.14, "machete": 0.5, "katana": 0.72, "sickle": 0.3}[ref]
		return [handle, CutShapes.item(PackedVector2Array([Vector2(0.5, 0.025), Vector2(0.5 + bl, 0.02), Vector2(0.5 + bl + 0.03, -0.01), Vector2(0.5, -0.03)]), light)]
	if ref in axes:
		var hl := 0.5 if ref in ["fireAxe", "battleAxe", "shovel", "sledge"] else 0.22
		var head := CutShapes.item(PackedVector2Array([Vector2(0.3 + hl - 0.04, 0.02), Vector2(0.3 + hl - 0.04, 0.13), Vector2(0.3 + hl + 0.06, 0.1),
			Vector2(0.3 + hl + 0.08, -0.02)]), steel.lightened(0.25))
		if ref == "cleaver":
			head = CutShapes.item(CutShapes.box(0.42, -0.1, 0.62, 0.02), light)
		return [CutShapes.item(CutShapes.box(0.3, -0.02, 0.3 + hl, 0.02), wood), head]
	var sl: float = {"bat": 0.45, "cricketBat": 0.45, "crowbar": 0.5, "golfClub": 0.6, "hockeyStick": 0.65, "pipe": 0.5,
		"policeBaton": 0.3, "tireIron": 0.5, "woodBoard": 0.55, "nailBoard": 0.55, "guitar": 0.5}.get(ref, 0.45)
	var col := steel.lightened(0.15) if ref in ["crowbar", "pipe", "tireIron", "policeBaton"] else wood
	return [CutShapes.item(PackedVector2Array([Vector2(0.3, -0.018), Vector2(0.3 + sl, -0.035), Vector2(0.3 + sl, 0.035), Vector2(0.3, 0.018)]), col)]


# ------------------------------------------------------------------ poses

func _ik(l1: float, l2: float, target: Vector2, bend: float) -> Vector2:
	var dist := clampf(target.length(), absf(l1 - l2) + 0.02, l1 + l2 - 0.004)
	var base := atan2(target.x, -target.y)
	var alpha := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var elbow := PI - acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	return Vector2(base - bend * alpha, bend * elbow)


func _arm_ik(P: Dictionary, side: String, target: Vector2) -> void:
	var r := _ik(_dims["arm_up"], _dims["arm_lo"], target, 1.0)
	P["a%s_u" % side] = r.x
	P["a%s_l" % side] = r.y


func _legs(P: Dictionary, p: float, amp: float, knee: float, lead: float = 0.0, limp: float = 0.0) -> void:
	P["lf_u"] = amp * sin(p) + lead
	P["lf_l"] = -knee * maxf(0.0, cos(p)) - 0.05
	P["lb_u"] = amp * sin(p + PI) * (1.0 - limp * 0.6) + lead
	P["lb_l"] = -knee * maxf(0.0, cos(p + PI)) * (1.0 + limp) - 0.05
	P["lf_ft"] = -(P["lf_u"] + P["lf_l"]) * 0.85
	P["lb_ft"] = -(P["lb_u"] + P["lb_l"]) * 0.85 - limp * 0.5


func _ground(P: Dictionary) -> void:
	# lower the hips so the lowest foot touches the ground
	var l1: float = _dims["leg_up"]
	var l2: float = _dims["leg_lo"]
	var reach := 0.0
	for s in ["lf", "lb"]:
		var a1: float = P[s + "_u"]
		var a2: float = a1 + P[s + "_l"]
		reach = maxf(reach, l1 * cos(a1) + l2 * cos(a2))
	P["hip_y"] = float(P["hip_y"]) + reach - (l1 + l2)


func _curve_strike(u: float) -> float:
	# wind-up (negative), strike to 1, recover to 0
	if u < 0.3:
		return -0.25 * (u / 0.3)
	if u < 0.5:
		return lerpf(-0.25, 1.0, (u - 0.3) / 0.2)
	return lerpf(1.0, 0.0, (u - 0.5) / 0.5)


func _compute_pose(a: String, t: float) -> Dictionary:
	var P := {}
	for k in JOINTS:
		P[k] = 0.0
	var post: String = tweaks.get("posture", "stand")
	if a == "crawl" and post == "stand":
		post = "crawl"
	if post == "crawl" or post == "dog":
		_pose_horizontal(P, a, t, post)
		return P
	var lean: float = tweaks.get("hunch", 0.0)
	var g: float = tweaks.get("gait", 1.0)
	var limp: float = tweaks.get("limp", 0.0)
	var zombie_arms: bool = tweaks.get("arms_out", false)
	var armed := _wclass != "none"
	var u := 0.0
	if ONESHOT.has(a):
		u = clampf(t / ONESHOT[a], 0.0, 1.0)
	var gun := _wclass == "pistol" or _wclass == "long"
	var aiming := a == "aim" and gun
	var arms_mode := "free"
	var swing := 0.0
	var ext := 0.0
	P["torso"] = -lean
	P["head"] = lean * 0.7
	var guard_f := Vector2(0.26, 0.0)
	var guard_b := Vector2(0.2, -0.08)
	match a:
		"idle", "aim":
			var br := sin(t * 2.2)
			P["torso"] += 0.012 * br
			_legs(P, 0.0, 0.0, 0.0)
			P["lf_u"] = 0.12
			P["lb_u"] = -0.14
			P["lf_l"] = -0.1
			P["lb_l"] = -0.06
			P["lf_ft"] = -(P["lf_u"] + P["lf_l"])
			P["lb_ft"] = -(P["lb_u"] + P["lb_l"])
			if zombie_arms:
				P["head"] += 0.1 * sin(t * 1.3)
			swing = 0.03 * br
		"walk":
			var p := t * TAU * 1.05 * g
			_legs(P, p, 0.5, 0.75, 0.0, limp)
			P["hip_y"] = 0.0
			P["torso"] += 0.03 * sin(p * 2.0) + 0.04
			P["head"] -= 0.03
			swing = 0.5
			arms_mode = "swing"
			ext = p
		"run":
			var p2 := t * TAU * 1.55 * g
			_legs(P, p2, 0.95, 1.5, 0.0, limp)
			P["torso"] += -0.28 + 0.03 * sin(p2 * 2.0)
			P["head"] += 0.2
			P["hip_y"] = 0.0
			arms_mode = "run"
			ext = p2
		"punch":
			_legs(P, 0.0, 0.0, 0.0)
			P["lf_u"] = 0.25
			P["lb_u"] = -0.3
			P["lb_l"] = -0.25
			P["lf_ft"] = -P["lf_u"]
			P["lb_ft"] = -(P["lb_u"] + P["lb_l"])
			ext = _curve_strike(u)
			P["torso"] += -0.22 * ext
			P["hip_x"] = 0.06 * maxf(ext, 0.0)
		"shove":
			_legs(P, 0.0, 0.0, 0.0)
			P["lf_u"] = 0.3
			P["lb_u"] = -0.35
			P["lb_l"] = -0.2
			P["lf_ft"] = -P["lf_u"]
			P["lb_ft"] = -(P["lb_u"] + P["lb_l"])
			ext = _curve_strike(u)
			P["torso"] += -0.3 * ext
			P["hip_x"] = 0.08 * maxf(ext, 0.0)
		"hurt":
			var bump := sin(u * PI)
			_legs(P, 0.0, 0.0, 0.0)
			P["lf_u"] = 0.2
			P["lb_u"] = -0.25
			P["lb_l"] = -0.15
			P["lf_ft"] = -P["lf_u"]
			P["lb_ft"] = -(P["lb_u"] + P["lb_l"])
			P["torso"] += 0.4 * bump
			P["head"] += 0.45 * bump
			P["hip_x"] = -0.06 * bump
			ext = bump
		"die", "rise":
			_pose_fall(P, a, t)
			return P
	# ---- arms
	var sh_rel_torso: float = P["torso"] + P["hip_rot"]
	if _wclass == "shield":
		P["wrot"] = 0.0 - sh_rel_torso
		var gf := Vector2(0.38, 0.0)
		if a == "punch" or a == "shove":
			gf.x += 0.12 * maxf(ext, 0.0)
		_arm_ik(P, "f", gf)
		_arm_free(P, "b", a, ext, swing, zombie_arms, t, guard_b)
	elif gun:
		var pitch := aim_pitch if aiming else (-0.55 if _wclass == "pistol" else -0.4)
		if a == "run" or a == "walk":
			pitch += 0.12 * sin(ext * 2.0)
		if a == "punch" or a == "shove":
			pitch = 0.3
		var off := Vector2(0.1 * maxf(ext, 0.0), 0.0) if (a == "punch" or a == "shove") else Vector2.ZERO
		P["wrot"] = pitch - sh_rel_torso
		var gr: Vector2 = Vector2(0.44, -0.03) if _wclass == "long" else Vector2(0.45, -0.02)
		var gf2: Vector2 = Vector2(0.62, -0.01) if _wclass == "long" else Vector2(0.43, -0.05)
		if _wclass == "long":
			gf2 = Vector2(0.58, -0.02)
		_arm_ik(P, "f", gr.rotated(P["wrot"]) + off)
		_arm_ik(P, "b", gf2.rotated(P["wrot"]) + off)
	elif _wclass == "melee":
		var wrot_w := 0.45 + 0.06 * sin(t * 2.2)
		if a == "run" or a == "walk":
			wrot_w = 0.35 + 0.12 * sin(ext * 2.0)
		if a == "punch":
			# overhead swing: back over the shoulder, then down through the target
			var sw := clampf(u / 0.7, 0.0, 1.0)
			wrot_w = lerpf(2.5, -0.9, sw * sw * (3.0 - 2.0 * sw)) if u < 0.7 else lerpf(-0.9, 0.45, (u - 0.7) / 0.3)
			if u < 0.18:
				wrot_w = lerpf(0.45, 2.5, u / 0.18)
		P["wrot"] = wrot_w - sh_rel_torso
		_arm_ik(P, "f", Vector2(0.42, 0.0).rotated(P["wrot"]))
		_arm_free(P, "b", a, ext, swing, zombie_arms, t, guard_b)
		if a == "punch":
			P["torso"] += -0.25 * clampf(sin(u * PI), 0.0, 1.0)
	else:
		_arm_free(P, "f", a, ext, swing, zombie_arms, t, guard_f)
		_arm_free(P, "b", a, ext, swing, zombie_arms, t, guard_b, true)
	if a == "hurt" and not gun:
		P["af_u"] = -0.9 * ext + P["af_u"] * (1.0 - ext)
		P["ab_u"] = -0.5 * ext + P["ab_u"] * (1.0 - ext)
	_ground(P)
	P["hip_y"] += 0.012 * sin(t * 2.2) * (1.0 if a == "idle" else 0.0)
	if a == "walk" or a == "run":
		var ph := t * TAU * (1.05 if a == "walk" else 1.55) * g
		P["hip_y"] += -0.035 * absf(sin(ph)) * (1.0 if a == "walk" else 1.6)
		P["hip_y"] = float(P["hip_y"]) + 0.02
	return P


## FK/IK arms for unarmed and zombie poses. `ext` is the strike/shove extension or gait phase.
func _arm_free(P: Dictionary, side: String, a: String, ext: float, swing: float, zombie_arms: bool, t: float, guard: Vector2, is_back: bool = false) -> void:
	var sgn := 1.0 if side == "f" else -1.0
	if zombie_arms:
		var base := 1.4 + 0.1 * sgn
		var wob := 0.12 * sin(t * 3.1 + (0.0 if side == "f" else 1.7))
		if a == "run":
			base = 1.1
		if a == "punch" or a == "shove":
			base += 0.25 * maxf(ext, 0.0)
		P["a%s_u" % side] = base + wob
		P["a%s_l" % side] = 0.15 + 0.1 * sin(t * 2.3)
		return
	match a:
		"walk":
			P["a%s_u" % side] = -sgn * swing * sin(ext) * 0.9 + 0.05
			P["a%s_l" % side] = 0.25 + 0.2 * (1.0 + sin(ext * sgn + 1.0)) * 0.5
		"run":
			P["a%s_u" % side] = -sgn * 1.0 * sin(ext)
			P["a%s_l" % side] = 1.35
		"idle", "aim":
			_arm_ik(P, side, guard + Vector2(0.0, 0.01 * sin(t * 2.2)))
		"punch":
			if is_back:
				_arm_ik(P, side, guard + Vector2(-0.03 * ext, 0.02))
			else:
				_arm_ik(P, side, guard.lerp(Vector2(0.6, 0.02), ext))
		"shove":
			_arm_ik(P, side, guard.lerp(Vector2(0.52, 0.0 if side == "f" else -0.05), ext))
		"hurt":
			_arm_ik(P, side, guard)
		_:
			_arm_ik(P, side, guard)


func _pose_fall(P: Dictionary, a: String, t: float) -> void:
	var u := clampf(t / ONESHOT["die"], 0.0, 1.0)
	if a == "rise":
		u = 1.0 - clampf(t / ONESHOT["rise"], 0.0, 1.0)
		# jerky lurch on the way up
		u = clampf(u + 0.06 * sin(t * 14.0) * u, 0.0, 1.0)
	var f := u * u
	var settle := 1.0 + 0.05 * sin(clampf(u - 0.9, 0.0, 0.1) * 60.0) * (1.0 if a == "die" else 0.0)
	P["hip_rot"] = 1.47 * f * settle
	P["hip_y"] = -(float(_dims["hip_y"]) - 0.14) * f
	P["hip_x"] = -0.1 * f
	P["head"] = 0.25 * f
	P["torso"] = 0.0
	P["af_u"] = -0.8 * f
	P["af_l"] = 0.4 * f
	P["ab_u"] = -1.3 * f
	P["ab_l"] = 0.3 * f
	P["lf_u"] = 0.5 * f
	P["lf_l"] = -0.5 * f
	P["lb_u"] = 0.2 * f
	P["lb_l"] = -0.3 * f
	P["lf_ft"] = -0.2 * f
	P["lb_ft"] = -0.2 * f
	if _wclass != "none":
		P["wrot"] = -0.6 * f
	var post: String = tweaks.get("posture", "stand")
	if post == "crawl":
		P["hip_rot"] = -1.45
		P["hip_y"] = -(float(_dims["hip_y"]) - 0.1) * f + 0.0
		P["hip_x"] = 0.0
	elif post == "dog":
		P["hip_rot"] = -1.57 + 1.2 * f
		P["hip_y"] = -0.2 * f
		P["lf_u"] = 1.4 * f
		P["lb_u"] = 1.1 * f
		P["af_u"] = 1.5 * f
		P["ab_u"] = 1.3 * f


func _pose_horizontal(P: Dictionary, a: String, t: float, post: String) -> void:
	var g: float = tweaks.get("gait", 1.0)
	var moving := a in ["walk", "run", "crawl", "punch", "shove"]
	var spd := (1.6 if a == "run" else 1.0) * g
	var p := t * TAU * (0.9 if post == "crawl" else 1.5) * spd
	if post == "dog" and a == "run":
		p = t * TAU * 2.4 * g
	if a == "die" or a == "rise":
		_pose_fall(P, a, t)
		return
	var amp := 1.0 if moving else 0.0
	var base_rot := -1.45 if post == "crawl" else -1.5708
	P["hip_rot"] = base_rot
	var lim := -base_rot
	if post == "crawl":
		P["head"] = 1.15 + 0.08 * sin(t * 2.0)
		P["hip_y"] = -(float(_dims["hip_y"]) - 0.2)
		var reach_f := 1.2 + 0.7 * sin(p)
		var reach_b := 1.2 + 0.7 * sin(p + PI)
		P["af_u"] = reach_f + lim
		P["ab_u"] = reach_b + lim
		P["af_l"] = 0.4 + 0.4 * cos(p)
		P["ab_l"] = 0.4 + 0.4 * cos(p + PI)
		P["lf_u"] = -1.3 + lim + 0.3 * sin(p + 2.0) * amp
		P["lb_u"] = -1.45 + lim + 0.3 * sin(p + 3.1) * amp
		P["lf_l"] = 0.2
		P["lb_l"] = 0.1
		P["lf_ft"] = 0.3
		P["lb_ft"] = 0.3
		if a == "punch" or a == "shove":
			var uu := clampf(t / ONESHOT[a], 0.0, 1.0)
			P["af_u"] = 2.4 * sin(uu * PI) + 1.2 + lim * 0.0 + lim
			P["head"] += 0.3 * sin(uu * PI)
		if a == "hurt":
			P["hip_x"] = -0.05 * sin(clampf(t / ONESHOT["hurt"], 0.0, 1.0) * PI)
	else:
		# dog: head faces forward again, legs reach to the ground and gallop
		P["head"] = lim + 0.1 * sin(p * 2.0) * amp - 0.1
		P["hip_y"] = 0.0
		var sw := 0.7 * amp
		P["af_u"] = lim + sw * sin(p)
		P["ab_u"] = lim + sw * sin(p + 0.6)
		P["lf_u"] = lim + sw * sin(p + PI)
		P["lb_u"] = lim + sw * sin(p + PI + 0.6)
		P["af_l"] = -0.1 + 0.5 * amp * maxf(0.0, cos(p))
		P["ab_l"] = -0.1 + 0.5 * amp * maxf(0.0, cos(p + 0.6))
		P["lf_l"] = -0.3 - 0.8 * amp * maxf(0.0, cos(p + PI))
		P["lb_l"] = -0.3 - 0.8 * amp * maxf(0.0, cos(p + PI + 0.6))
		P["lf_ft"] = -(P["lf_u"] - lim + P["lf_l"]) * 0.7
		P["lb_ft"] = -(P["lb_u"] - lim + P["lb_l"]) * 0.7
		P["hip_y"] += 0.03 * sin(p * 2.0) * amp
		P["hip_rot"] += 0.06 * sin(p) * amp
		if a == "punch" or a == "shove":
			var u2 := clampf(t / ONESHOT[a], 0.0, 1.0)
			P["hip_rot"] += 0.5 * sin(u2 * PI)
			P["hip_x"] = 0.15 * sin(u2 * PI)
		if a == "hurt":
			P["hip_rot"] += -0.3 * sin(clampf(t / ONESHOT["hurt"], 0.0, 1.0) * PI)
