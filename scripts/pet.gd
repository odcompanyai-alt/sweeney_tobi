extends Node2D
## Tobi — a tiny desktop pet.
## One node draws the whole character from part sprites (assets/parts),
## runs a small behaviour state machine and moves its own borderless,
## transparent, always-on-top window around the screen.

const PartData := preload("res://scripts/part_data.gd")

const BASE_SIZE := Vector2(240, 250)   # window size at scale 1 (units)
const FEET := Vector2(120, 244)        # where the feet touch the ground inside the window
const WALK_SPEED := 34.0               # units/s
const GRAVITY := 2600.0                # units/s^2
const SETTINGS_PATH := "user://settings.cfg"
const SIZE_LEVELS := [0.75, 1.0, 1.4, 1.9]
const SIZE_NAMES := ["작게", "보통", "크게", "아주 크게"]
const PETTABLE := ["idle", "walk", "look", "wave", "hop", "petted"]

const COL_OUTLINE := Color("#4a3228")
const COL_EYE := Color("#1a1618")
const COL_LINE := Color("#e8743b")
const COL_NOSE := Color("#cd845c")
const COL_MOUTH := Color("#962e34")
const COL_TONGUE := Color("#ff8c8c")
const COL_BLUSH := Color("#ff8c99")
const COL_HAIR_DARK := Color("#c88d56")
const COL_HEART := Color("#ff698c")
const COL_SPARK := Color("#ffd65a")
const COL_SWEAT := Color("#8cc8ff")
const COL_DUST := Color("#e8ddd0")
const COL_ANGER := Color("#e8434f")
const COL_TEXT := Color("#5a6f9a")
const NOTE_COLORS := [Color("#ff8fb1"), Color("#7fb6ff"), Color("#9ad48a"), Color("#ffb85c")]

# face name -> [eyes, mouth, brows]
const FACES := {
	"normal": ["open", "smile", "soft"],
	"happy": ["happy", "open_smile", "raised"],
	"hehe": ["happy", "smile", "soft"],
	"surprised": ["big", "o", "raised"],
	"shout": ["open", "talk", "angry"],
	"worried": ["teary", "wavy", "worried"],
	"dizzy": ["dizzy", "wavy", "worried"],
	"effort": ["squint", "flat", "angry"],
	"shy": ["squint", "wavy", "worried"],
	"sleep": ["closed", "o_small", "soft"],
	"yawn": ["closed", "talk", "raised"],
	"pout": ["open", "pout", "angry"],
}

enum { M_BOX, M_WIG, M_WAVE, M_HOP, M_SLEEP, M_STILL, M_QUIT, M_SIZE0 = 100 }


class Pose:
	var root := Vector2.ZERO        # whole-character offset (anchor space)
	var root_rot := 0.0
	var rot_pivot := Vector2.ZERO
	var squash := Vector2.ONE       # scale around the feet
	var body_off := Vector2.ZERO
	var body_rot := 0.0
	var head_off := Vector2.ZERO
	var head_rot := 0.0
	var arm_l := 12.0               # degrees, 0 = hanging down
	var arm_r := -12.0
	var arms_front := false
	var foot_l := Vector2.ZERO
	var foot_r := Vector2.ZERO
	var scarf_rot := 0.0
	var face := "normal"
	var look := Vector2.ZERO
	var blush := 0.3
	var mouth_open := 0.0
	var nose_bubble := 0.0
	var dizzy := false


class Particle:
	var kind := ""
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var grav := 0.0
	var life := 1.0
	var max_life := 1.0
	var size := 1.0
	var rot := 0.0
	var spin := 0.0
	var text := ""
	var color := Color.WHITE


var tex := {}
var font: SystemFont
var bubble_style := StyleBoxFlat.new()
var menu: PopupMenu

var size_level := 1
var auto_scale := 1.0
var pet_scale := 1.0
var stay_still := false
var view_xf := Transform2D.IDENTITY

var pos := Vector2.ZERO        # anchor (feet on the ground) in screen pixels
var vel := Vector2.ZERO        # px/s while falling
var usable := Rect2i()
var screen_timer := 0.0

var state := ""
var st := 0.0
var state_dur := 0.0
var fired := {}
var last_action := ""
var pose := Pose.new()
var facing := 1.0
var side := 1.0
var char_off := Vector2.ZERO   # character offset from the anchor (used on the box)

var wig_attached := true
var wig_off := Vector2.ZERO
var wig_rot := 0.0
var wig_c := Vector2.ZERO      # free wig centre (character space)
var wig_vel := Vector2.ZERO
var wig_spin := 0.0
var wig_from := Vector2.ZERO

var box_visible := false
var box_scale := 0.0
var box_sq := 1.0
var box_closing := false

var bubble_text := ""
var bubble_t := 0.0
var bubble_left := 0.0
var bubble_rect := Rect2()

var particles: Array[Particle] = []
var blink_timer := 2.0
var blinking := 0.0
var t_total := 0.0

var pressing := false
var dragging := false
var press_screen := Vector2.ZERO
var grab := Vector2.ZERO
var swing := 0.0
var swing_vel := 0.0
var last_mouse := Vector2.ZERO
var last_mouse_vel := Vector2.ZERO
var mouse_hist: Array = []
var poke_times: Array[float] = []
var rub := 0.0
var last_rub := -10.0
var max_fall_speed := 0.0
var greet_after_land := true

var last_region := Rect2i()
var region_full := false


# ======================================================================
# Setup
# ======================================================================

func _ready() -> void:
	randomize()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for part_name in PartData.PIVOTS:
		var src: Texture2D = load("res://assets/parts/%s.png" % part_name)
		var img := src.get_image()
		if img.is_compressed():
			img.decompress()
		img.generate_mipmaps()
		tex[part_name] = ImageTexture.create_from_image(img)

	font = SystemFont.new()
	font.font_names = PackedStringArray(["Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", "NanumGothic", "sans-serif"])
	font.font_weight = 800
	bubble_style.bg_color = Color.WHITE
	bubble_style.border_color = COL_OUTLINE
	bubble_style.anti_aliasing = true

	_load_settings()
	_build_menu()
	_refresh_screen()
	_apply_scale()
	last_mouse = Vector2(DisplayServer.mouse_get_position())

	# drop in from the top of the screen
	pos = Vector2(
		randf_range(usable.position.x + 120.0, usable.end.x - 120.0),
		usable.position.y + 160.0 * pet_scale)
	vel = Vector2.ZERO
	_enter("fall")


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		size_level = clampi(int(cfg.get_value("pet", "size", 1)), 0, SIZE_LEVELS.size() - 1)
		stay_still = bool(cfg.get_value("pet", "stay_still", false))
	auto_scale = DisplayServer.screen_get_scale()
	if OS.get_name() == "Windows":
		auto_scale = clampf(DisplayServer.screen_get_dpi() / 96.0, 1.0, 3.0)
	pet_scale = SIZE_LEVELS[size_level] * auto_scale


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("pet", "size", size_level)
	cfg.set_value("pet", "stay_still", stay_still)
	cfg.save(SETTINGS_PATH)


func _build_menu() -> void:
	menu = PopupMenu.new()
	menu.add_item("박스 위에서 외치기", M_BOX)
	menu.add_item("가발 벗기", M_WIG)
	menu.add_item("손 흔들기", M_WAVE)
	menu.add_item("깡총 뛰기", M_HOP)
	menu.add_item("낮잠 자기", M_SLEEP)
	menu.add_separator()
	for i in SIZE_LEVELS.size():
		menu.add_radio_check_item("크기: " + SIZE_NAMES[i], M_SIZE0 + i)
	menu.add_check_item("제자리에 있기 (걷지 않기)", M_STILL)
	menu.add_separator()
	menu.add_item("종료", M_QUIT)
	menu.id_pressed.connect(_on_menu)
	add_child(menu)


func _sync_menu() -> void:
	for i in SIZE_LEVELS.size():
		menu.set_item_checked(menu.get_item_index(M_SIZE0 + i), i == size_level)
	menu.set_item_checked(menu.get_item_index(M_STILL), stay_still)


func _open_menu() -> void:
	_sync_menu()
	menu.reset_size()
	menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


func _on_menu(id: int) -> void:
	match id:
		M_BOX: _start_action("box")
		M_WIG: _start_action("wig")
		M_WAVE: _start_action("wave")
		M_HOP: _start_action("hop")
		M_SLEEP: _start_action("sleep")
		M_STILL:
			stay_still = not stay_still
			_save_settings()
		M_QUIT:
			get_tree().quit()
		_:
			if id >= M_SIZE0:
				size_level = id - M_SIZE0
				pet_scale = SIZE_LEVELS[size_level] * auto_scale
				_apply_scale()
				_save_settings()


func _start_action(action: String) -> void:
	if state in ["drag", "fall"]:
		return
	_cleanup_specials()
	_enter(action)


func _apply_scale() -> void:
	get_window().size = Vector2i((BASE_SIZE * pet_scale).round())
	view_xf = Transform2D(0.0, Vector2(pet_scale, pet_scale), 0.0, FEET * pet_scale)
	bubble_style.set_border_width_all(maxi(1, roundi(2.0 * pet_scale)))
	bubble_style.set_corner_radius_all(roundi(10.0 * pet_scale))
	last_region = Rect2i()
	region_full = false


func _refresh_screen() -> void:
	usable = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())


# ======================================================================
# Main loop
# ======================================================================

func _process(delta: float) -> void:
	var d := minf(delta, 0.05)
	t_total += d
	screen_timer -= d
	if screen_timer <= 0.0:
		screen_timer = 0.5
		_refresh_screen()

	_poll_mouse(d)
	pose = Pose.new()
	st += d
	match state:
		"idle": _st_idle(d)
		"walk": _st_walk(d)
		"look": _st_look(d)
		"wave": _st_wave(d)
		"hop": _st_hop(d)
		"box": _st_box(d)
		"wig": _st_wig(d)
		"sleep": _st_sleep(d)
		"wake": _st_wake(d)
		"poke": _st_poke(d)
		"pout": _st_pout(d)
		"petted": _st_petted(d)
		"drag": _st_drag(d)
		"fall": _st_fall(d)
		"land": _st_land(d)
		"dizzy": _st_dizzy(d)

	_update_blink(d)
	_update_particles(d)
	_update_box(d)
	if bubble_left > 0.0:
		bubble_left -= d
		bubble_t += d
	rub = maxf(0.0, rub - 300.0 * d)

	_apply_window()
	_update_passthrough()
	queue_redraw()


func _enter(s: String) -> void:
	state = s
	st = 0.0
	fired.clear()
	match s:
		"idle":
			state_dur = randf_range(2.5, 6.0)
		"walk":
			state_dur = randf_range(3.0, 7.0)
			if randf() < 0.5:
				facing = -facing
		"sleep":
			state_dur = randf_range(10.0, 18.0)
		"petted":
			rub = 0.0
		"wig":
			wig_attached = true
			wig_rot = 0.0
			wig_off = Vector2.ZERO
		"box":
			var s_px := pet_scale
			side = facing
			var probe := pos.x + 70.0 * side * s_px
			if probe > usable.end.x - 50.0 * s_px or probe < usable.position.x + 50.0 * s_px:
				side = -side
			facing = side
			pos.x += 42.0 * side * s_px
			char_off = Vector2(-42.0 * side, 0.0)
			box_visible = true
			box_closing = false
			box_scale = 0.0
			box_sq = 1.0


func _once(key: String) -> bool:
	if fired.has(key):
		return false
	fired[key] = true
	return true


func _pick_next() -> void:
	var opts := {
		"walk": 0.0 if stay_still else 36.0,
		"look": 10.0,
		"wave": 8.0,
		"box": 12.0,
		"wig": 10.0,
		"hop": 9.0,
		"sleep": 6.0,
	}
	if last_action in opts and last_action != "walk":
		opts[last_action] = 0.0
	var total := 0.0
	for k in opts:
		total += float(opts[k])
	var r := randf() * total
	for k in opts:
		r -= float(opts[k])
		if r <= 0.0:
			last_action = k
			_enter(k)
			return
	_enter("idle")


func _cleanup_specials() -> void:
	if char_off != Vector2.ZERO:
		pos.x += char_off.x * pet_scale
		char_off = Vector2.ZERO
	if box_visible:
		box_closing = true
	if not wig_attached:
		_spawn_spark(_anchor_of(Vector2(0, -130)))
	wig_attached = true
	wig_rot = 0.0
	wig_off = Vector2.ZERO
	bubble_left = 0.0


func _check_ground() -> bool:
	if absf(pos.y - float(usable.end.y)) > 2.0:
		vel = Vector2.ZERO
		max_fall_speed = 0.0
		greet_after_land = false
		_enter("fall")
		return true
	return false


# ======================================================================
# Behaviours
# ======================================================================

func _breathe() -> void:
	var b := sin(st * 2.6)
	pose.squash = Vector2(1.0 - b * 0.012, 1.0 + b * 0.018)
	pose.arm_l = 12.0 + b * 3.0
	pose.arm_r = -pose.arm_l
	pose.scarf_rot = sin(st * 1.7) * 0.06


func _st_idle(_d: float) -> void:
	_breathe()
	pose.head_rot = sin(st * 1.1) * 0.035
	if _check_ground():
		return
	if st > state_dur:
		_pick_next()


func _st_walk(d: float) -> void:
	var ph := st * 8.0
	var s := sin(ph)
	pose.root.y = -absf(s) * 3.0
	pose.root_rot = s * 0.06
	pose.foot_l = Vector2(2.0 * s, -maxf(0.0, s) * 5.0)
	pose.foot_r = Vector2(-2.0 * s, -maxf(0.0, -s) * 5.0)
	pose.arm_l = 12.0 + s * 22.0
	pose.arm_r = -12.0 + s * 22.0
	pose.head_rot = -s * 0.04
	pose.scarf_rot = -s * 0.15

	var px := pet_scale
	pos.x += facing * WALK_SPEED * px * d
	var left := usable.position.x + 60.0 * px
	var right := usable.end.x - 60.0 * px
	if pos.x < left:
		pos.x = left
		facing = 1.0
	elif pos.x > right:
		pos.x = right
		facing = -1.0

	if fmod(st, 1.6) < d and randf() < 0.5:
		_spawn_note()
	if _check_ground():
		return
	if st > state_dur:
		_enter("idle")


func _st_look(_d: float) -> void:
	_breathe()
	var lx := 0.0
	if st < 0.9:
		lx = -_smooth((st - 0.1) / 0.3)
	elif st < 1.9:
		lx = lerpf(-1.0, 1.0, _smooth((st - 0.9) / 0.4))
	else:
		lx = 1.0 - _smooth((st - 1.9) / 0.3)
	pose.look.x = lx
	pose.head_rot = lx * 0.07
	if st > 2.3 and _once("q"):
		_spawn_text(_anchor_of(Vector2(28, -150)), "?", 16.0, COL_TEXT)
	if st > 3.0:
		_enter("idle")


func _st_wave(_d: float) -> void:
	var dur := 2.4
	var up := _smooth(st / 0.25) * (1.0 - _smooth((st - dur + 0.3) / 0.3))
	pose.face = "happy"
	pose.blush = 0.6
	pose.arm_r = lerpf(-12.0, -150.0 + sin(st * 14.0) * 22.0, up)
	pose.arm_l = 12.0
	pose.head_rot = -0.07 * up + sin(st * 3.0) * 0.03
	pose.root.y = -absf(sin(st * 7.0)) * 1.5 * up
	pose.scarf_rot = sin(st * 7.0) * 0.08
	if st > 0.4 and _once("heart"):
		_spawn_heart(_anchor_of(Vector2(32, -120)))
	if st > dur:
		_enter("idle")


func _st_hop(_d: float) -> void:
	var cyc := 0.62
	var k := int(st / cyc)
	if k >= 2:
		_enter("idle")
		return
	var f := fmod(st, cyc) / cyc
	pose.face = "happy"
	pose.blush = 0.6
	if f < 0.18:
		var a := f / 0.18
		pose.squash = Vector2(1.0 + 0.12 * a, 1.0 - 0.15 * a)
		pose.arm_l = 12.0 + 20.0 * a
	elif f < 0.82:
		var g := (f - 0.18) / 0.64
		pose.root.y = -sin(g * PI) * 26.0
		pose.squash = Vector2(0.92, 1.1).lerp(Vector2.ONE, g)
		pose.arm_l = 12.0 + 140.0 * sin(g * PI)
		pose.foot_l.y = -2.0
		pose.foot_r.y = -2.0
		pose.scarf_rot = -sin(g * PI) * 0.3
	else:
		var a := 1.0 - (f - 0.82) / 0.18
		pose.squash = Vector2(1.0 + 0.12 * a, 1.0 - 0.14 * a)
		if _once("land%d" % k):
			_dust_burst(_anchor_of(Vector2.ZERO), 3)
			_spawn_spark(_anchor_of(Vector2(randf_range(-35, 35), randf_range(-140, -100))))
	pose.arm_r = -pose.arm_l


## Tobias climbs onto Pirelli's elixir crate and stomps for attention.
func _st_box(_d: float) -> void:
	var sd := side
	var top := Vector2(42.0 * sd, -40.0)
	pose.blush = 0.45
	if st < 0.45:
		box_scale = _ease_out_back(st / 0.45)
		pose.look.x = 1.0
		pose.face = "surprised" if st > 0.1 else "normal"
		if _once("poof"):
			_dust_burst(Vector2(0, -4), 6)
			_spawn_text(_anchor_of(Vector2(0, -152)), "!", 18.0, COL_LINE)
		_breathe()
	elif st < 0.75:
		box_scale = 1.0
		var a := _smooth((st - 0.45) / 0.3)
		pose.squash = Vector2(1.0 + 0.12 * a, 1.0 - 0.15 * a)
		pose.arm_l = 12.0 + 25.0 * a
		pose.arm_r = -pose.arm_l
		pose.face = "happy"
		pose.look.x = 1.0
	elif st < 1.25:
		var g := (st - 0.75) / 0.5
		pose.root = Vector2(top.x * g, top.y * g - sin(g * PI) * 30.0)
		pose.squash = Vector2(0.92, 1.1).lerp(Vector2.ONE, g)
		pose.arm_l = 150.0
		pose.arm_r = -150.0
		pose.foot_l.y = -2.0
		pose.foot_r.y = -2.0
		pose.face = "happy"
	elif st < 1.45:
		pose.root = top
		var a := exp(-(st - 1.25) * 12.0)
		pose.squash = Vector2(1.0 + 0.16 * a, 1.0 - 0.18 * a)
		pose.face = "happy"
		if _once("land1"):
			box_sq = 0.88
			_dust_burst(Vector2(0, -40), 4)
	elif st < 5.6:
		var sp := st - 1.45
		pose.root = top
		var cyc := 0.34
		var n := int(sp / cyc)
		var f := fmod(sp, cyc) / cyc
		var lift := 0.0
		if f < 0.55:
			lift = sin(f / 0.55 * PI * 0.5) * 8.0
		else:
			lift = 8.0 * (1.0 - pow((f - 0.55) / 0.45, 2.0))
		if n % 2 == 0:
			pose.foot_l.y = -lift
		else:
			pose.foot_r.y = -lift
		var imp := exp(-f * 10.0)
		pose.squash = Vector2(1.0 + 0.05 * imp, 1.0 - 0.07 * imp)
		pose.body_off.y = imp * 1.5
		if n > 0 and _once("stomp%d" % n):
			box_sq = 0.93
			var fx := -11.0 if (n - 1) % 2 == 0 else 11.0
			_dust_burst(_anchor_of(Vector2(fx, 0)), 2)
		pose.arm_r = -150.0 + sin(sp * 9.0) * 14.0
		pose.arm_l = 30.0 + sin(sp * PI / cyc) * 25.0
		pose.face = "shout"
		pose.mouth_open = 0.4 + 0.6 * absf(sin(sp * 11.0))
		pose.head_rot = sin(sp * PI / cyc) * 0.05
		pose.scarf_rot = sin(sp * PI / cyc) * 0.2
		var lines := ["여러분 여러분!", "주목해 주세요!!", "피렐리의 기적의 묘약!"]
		_say(lines[mini(int(sp / 1.38), 2)], 0.3)
	elif st < 6.2:
		var g := (st - 5.6) / 0.6
		pose.root = top + Vector2(0, -sin(g * PI) * 7.0)
		pose.arm_l = 155.0
		pose.arm_r = -155.0
		pose.face = "happy"
		pose.blush = 0.8
		if _once("tada"):
			for i in 3:
				_spawn_spark(_anchor_of(Vector2(randf_range(-40, 40), randf_range(-170, -120))))
			_spawn_heart(_anchor_of(Vector2(-26, -150)))
			_spawn_heart(_anchor_of(Vector2(26, -150)))
	elif st < 6.7:
		var g := (st - 6.2) / 0.5
		pose.root = Vector2(top.x * (1.0 - g), top.y * (1.0 - g) - sin(g * PI) * 24.0)
		pose.arm_l = 120.0
		pose.arm_r = -120.0
		pose.face = "happy"
	elif st < 7.1:
		var g := (st - 6.7) / 0.4
		if _once("land2"):
			_dust_burst(_anchor_of(Vector2.ZERO), 4)
		var a := exp(-g * 5.0)
		pose.squash = Vector2(1.0 + 0.12 * a, 1.0 - 0.14 * a)
		pose.face = "hehe"
		box_scale = 1.0 - _smooth(g)
	else:
		box_visible = false
		box_scale = 0.0
		pos.x += char_off.x * pet_scale
		char_off = Vector2.ZERO
		_enter("idle")


## The wig pops off, Tobias is embarrassed, then tosses it back on.
func _st_wig(d: float) -> void:
	var head_c := Vector2(0, -118)
	pose.arms_front = true
	if st < 0.5:
		var a := _smooth(st / 0.5)
		pose.arm_l = lerpf(12.0, 150.0, a)
		pose.arm_r = -pose.arm_l
	elif st < 1.25:
		pose.arm_l = 150.0 + sin(st * 40.0) * 4.0
		pose.arm_r = -150.0 - sin(st * 40.0) * 4.0
		pose.face = "effort"
		pose.blush = 0.6
		wig_off.y = -1.5 - absf(sin(st * 30.0)) * 2.5
		pose.head_off.y = sin(st * 40.0) * 0.8
		pose.squash = Vector2(1.03, 0.97)
		if st > 0.6 and _once("sweat"):
			_spawn_sweat()
	else:
		if _once("pop"):
			wig_attached = false
			wig_off = Vector2.ZERO
			wig_rot = 0.0
			wig_c = head_c + Vector2(0, -2)
			wig_vel = Vector2(60.0, -380.0)
			wig_spin = 10.0
			_spawn_text(_anchor_of(Vector2(-20, -160)), "뽁!", 17.0, COL_LINE)
			for i in 3:
				_spawn_spark(_anchor_of(Vector2(randf_range(-30, 30), randf_range(-140, -110))))
		if st < 4.0:
			_wig_physics(d)

		if st < 2.2:
			var a := _smooth((st - 1.25) / 0.25)
			pose.arm_l = lerpf(150.0, 70.0, a)
			pose.arm_r = -pose.arm_l
			pose.face = "surprised"
			pose.look = Vector2(0, -1) if st < 1.8 else Vector2(1, 0.3)
			var k := exp(-(st - 1.25) * 8.0)
			pose.squash = Vector2(1.0 - 0.08 * k, 1.0 + 0.1 * k)
		elif st < 3.6:
			pose.arm_l = 150.0 + sin(st * 9.0) * 3.0
			pose.arm_r = -pose.arm_l
			pose.face = "shy"
			pose.blush = 1.0
			pose.root_rot = sin(st * 9.0) * 0.07
			if st < 3.4:
				_say("앗…! 보지 마세요!", 0.3)
			if st > 2.3 and _once("shine1"):
				_spawn_spark(_anchor_of(Vector2(-16, -126)))
			if st > 3.0 and _once("shine2"):
				_spawn_spark(_anchor_of(Vector2(-10, -132)))
		elif st < 4.0:
			var a := _smooth((st - 3.6) / 0.4)
			pose.look = Vector2(signf(wig_c.x), 0.4)
			pose.arm_l = lerpf(150.0, 40.0, a)
			pose.arm_r = -pose.arm_l
			pose.squash = Vector2(1.0 + 0.1 * a, 1.0 - 0.12 * a)
			pose.blush = 0.7
		elif st < 4.7:
			if _once("toss"):
				wig_from = wig_c
				_say("영차!", 0.6)
			var g := (st - 4.0) / 0.7
			wig_c = wig_from.lerp(head_c, g) + Vector2(0, -sin(g * PI) * 55.0)
			wig_rot = lerpf(0.0, TAU + 0.3, g)
			pose.arm_l = 140.0
			pose.arm_r = -140.0
			pose.face = "happy"
			pose.look = Vector2(0, -1)
		else:
			if _once("catch"):
				wig_attached = true
				wig_rot = 0.3
				wig_off = Vector2(3, 1)
				_spawn_spark(_anchor_of(Vector2(20, -150)))
			var g := st - 4.7
			var fix := _smooth((g - 0.2) / 0.5)
			wig_rot = 0.3 * (1.0 - fix) + sin(g * 20.0) * 0.03 * exp(-g * 3.0)
			wig_off = Vector2(3, 1).lerp(Vector2.ZERO, fix)
			var adjust := 1.0 - _smooth((g - 0.6) / 0.3)
			pose.arm_l = lerpf(12.0, 150.0 + sin(g * 25.0) * 5.0, adjust)
			pose.arm_r = -pose.arm_l
			var k := exp(-g * 8.0)
			pose.squash = Vector2(1.0 + 0.1 * k, 1.0 - 0.12 * k)
			pose.face = "hehe"
			pose.blush = 0.7
			if g > 0.5 and _once("note"):
				_spawn_note()
			if g > 0.95:
				wig_rot = 0.0
				wig_off = Vector2.ZERO
				_enter("idle")


func _wig_physics(d: float) -> void:
	if wig_attached:
		return
	wig_vel.y += 1300.0 * d
	wig_c += wig_vel * d
	wig_rot += wig_spin * d
	if wig_c.y >= -32.0:
		wig_c.y = -32.0
		if wig_vel.y > 200.0:
			wig_vel.y = -wig_vel.y * 0.3
			wig_vel.x *= 0.6
			wig_spin *= 0.4
			_dust_burst(_anchor_of(Vector2(wig_c.x, 0)), 3)
		else:
			wig_vel = Vector2.ZERO
			wig_spin = 0.0
			wig_rot = lerp_angle(wig_rot, 0.0, 1.0 - exp(-10.0 * d))


func _st_sleep(d: float) -> void:
	var a := _smooth(st / 0.8)
	var br := sin(st * 1.7)
	pose.squash = Vector2(1.0 + 0.03 * a + br * 0.01, 1.0 - 0.06 * a - br * 0.012)
	pose.head_rot = 0.16 * a + br * 0.015
	pose.head_off.y = 2.0 * a
	pose.arm_l = 6.0
	pose.arm_r = -6.0
	pose.face = "sleep"
	pose.blush = 0.45
	pose.nose_bubble = a * (0.5 + 0.5 * br)
	if st > 0.8 and fmod(st, 1.3) < d:
		_spawn_z()
	if st > state_dur:
		_enter("wake")


func _st_wake(_d: float) -> void:
	if st < 0.9:
		var g := sin(st / 0.9 * PI)
		pose.face = "yawn"
		pose.mouth_open = g
		pose.arm_l = lerpf(6.0, 165.0, g)
		pose.arm_r = -pose.arm_l
		pose.squash = Vector2(1.0 - 0.04 * g, 1.0 + 0.06 * g)
	else:
		_breathe()
	if st > 1.4:
		_enter("idle")


func _st_poke(_d: float) -> void:
	if _once("bang"):
		_spawn_text(_anchor_of(Vector2(26, -152)), "!", 18.0, COL_LINE)
	if st < 0.1:
		var a := st / 0.1
		pose.squash = Vector2(1.0 + 0.15 * a, 1.0 - 0.18 * a)
		pose.face = "surprised"
	elif st < 0.4:
		var g := (st - 0.1) / 0.3
		pose.root.y = -sin(g * PI) * 10.0
		pose.squash = Vector2(0.92, 1.1).lerp(Vector2.ONE, g)
		pose.face = "surprised"
		pose.arm_l = 60.0
		pose.arm_r = -60.0
	else:
		var g := st - 0.4
		pose.face = "happy"
		pose.blush = 0.8
		pose.root_rot = sin(g * 22.0) * 0.06 * exp(-g * 2.5)
		pose.arm_l = 25.0
		pose.arm_r = -25.0
		if _once("heart"):
			_spawn_heart(_anchor_of(Vector2(-28, -130)))
	if st > 1.2:
		_enter("idle")


func _st_pout(_d: float) -> void:
	pose.face = "pout"
	pose.blush = 1.0
	if _once("anger"):
		_spawn_anger()
		_say("흥!", 1.2)
	var k := sin(st * 18.0)
	pose.foot_l.y = -maxf(0.0, k) * 4.0
	pose.foot_r.y = -maxf(0.0, -k) * 4.0
	pose.arm_l = 30.0 + absf(k) * 10.0
	pose.arm_r = -pose.arm_l
	pose.squash = Vector2(1.03, 0.97)
	pose.head_rot = sin(st * 3.0) * 0.05
	pose.look.x = -0.6
	if st > 2.4:
		_enter("idle")


func _st_petted(d: float) -> void:
	pose.face = "happy"
	pose.blush = 1.0
	pose.head_rot = sin(st * 4.0) * 0.1
	pose.squash = Vector2(1.0 - sin(st * 8.0) * 0.01, 1.0 + sin(st * 8.0) * 0.015)
	pose.arm_l = 20.0
	pose.arm_r = -20.0
	if fmod(st, 0.35) < d:
		_spawn_heart(_anchor_of(Vector2(randf_range(-30, 30), -140)))
	if _once("hehe"):
		_say("헤헤…", 1.2)
	if t_total - last_rub > 0.8 and st > 1.0:
		_enter("idle")


func _st_drag(_d: float) -> void:
	var m := Vector2(DisplayServer.mouse_get_position())
	pos = m - grab * pet_scale
	pose.root_rot = swing
	pose.rot_pivot = grab
	pose.squash = Vector2(0.96, 1.05)
	var k := sin(st * 16.0)
	pose.foot_l.y = -maxf(0.0, k) * 5.0
	pose.foot_r.y = -maxf(0.0, -k) * 5.0
	pose.arm_l = 50.0 + sin(st * 13.0) * 25.0
	pose.arm_r = -50.0 - sin(st * 13.0 + 1.3) * 25.0
	pose.scarf_rot = -swing * 0.8 + sin(st * 6.0) * 0.1
	pose.face = "surprised" if absf(last_mouse_vel.x) > 900.0 * pet_scale else "worried"
	pose.blush = 0.5
	if st > 0.3 and _once("sweat"):
		_spawn_sweat()


func _st_fall(d: float) -> void:
	var px := pet_scale
	vel.y += GRAVITY * px * d
	pos += vel * d
	max_fall_speed = maxf(max_fall_speed, vel.length())
	var left := usable.position.x + 50.0 * px
	var right := usable.end.x - 50.0 * px
	if pos.x < left:
		pos.x = left
		vel.x = absf(vel.x) * 0.5
	elif pos.x > right:
		pos.x = right
		vel.x = -absf(vel.x) * 0.5
	var top := usable.position.y + 150.0 * px
	if pos.y < top and vel.y < 0.0:
		pos.y = top
		vel.y = absf(vel.y) * 0.3
	var ground := float(usable.end.y)
	if pos.y >= ground:
		pos.y = ground
		if vel.y > 1300.0 * px:
			vel.y = -vel.y * 0.35
			vel.x *= 0.7
			_dust_burst(Vector2.ZERO, 5)
		else:
			_dust_burst(Vector2.ZERO, 4)
			if max_fall_speed > 2300.0 * px:
				_enter("dizzy")
			else:
				_enter("land")
			return

	swing = lerpf(swing, clampf(vel.x / (2600.0 * px), -0.5, 0.5), 1.0 - exp(-6.0 * d))
	pose.root_rot = swing
	pose.rot_pivot = Vector2(0, -60)
	pose.face = "surprised"
	pose.arm_l = 140.0 + sin(st * 20.0) * 20.0
	pose.arm_r = -140.0 - sin(st * 20.0 + 1.0) * 20.0
	var k := sin(st * 18.0)
	pose.foot_l.y = -maxf(0.0, k) * 4.0
	pose.foot_r.y = -maxf(0.0, -k) * 4.0
	pose.squash = Vector2(0.94, 1.08)
	pose.scarf_rot = sin(st * 10.0) * 0.2


func _st_land(_d: float) -> void:
	var a := exp(-st * 9.0) * cos(st * 28.0)
	pose.squash = Vector2(1.0 + 0.2 * a, 1.0 - 0.22 * a)
	pose.arm_l = 12.0 + 30.0 * absf(a)
	pose.arm_r = -pose.arm_l
	if st > 0.45:
		if greet_after_land:
			greet_after_land = false
			_say("안녕하세요!", 2.2)
			_enter("wave")
		else:
			_enter("idle")


func _st_dizzy(_d: float) -> void:
	var fade := 1.0 - st / 2.4
	pose.face = "dizzy"
	pose.dizzy = true
	pose.root_rot = sin(st * 5.0) * 0.12 * fade
	pose.head_rot = sin(st * 5.0 + 1.0) * 0.1 * fade
	pose.squash = Vector2(1.03, 0.97)
	pose.arm_l = 20.0 + sin(st * 5.0) * 8.0
	pose.arm_r = -20.0 + sin(st * 5.0) * 8.0
	if st > 2.4:
		_enter("idle")


# ======================================================================
# Input
# ======================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if not _hit_char(mb.position):
					return
				if mb.double_click:
					pressing = false
					if state in PETTABLE or state in ["poke", "pout"]:
						_start_action("hop")
					return
				pressing = true
				press_screen = Vector2(DisplayServer.mouse_get_position())
			else:
				if dragging:
					_end_drag()
				elif pressing:
					_on_click()
				pressing = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_open_menu()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask == 0 and state in PETTABLE and _hit_head(mm.position):
			rub += mm.relative.length() / pet_scale
			last_rub = t_total
			if state != "petted" and rub > 240.0:
				_enter("petted")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and dragging:
		_end_drag()


func _poll_mouse(d: float) -> void:
	var m := Vector2(DisplayServer.mouse_get_position())
	var mv := (m - last_mouse) / maxf(d, 0.001)
	if pressing and not dragging and m.distance_to(press_screen) > 6.0:
		_begin_drag(m)
	if dragging:
		mouse_hist.append([t_total, m])
		while mouse_hist.size() > 2 and t_total - float(mouse_hist[0][0]) > 0.1:
			mouse_hist.pop_front()
		swing_vel += (mv.x - last_mouse_vel.x) * 0.0014 / pet_scale
		swing_vel += (-swing * 38.0 - swing_vel * 4.5) * d
		swing = clampf(swing + swing_vel * d, -1.1, 1.1)
	last_mouse_vel = mv
	last_mouse = m


func _begin_drag(m: Vector2) -> void:
	_cleanup_specials()
	dragging = true
	pressing = false
	grab = (m - pos) / pet_scale
	grab.x = clampf(grab.x, -40.0, 40.0)
	grab.y = clampf(grab.y, -130.0, -50.0)
	swing = 0.0
	swing_vel = 0.0
	mouse_hist.clear()
	_enter("drag")


func _end_drag() -> void:
	dragging = false
	var v := Vector2.ZERO
	if mouse_hist.size() >= 2:
		var a: Array = mouse_hist[0]
		var b: Array = mouse_hist[mouse_hist.size() - 1]
		var dt := float(b[0]) - float(a[0])
		if dt > 0.005:
			v = ((b[1] as Vector2) - (a[1] as Vector2)) / dt
	vel = v.limit_length(3200.0 * pet_scale)
	max_fall_speed = 0.0
	greet_after_land = false
	_enter("fall")


func _on_click() -> void:
	match state:
		"sleep":
			_say("앗, 깜짝이야!", 1.2)
			_enter("poke")
		"box", "wig", "fall", "drag", "land", "dizzy":
			_spawn_heart(_anchor_of(Vector2(randf_range(-20, 20), -140)))
		_:
			poke_times.append(t_total)
			while poke_times.size() > 0 and t_total - poke_times[0] > 2.5:
				poke_times.remove_at(0)
			if poke_times.size() >= 4:
				poke_times.clear()
				_enter("pout")
			else:
				_enter("poke")


func _to_char_units(local_px: Vector2) -> Vector2:
	return (local_px - FEET * pet_scale) / pet_scale - char_off - pose.root


func _hit_head(local_px: Vector2) -> bool:
	var u := _to_char_units(local_px)
	return pow(u.x / 50.0, 2.0) + pow((u.y + 92.0) / 46.0, 2.0) <= 1.0


func _hit_char(local_px: Vector2) -> bool:
	return _hit_head(local_px) or Rect2(-32, -62, 64, 64).has_point(_to_char_units(local_px))


# ======================================================================
# Window
# ======================================================================

func _apply_window() -> void:
	var w := get_window()
	var p := Vector2i((pos - FEET * pet_scale).round())
	if w.position != p:
		w.position = p


## Only the area around visible things catches the mouse; the rest of the
## window lets clicks through to the desktop. On Windows this region also
## clips drawing, so it must cover everything we draw.
func _update_passthrough() -> void:
	if state in ["drag", "fall"]:
		if not region_full:
			DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
			region_full = true
			last_region = Rect2i()
		return

	var r := Rect2(char_off + pose.root + Vector2(-64, -160), Vector2(128, 168))
	if box_visible:
		r = r.merge(Rect2(-44, -48, 88, 52))
	if not wig_attached:
		var wc := char_off + pose.root + Vector2(facing * wig_c.x, wig_c.y)
		r = r.merge(Rect2(wc - Vector2(58, 50), Vector2(116, 100)))
	for p: Particle in particles:
		r = r.merge(Rect2(p.pos - Vector2(16, 16), Vector2(32, 32)))
	var pr := Rect2(view_xf * r.position, r.size * pet_scale)
	if bubble_left > 0.0 and bubble_rect.size != Vector2.ZERO:
		pr = pr.merge(bubble_rect)
	pr = pr.intersection(Rect2(Vector2.ZERO, Vector2(get_window().size)))
	if pr.size.x <= 0.0 or pr.size.y <= 0.0:
		return
	var a := Vector2i(floori(pr.position.x / 4.0) * 4, floori(pr.position.y / 4.0) * 4)
	var b := Vector2i(ceili(pr.end.x / 4.0) * 4, ceili(pr.end.y / 4.0) * 4)
	var ri := Rect2i(a, b - a)
	if ri != last_region:
		last_region = ri
		region_full = false
		DisplayServer.window_set_mouse_passthrough(PackedVector2Array([
			Vector2(a.x, a.y), Vector2(b.x, a.y), Vector2(b.x, b.y), Vector2(a.x, b.y)]))


# ======================================================================
# Effects
# ======================================================================

func _update_blink(d: float) -> void:
	blink_timer -= d
	if blink_timer <= 0.0:
		blinking = 0.13
		blink_timer = randf_range(1.8, 4.5)
	blinking = maxf(0.0, blinking - d)


func _update_box(d: float) -> void:
	box_sq = lerpf(box_sq, 1.0, 1.0 - exp(-14.0 * d))
	if box_closing:
		box_scale -= d * 5.0
		if box_scale <= 0.0:
			box_scale = 0.0
			box_visible = false
			box_closing = false


func _update_particles(d: float) -> void:
	for p: Particle in particles:
		p.life -= d
		p.vel.y += p.grav * d
		p.pos += p.vel * d
		p.rot += p.spin * d
	for i in range(particles.size() - 1, -1, -1):
		if particles[i].life <= 0.0:
			particles.remove_at(i)
	while particles.size() > 60:
		particles.remove_at(0)


func _say(text: String, dur: float) -> void:
	if text != bubble_text or bubble_left <= 0.0:
		bubble_t = 0.0
	bubble_text = text
	bubble_left = dur


func _anchor_of(v: Vector2) -> Vector2:
	return char_off + pose.root + Vector2(facing * v.x, v.y)


func _spawn(kind: String, at: Vector2, v: Vector2, life: float, size := 1.0, grav := 0.0) -> Particle:
	var p := Particle.new()
	p.kind = kind
	p.pos = at
	p.vel = v
	p.life = life
	p.max_life = life
	p.size = size
	p.grav = grav
	particles.append(p)
	return p


func _spawn_heart(at: Vector2) -> void:
	_spawn("heart", at, Vector2(randf_range(-12, 12), -45), 1.3, randf_range(0.8, 1.15))


func _spawn_spark(at: Vector2) -> void:
	var p := _spawn("spark", at, Vector2.ZERO, 0.6, randf_range(0.8, 1.3))
	p.spin = randf_range(-3.0, 3.0)


func _dust_burst(at: Vector2, n: int) -> void:
	for i in n:
		_spawn("dust", at + Vector2(randf_range(-14, 14), -2),
			Vector2(randf_range(-40, 40), randf_range(-25, -5)), randf_range(0.35, 0.6), randf_range(3.0, 5.5))


func _spawn_text(at: Vector2, text: String, size_u: float, col: Color) -> void:
	var p := _spawn("text", at, Vector2(0, -18), 0.9, size_u)
	p.text = text
	p.color = col


func _spawn_z() -> void:
	var p := _spawn("z", _anchor_of(Vector2(24, -128)), Vector2(14, -22), 1.8, 11.0)
	p.text = "Z"
	p.color = COL_TEXT


func _spawn_note() -> void:
	var p := _spawn("note", _anchor_of(Vector2(28, -120)), Vector2(10, -30), 1.4)
	p.color = NOTE_COLORS[randi() % NOTE_COLORS.size()]


func _spawn_sweat() -> void:
	_spawn("sweat", _anchor_of(Vector2(34, -118)), Vector2(4, 12), 0.9)


func _spawn_anger() -> void:
	_spawn("anger", _anchor_of(Vector2(32, -128)), Vector2.ZERO, 1.6)


# ======================================================================
# Drawing
# ======================================================================

func _draw() -> void:
	if box_visible and box_scale > 0.01:
		_part("box", view_xf * Transform2D(0.0, Vector2(box_scale * (2.0 - box_sq), box_scale * box_sq), 0.0, Vector2.ZERO))
	_draw_char()
	_draw_particles()
	_draw_bubble()


func _part(part_name: String, xf: Transform2D, flip := false) -> void:
	var k := 1.0 / PartData.PX_PER_UNIT
	draw_set_transform_matrix(xf * Transform2D(0.0, Vector2(-k if flip else k, k), 0.0, Vector2.ZERO))
	var t: Texture2D = tex[part_name]
	var pivot: Vector2 = PartData.PIVOTS[part_name]
	draw_texture(t, -pivot)


func _draw_char() -> void:
	var p := pose
	var ct := view_xf * Transform2D(0.0, char_off + p.root)
	ct = ct * Transform2D(0.0, p.rot_pivot) * Transform2D(p.root_rot, Vector2.ZERO) * Transform2D(0.0, -p.rot_pivot)
	ct = ct * Transform2D(0.0, Vector2(facing * p.squash.x, p.squash.y), 0.0, Vector2.ZERO)
	var bt := ct * Transform2D(p.body_rot, Vector2(0, -6) + p.body_off)
	var ht := bt * Transform2D(p.head_rot, Vector2(0, -42) + p.head_off)
	var al := bt * Transform2D(deg_to_rad(p.arm_l), Vector2(-23, -38))
	var ar := bt * Transform2D(deg_to_rad(p.arm_r), Vector2(23, -38))

	_part("foot", ct * Transform2D(0.0, Vector2(-11, 0) + p.foot_l))
	_part("foot", ct * Transform2D(0.0, Vector2(11, 0) + p.foot_r), true)
	if not p.arms_front:
		_part("arm", al)
		_part("arm", ar, true)
	_part("body", bt)
	_part("scarf_tail", bt * Transform2D(p.scarf_rot, Vector2(12, -40)))
	_part("head", ht)
	draw_set_transform_matrix(ht)
	if not wig_attached:
		_draw_bald()
	_draw_face(p)
	if wig_attached:
		_part("wig", ht * Transform2D(wig_rot, Vector2(0, -70) + wig_off) * Transform2D(0.0, Vector2(0, 70)))
	_part("scarf_wrap", bt * Transform2D(0.0, Vector2(0, -42)))
	if p.arms_front:
		_part("arm", al)
		_part("arm", ar, true)
	if not wig_attached:
		_part("wig", ct * Transform2D(wig_rot, wig_c) * Transform2D(0.0, Vector2(0, 70)))
	if p.dizzy:
		draw_set_transform_matrix(ht)
		for i in 3:
			var a := st * 4.0 + TAU * i / 3.0
			_star(Vector2(cos(a) * 34.0, -92.0 + sin(a) * 9.0), 4.5, COL_SPARK)


func _draw_bald() -> void:
	_ell(Vector2(-15, -70), 8.0, 3.5, Color(1, 1, 1, 0.75), -0.5)
	_ell(Vector2(-5, -76), 2.0, 1.5, Color(1, 1, 1, 0.7))
	# a single brave little curl
	var w := sin(t_total * 7.0) * 0.25
	var base := Vector2(1, -82)
	var pts := PackedVector2Array()
	for k in 6:
		pts.append(Vector2(sin(k * 0.5) * 1.2, -k * 1.5))
	var cc := Vector2(3.2, -9.0)
	for k in 11:
		var a := PI + k * 0.17 * PI
		pts.append(cc + Vector2(cos(a), sin(a)) * 3.2 * (1.0 - k * 0.04))
	for k in pts.size():
		pts[k] = base + pts[k].rotated(w)
	draw_polyline(pts, COL_HAIR_DARK, 2.0, true)


func _draw_face(p: Pose) -> void:
	var spec: Array = FACES.get(p.face, FACES["normal"])
	var eyes: String = spec[0]
	var mouth: String = spec[1]
	var brows: String = spec[2]
	if blinking > 0.0 and eyes in ["open", "teary", "big"]:
		eyes = "closed"
	var o := Vector2(p.look.x * 4.0, p.look.y * 2.5)

	for i in 2:
		var sx := -1.0 if i == 0 else 1.0
		if p.blush > 0.01:
			var c := Vector2(24.0 * sx, -24.0) + o * 0.5
			_ell(c, 5.5, 3.2, Color(COL_BLUSH, 0.5 * p.blush))
			if p.blush > 0.75:
				for j in 3:
					var x := c.x - 2.5 + j * 2.5
					_line(Vector2(x + 1.0, c.y - 1.5), Vector2(x - 1.0, c.y + 1.5), Color(COL_BLUSH.darkened(0.2), 0.8), 0.8)

		var e := Vector2(15.0 * sx, -33.0) + o
		match eyes:
			"open", "teary":
				_ell(e, 5.0, 6.0, COL_EYE)
				var hr := 2.3 if eyes == "teary" else 1.8
				_ell(e + Vector2(-1.7, -2.3), hr, hr, Color.WHITE)
				_ell(e + Vector2(1.8, 2.2), 0.85, 0.85, Color(1, 1, 1, 0.9))
				if eyes == "teary":
					_arc(e + Vector2(0, 1.0), 5.6, 0.25 * PI, 0.75 * PI, Color(COL_SWEAT, 0.9), 1.2)
			"big":
				_ell(e, 5.8, 7.0, COL_EYE)
				_ell(e + Vector2(-2.0, -2.6), 2.3, 2.3, Color.WHITE)
				_ell(e + Vector2(2.0, 2.6), 1.1, 1.1, Color(1, 1, 1, 0.9))
			"closed":
				_arc(e, 4.5, 0.15 * PI, 0.85 * PI, COL_EYE, 1.8)
			"happy":
				_arc(e + Vector2(0, 2.0), 4.6, 1.15 * PI, 1.85 * PI, COL_EYE, 2.0)
			"squint":
				_polyline(PackedVector2Array([e + Vector2(4.0 * sx, -3.2), e + Vector2(-3.0 * sx, 0), e + Vector2(4.0 * sx, 3.2)]), COL_EYE, 1.9)
			"dizzy":
				var sp := PackedVector2Array()
				for k in 18:
					var a := k * 0.7 + st * 6.0 * sx
					sp.append(e + Vector2(cos(a), sin(a)) * (0.6 + k * 0.27))
				_polyline(sp, COL_EYE, 1.3)

		match brows:
			"soft", "raised":
				var by := -40.5 if brows == "soft" else -43.0
				_arc(Vector2(15.0 * sx, by) + o, 5.5, 1.25 * PI, 1.75 * PI, COL_LINE, 1.7)
			"angry":
				_line(Vector2(20.0 * sx, -45.0) + o, Vector2(10.0 * sx, -41.5) + o, COL_LINE, 1.8)
			"worried":
				_line(Vector2(20.0 * sx, -41.5) + o, Vector2(10.0 * sx, -45.5) + o, COL_LINE, 1.8)

	_ell(Vector2(0, -26.5) + o, 1.5, 1.3, COL_NOSE)

	var m := Vector2(0, -24) + o
	match mouth:
		"smile":
			_arc(m + Vector2(0, -3.5), 5.0, 0.2 * PI, 0.8 * PI, COL_LINE, 1.6)
		"open_smile":
			var pts := PackedVector2Array()
			for k in 13:
				var a := PI * k / 12.0
				pts.append(m + Vector2(0, -1) + Vector2(cos(a) * 5.0, sin(a) * 5.0))
			draw_colored_polygon(pts, COL_MOUTH)
			_ell(m + Vector2(0, 2.4), 2.6, 1.4, COL_TONGUE)
			pts.append(pts[0])
			_polyline(pts, COL_LINE, 1.2)
		"o":
			_ell(m + Vector2(0, 2), 2.2, 2.6, COL_MOUTH)
		"o_small":
			_ell(m + Vector2(0, 1.5), 1.6, 1.8, COL_MOUTH)
		"talk":
			var ry := 1.5 + 3.5 * p.mouth_open
			_ell(m + Vector2(0, 2), 4.0, ry, COL_MOUTH)
			_ell(m + Vector2(0, 2 + ry * 0.5), 2.2, maxf(0.6, ry * 0.35), COL_TONGUE)
		"wavy":
			var wp := PackedVector2Array()
			for k in 9:
				var x := -5.0 + k * 1.25
				wp.append(m + Vector2(x, 1.0 + sin(x * 1.3) * 0.9))
			_polyline(wp, COL_LINE, 1.5)
		"flat":
			_line(m + Vector2(-4, 1), m + Vector2(4, 1), COL_LINE, 1.6)
		"pout":
			_polyline(PackedVector2Array([m + Vector2(-3, 2.5), m + Vector2(0, 0), m + Vector2(3, 2.5)]), COL_LINE, 1.6)

	if p.nose_bubble > 0.02:
		var r := 1.5 + 5.5 * p.nose_bubble
		var c := Vector2(2.0 + r * 0.8, -25.5 + r * 0.3) + o
		_ell(c, r, r, Color(0.75, 0.9, 1.0, 0.45))
		_arc(c, r, 0.0, TAU, Color(0.45, 0.65, 0.9, 0.8), 0.8)
		_ell(c + Vector2(-r * 0.35, -r * 0.35), r * 0.22, r * 0.22, Color(1, 1, 1, 0.9))


func _draw_particles() -> void:
	draw_set_transform_matrix(view_xf)
	for p: Particle in particles:
		var a := clampf(p.life / 0.3, 0.0, 1.0)
		var age := p.max_life - p.life
		match p.kind:
			"heart":
				var pop := minf(age / 0.15, 1.0)
				_heart(p.pos + Vector2(sin(age * 6.0) * 3.0, 0), 7.0 * p.size * pop, Color(COL_HEART, a))
			"spark":
				var k := sin(clampf(age / p.max_life, 0.0, 1.0) * PI)
				_sparkle(p.pos, 6.0 * p.size * k, COL_SPARK, p.rot)
			"dust":
				var g := age / p.max_life
				_ell(p.pos, p.size * (1.0 + g), p.size * (1.0 + g) * 0.8, Color(COL_DUST, 0.8 * (1.0 - g)))
			"note":
				_note(p.pos + Vector2(sin(age * 5.0) * 3.0, 0), Color(p.color, a))
			"sweat":
				_drop(p.pos, 3.0, Color(COL_SWEAT, a))
			"anger":
				_anger(p.pos, 1.0 + 0.15 * sin(age * 14.0), Color(COL_ANGER, a))
	for p: Particle in particles:
		var a := clampf(p.life / 0.3, 0.0, 1.0)
		var age := p.max_life - p.life
		if p.kind == "text":
			var pop := _ease_out_back(age / 0.2)
			_text_px(p.pos, p.text, p.size * maxf(pop, 0.1), Color(p.color, a), Color(1, 1, 1, a))
		elif p.kind == "z":
			_text_px(p.pos + Vector2(sin(age * 3.0) * 4.0, 0), p.text, p.size + age * 4.0, Color(p.color, a), Color(1, 1, 1, a))


func _draw_bubble() -> void:
	bubble_rect = Rect2()
	if bubble_left <= 0.0 or bubble_text.is_empty():
		return
	var s := pet_scale
	var k := _ease_out_back(bubble_t / 0.18) * clampf(bubble_left / 0.15, 0.0, 1.0)
	if k <= 0.05:
		return
	var fs := maxi(8, roundi(15.0 * s))
	var ts := font.get_string_size(bubble_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var tip := view_xf * (char_off + pose.root + Vector2(0, -146))
	var size := Vector2(ts.x + 20.0 * s, fs + 14.0 * s) * k
	var win := Vector2(get_window().size)
	var cx := clampf(tip.x, size.x * 0.5 + 2.0, maxf(size.x * 0.5 + 2.0, win.x - size.x * 0.5 - 2.0))
	var rect := Rect2(Vector2(cx - size.x * 0.5, tip.y - 9.0 * s * k - size.y), size)
	var bx := clampf(tip.x, rect.position.x + 10.0 * s, rect.end.x - 10.0 * s)
	var tw := 6.0 * s * k
	var bw := 2.0 * s

	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_colored_polygon(PackedVector2Array([
		Vector2(bx - tw - bw, rect.end.y - 2.0), Vector2(bx + tw + bw, rect.end.y - 2.0), tip + Vector2(0, bw * 1.2)]), COL_OUTLINE)
	bubble_style.draw(get_canvas_item(), rect)
	draw_colored_polygon(PackedVector2Array([
		Vector2(bx - tw, rect.end.y - bw - 1.0), Vector2(bx + tw, rect.end.y - bw - 1.0), tip]), Color.WHITE)
	if k > 0.7:
		var tp := Vector2(
			rect.position.x + (rect.size.x - ts.x) * 0.5,
			rect.position.y + (rect.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
		draw_string(font, tp, bubble_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_OUTLINE)
	bubble_rect = rect.grow(bw * 2.0).expand(tip + Vector2(0, bw * 2.0))


func _text_px(at: Vector2, text: String, size_u: float, col: Color, outline_col: Color) -> void:
	draw_set_transform_matrix(Transform2D.IDENTITY)
	var fs := maxi(6, roundi(size_u * pet_scale))
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := view_xf * at + Vector2(-ts.x * 0.5, font.get_ascent(fs) * 0.4)
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, roundi(4.0 * pet_scale)), outline_col)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_set_transform_matrix(view_xf)


# ----------------------------------------------------------------------
# Shape helpers (all in the current draw transform)
# ----------------------------------------------------------------------

func _ell(c: Vector2, rx: float, ry: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, col, 0.6, true)


func _arc(c: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> void:
	draw_arc(c, r, a0, a1, 16, col, w, true)


func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w, true)


func _polyline(pts: PackedVector2Array, col: Color, w: float) -> void:
	draw_polyline(pts, col, w, true)


func _heart(c: Vector2, size: float, col: Color) -> void:
	if size < 0.3:
		return
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		var x := 16.0 * pow(sin(t), 3.0)
		var y := -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t))
		pts.append(c + Vector2(x, y) * size / 16.0)
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(col.darkened(0.25), col.a), 1.0, true)


func _sparkle(c: Vector2, r: float, col: Color, rot: float) -> void:
	if r < 0.3:
		return
	var pts := PackedVector2Array()
	for i in 8:
		var a := rot + PI * i / 4.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.3))
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, col, 0.6, true)


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + PI * i / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, col.darkened(0.3), 0.8, true)


func _drop(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(0, -r * 1.8)])
	for i in 13:
		var a := -0.15 * PI + 1.3 * PI * i / 12.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(col.darkened(0.25), col.a), 0.8, true)


func _note(c: Vector2, col: Color) -> void:
	_ell(c, 3.0, 2.3, col, -0.4)
	_line(c + Vector2(2.6, -0.5), c + Vector2(2.6, -10.0), col, 1.3)
	_polyline(PackedVector2Array([c + Vector2(2.6, -10.0), c + Vector2(6.0, -7.0), c + Vector2(6.0, -5.0)]), col, 1.3)


func _anger(c: Vector2, k: float, col: Color) -> void:
	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var sy := -1.0 if i < 2 else 1.0
		_polyline(PackedVector2Array([
			c + Vector2(sx * 1.5, sy * 5.0) * k,
			c + Vector2(sx * 1.5, sy * 1.5) * k,
			c + Vector2(sx * 5.0, sy * 1.5) * k]), col, 1.8)


func _smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _ease_out_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c := 1.70158
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)
