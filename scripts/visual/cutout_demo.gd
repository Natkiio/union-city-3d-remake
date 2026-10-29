extends Node3D
## Demo of the cutout kit: stages for animations, weapon poses, looks and zombies on a
## street with a Cork backdrop. Left/Right arrows (or 1-4) switch stage. With
## `frozen = true` every rig is advanced to a fixed time and stops (screenshots).

const STAGES := ["anims", "weapons", "looks", "zombies1", "zombies2", "closeup", "closeup_zombies"]
const HERO := {"sex": "male", "skinColour": "White", "hair": "short2", "hairColour": "Dark Brown", "facialHair": "shadow",
	"clothesTop": "male_hoodyBlack", "clothesBottom": "male_jeansBlue", "clothesShoe": "shoeBrown", "backpack": true, "weapon": "none"}

var frozen: bool = false
var stage: int = 0
var cam: Camera3D
var stage_nodes: Array = []
var stage_centres: Array = []
var stage_spans: Array = []
var stage_rigs: Array = []
var backdrop: Node3D


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.05, 0.07))
	backdrop = Backdrop.build(Backdrop.preset("cork_dusk"))
	add_child(backdrop)
	_ground()
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.far = 400.0
	add_child(cam)
	for i in STAGES.size():
		var n := Node3D.new()
		n.name = "Stage_" + STAGES[i]
		add_child(n)
		stage_nodes.append(n)
		stage_rigs.append([])
	_stage_anims(stage_nodes[0], 0)
	_stage_weapons(stage_nodes[1], 1)
	_stage_looks(stage_nodes[2], 2)
	_stage_zombies(stage_nodes[3], 3, 0, 11)
	_stage_zombies(stage_nodes[4], 4, 11, 22)
	_stage_closeup(stage_nodes[5], 5)
	_stage_closeup_z(stage_nodes[6], 6)
	show_stage(0)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if e.keycode == KEY_RIGHT:
			show_stage((stage + 1) % STAGES.size())
		elif e.keycode == KEY_LEFT:
			show_stage((stage + STAGES.size() - 1) % STAGES.size())
		elif e.keycode >= KEY_1 and e.keycode <= KEY_7:
			show_stage(e.keycode - KEY_1)


func show_stage(i: int) -> void:
	stage = i
	for k in stage_nodes.size():
		stage_nodes[k].visible = (k == i)
	var c: float = stage_centres[i]
	var span: float = stage_spans[i]
	var depth: float = stage_depth[i]
	var tan_v := tan(deg_to_rad(cam.fov * 0.5))
	var dist := maxf((span * 0.5 + 0.6) / (tan_v * 1.7), 4.0)
	# level camera (vertical lines stay vertical); the frustum is shifted down to frame the ground
	var cam_y := 1.5 + depth * 1.5
	var look_y := 2.0 + depth * 0.5
	cam.position = Vector3(c, cam_y, dist)
	cam.rotation = Vector3.ZERO
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	var near := 0.5
	cam.set_frustum(2.0 * near * tan_v, Vector2(0, (look_y - cam_y) / dist * near), near, 400.0)


var stage_depth: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


func _ground() -> void:
	var g := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(600, 40)
	g.mesh = q
	g.rotation.x = -PI / 2
	g.position = Vector3(0, 0.0, -10)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.17, 0.17, 0.2)
	g.material_override = m
	add_child(g)
	var kerb := MeshInstance3D.new()
	var q2 := QuadMesh.new()
	q2.size = Vector2(400, 4.0)
	kerb.mesh = q2
	kerb.rotation.x = -PI / 2
	kerb.position = Vector3(0, 0.01, -4.5)
	var m2 := m.duplicate() as StandardMaterial3D
	m2.albedo_color = Color(0.3, 0.3, 0.32)
	kerb.material_override = m2
	add_child(kerb)


func _place(stage_i: int, parent: Node3D, look: Dictionary, anim: String, x: float, z: float, label: String, t: float, tweaks_ref: String = "", facing: float = 1.0, pitch: float = 0.0) -> CutoutRig:
	var rig := CutoutRig.new()
	parent.add_child(rig)
	rig.apply_look(look)
	if tweaks_ref != "":
		ZombieLooks.apply(rig, tweaks_ref, int(x * 10.0))
	rig.set_facing(facing)
	rig.set_aim(pitch)
	rig.position = Vector3(x, 0, z)
	rig.play(anim)
	if frozen:
		rig.set_process(false)
		rig.advance(t)
	stage_rigs[stage_i].append(rig)
	var lab := Label3D.new()
	lab.text = label
	lab.font_size = 40
	lab.pixel_size = 0.0055
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.modulate = Color(0.9, 0.88, 0.8)
	lab.outline_size = 10
	lab.position = Vector3(x, -0.18, z + 0.3)
	parent.add_child(lab)
	return rig


func _stage_anims(parent: Node3D, si: int) -> void:
	var anims := ["idle", "walk", "run", "punch", "shove", "aim", "hurt", "die", "crawl", "rise"]
	var times := [0.4, 0.12, 0.1, 0.18, 0.2, 0.3, 0.14, 0.7, 0.3, 0.6]
	for i in anims.size():
		_place(si, parent, HERO, anims[i], (i % 5) * 2.4 + (0.0 if i < 5 else 1.2), -(i / 5) * 3.0, anims[i], times[i])
	stage_centres.append(4 * 2.4 * 0.5 + 0.5)
	stage_spans.append(5 * 2.4 + 1.0)
	stage_depth[si] = 3.0


func _stage_weapons(parent: Node3D, si: int) -> void:
	var defs := [["idle", "glock", 0.0, "glock ready"], ["aim", "glock", 0.25, "glock aim"], ["aim", "M4A1", 0.0, "M4A1 aim"],
		["walk", "M4A1", 0.0, "M4A1 walk"], ["aim", "hunter_scope", 0.5, "hunter aim up"], ["idle", "bat", 0.0, "bat idle"],
		["punch", "bat", 0.0, "bat swing"], ["punch", "katana", 0.0, "katana swing"], ["idle", "kitchenKnife", 0.0, "knife"],
		["punch", "fireAxe", 0.0, "axe swing"], ["run", "M9", 0.0, "pistol run"], ["shove", "M4A1", 0.0, "rifle shove"]]
	var times := [0.3, 0.3, 0.3, 0.12, 0.3, 0.3, 0.2, 0.3, 0.3, 0.24, 0.1, 0.2]
	for i in defs.size():
		var l := HERO.duplicate()
		l["weapon"] = defs[i][1]
		l["hair"] = "ponytail1" if i % 3 == 0 else "cropped"
		l["sex"] = "female" if i % 3 == 0 else "male"
		_place(si, parent, l, defs[i][0], (i % 6) * 2.3 + (0.0 if i < 6 else 1.15), -(i / 6) * 3.0, defs[i][3], times[i], "", 1.0, defs[i][2])
	stage_centres.append(5 * 2.3 * 0.5 + 0.5)
	stage_spans.append(6 * 2.3 + 1.0)
	stage_depth[si] = 3.0


func _stage_looks(parent: Node3D, si: int) -> void:
	var f := FileAccess.open("res://data/original/npc.json", FileAccess.READ)
	var npcs: Dictionary = JSON.parse_string(f.get_as_text())
	var names := ["Williams", "Partner"]
	var per_row := 8
	var recs: Array = []
	for k in npcs:
		recs.append(npcs[k])
	var pick := [3, 5, 8, 12, 15, 19, 22, 27, 33, 38, 41, 44, 48, 52, 56]
	var idx := 0
	for r in 2:
		for c in per_row:
			var look: Dictionary
			if r == 0 and c < 5 and false:
				look = {}
			elif idx < pick.size():
				look = Look.from_npc(recs[pick[idx] % recs.size()])
			else:
				look = Look.random(idx * 31 + 5)
			var nm: String = str(recs[pick[idx] % recs.size()].get("name", "random")) if idx < pick.size() else "crowd %d" % idx
			_place(si, parent, look, "idle" if (idx % 3) else "walk", c * 1.8 + (0.9 if r == 1 else 0.0), -r * 3.0, nm, 0.2 + idx * 0.13, "", 1.0 if idx % 4 != 3 else -1.0)
			idx += 1
	stage_centres.append(per_row * 1.8 * 0.5 + 0.2)
	stage_spans.append(per_row * 1.8 + 1.0)
	stage_depth[si] = 3.0


func _stage_zombies(parent: Node3D, si: int, from: int, to: int) -> void:
	var refs := ZombieLooks.refs()
	var per_row := 6
	for i in range(from, to):
		var k := i - from
		var r := k / per_row
		var c := k % per_row
		var ref: String = refs[i]
		_place(si, parent, {}, ZombieLooks.move_anim(ref), c * 2.4 + (1.2 if r == 1 else 0.0), -r * 3.0, ref.trim_prefix("zombie"), 0.15 + i * 0.11, ref)
	stage_centres.append(per_row * 2.4 * 0.5 - 0.1)
	stage_spans.append(per_row * 2.4 + 1.0)
	stage_depth[si] = 3.0


func _stage_closeup_z(parent: Node3D, si: int) -> void:
	var picks := [["zombieDog", "run"], ["zombieCrawl", "crawl"], ["zombieRiot", "walk"], ["zombieRiotShield", "walk"],
		["zombieArmy", "walk"], ["zombiePolice", "walk"]]
	for i in picks.size():
		_place(si, parent, {}, picks[i][1], i * 2.4, 0.0, str(picks[i][0]).trim_prefix("zombie"), 0.25 + i * 0.07, picks[i][0])
	stage_centres.append(2.5 * 2.4 + 0.1)
	stage_spans.append(picks.size() * 2.4 + 0.4)
	stage_depth[si] = 0.0


func _stage_closeup(parent: Node3D, si: int) -> void:
	var woman := {"sex": "female", "skinColour": "Tanned", "hair": "long1", "hairColour": "Red", "clothesTop": "female_longSleeveGreen",
		"clothesBottom": "female_jeansBlack", "clothesShoe": "shoeWhite", "faceAccessory": "glasses", "weapon": "M9"}
	var guard := {"sex": "male", "skinColour": "Black", "hair": "cropped", "hairColour": "Black", "facialHair": "fullBeard",
		"clothesTop": "male_unionSecTop", "clothesBottom": "male_policeBottom", "clothesShoe": "shoeBlack", "headAccessory": "capBlue",
		"torsoAccessory": "kevlarVest", "weapon": "policeBaton"}
	_place(si, parent, HERO, "idle", 0.0, 0.0, "hero", 0.5)
	_place(si, parent, woman, "aim", 2.2, 0.0, "woman, pistol", 0.5, "", 1.0, 0.1)
	_place(si, parent, guard, "idle", 4.4, 0.0, "security", 0.5)
	_place(si, parent, {}, "walk", 6.6, 0.0, "zombie slow", 0.4, "zombieSlow")
	_place(si, parent, {}, "walk", 8.8, 0.0, "zombie fat", 0.4, "zombieFat")
	stage_centres.append(4.4)
	stage_spans.append(10.0)
