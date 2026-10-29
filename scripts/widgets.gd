extends Node
## Tobi's desk widgets — To-Do list, memo pad, stopwatch and calculator —
## each in its own small always-on-top window. To-Do and memo contents are
## saved to user://widgets.cfg. The pet listens to the signals to react.

signal todo_completed(text: String)
signal memo_typed
signal stopwatch_changed(running: bool)
signal stopwatch_reset
signal calc_key
signal calc_result(value: float, error: bool)
signal focused(kind: String)

const SAVE_PATH := "user://widgets.cfg"
const KINDS := ["todo", "memo", "stopwatch", "calc"]
const TITLES := {"todo": "토비의 할 일", "memo": "토비의 메모", "stopwatch": "토비의 스톱워치", "calc": "토비의 계산기"}
const SIZES := {"todo": Vector2i(270, 340), "memo": Vector2i(300, 340), "stopwatch": Vector2i(270, 210), "calc": Vector2i(260, 360)}
const CALC_KEYS := ["C", "±", "%", "÷", "7", "8", "9", "×", "4", "5", "6", "-", "1", "2", "3", "+", "0", ".", "←", "="]
const COL_INK := Color("#4a3228")
const COL_SOFT := Color("#9a8670")
const COL_PAPER := Color("#fff8ec")
const COL_ACCENT := Color("#e8743b")

var ui_scale := 1.0
var windows := {}
var todo_input: LineEdit
var todo_list: VBoxContainer
var memo_edit: TextEdit
var todo_items: Array = []
var memo_text := ""
var memo_dirty := false
var memo_save_timer := 0.0

var sw_running := false
var sw_elapsed := 0.0
var sw_label: Label
var sw_button: Button

var calc_display: Label
var calc_expr: Label
var calc_entry := "0"
var calc_acc := 0.0
var calc_op := ""
var calc_new := true
var calc_error := false


func setup(scale_factor: float) -> void:
	ui_scale = scale_factor
	_load()
	var theme := _make_theme()
	for kind in KINDS:
		windows[kind] = _make_window(kind, theme)
	_build_todo()
	_build_memo()
	_build_stopwatch()
	_build_calc()


func _process(delta: float) -> void:
	if memo_dirty:
		memo_save_timer -= delta
		if memo_save_timer <= 0.0:
			save()
	if sw_running:
		sw_elapsed += delta
		sw_label.text = format_time(sw_elapsed)


func window_of(kind: String) -> Window:
	return windows.get(kind) as Window


func is_open(kind: String) -> bool:
	var w := window_of(kind)
	return w != null and w.visible


## Shows the widget next to the given screen point (Tobi's feet).
func open(kind: String, near: Vector2, usable: Rect2i) -> void:
	var w := window_of(kind)
	if not w.visible:
		var gap := 70.0 * ui_scale
		var x := near.x + gap
		if x + w.size.x > usable.end.x:
			x = near.x - gap - w.size.x
		var y := float(usable.end.y) - w.size.y - 24.0 * ui_scale
		x = clampf(x, usable.position.x, maxf(usable.position.x, usable.end.x - w.size.x))
		y = clampf(y, usable.position.y + 30.0 * ui_scale, maxf(usable.position.y, usable.end.y - w.size.y))
		w.position = Vector2i(roundi(x), roundi(y))
		w.show()
	w.grab_focus()
	match kind:
		"todo": todo_input.grab_focus()
		"memo": memo_edit.grab_focus()
	focused.emit(kind)


func close(kind: String) -> void:
	window_of(kind).hide()
	save()


func toggle(kind: String, near: Vector2, usable: Rect2i) -> void:
	if is_open(kind):
		close(kind)
	else:
		open(kind, near, usable)


func save() -> void:
	memo_dirty = false
	var cfg := ConfigFile.new()
	cfg.set_value("todo", "items", todo_items)
	cfg.set_value("memo", "text", memo_edit.text if memo_edit else memo_text)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		todo_items = cfg.get_value("todo", "items", [])
		memo_text = str(cfg.get_value("memo", "text", ""))


func format_time(t: float) -> String:
	var mins := int(t / 60.0)
	var secs := fmod(t, 60.0)
	if mins >= 60:
		return "%d:%02d:%05.2f" % [mins / 60, mins % 60, secs]
	return "%02d:%05.2f" % [mins, secs]


func format_number(v: float) -> String:
	if is_nan(v) or is_inf(v):
		return "오류"
	if absf(v) < 1e15 and v == floorf(v):
		return str(int(v))
	return String.num(v, 10)


# ----------------------------------------------------------------------
# Windows
# ----------------------------------------------------------------------

func _make_window(kind: String, theme: Theme) -> Window:
	var w := Window.new()
	w.title = TITLES[kind]
	var base: Vector2i = SIZES[kind]
	w.size = Vector2i(Vector2(base) * ui_scale)
	w.min_size = Vector2i(Vector2(200, 180) * ui_scale)
	w.content_scale_factor = ui_scale
	w.always_on_top = true
	w.visible = false
	w.theme = theme
	w.close_requested.connect(close.bind(kind))
	w.focus_entered.connect(func() -> void: focused.emit(kind))
	add_child(w)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PAPER
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	w.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := Label.new()
	head.text = TITLES[kind]
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", COL_INK)
	v.add_child(head)
	return w


func _content(kind: String) -> VBoxContainer:
	return window_of(kind).get_child(0).get_child(0) as VBoxContainer


func _hint(v: VBoxContainer, text: String) -> void:
	var hint := Label.new()
	hint.text = text
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_SOFT)
	v.add_child(hint)


# --- To-Do ------------------------------------------------------------

func _build_todo() -> void:
	var v := _content("todo")
	var row := HBoxContainer.new()
	v.add_child(row)
	todo_input = LineEdit.new()
	todo_input.placeholder_text = "할 일을 적고 Enter"
	todo_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	todo_input.text_submitted.connect(_on_todo_submit)
	row.add_child(todo_input)
	var add := Button.new()
	add.text = "추가"
	add.pressed.connect(func() -> void: _on_todo_submit(todo_input.text))
	row.add_child(add)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	todo_list = VBoxContainer.new()
	todo_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(todo_list)
	_hint(v, "다 한 일을 체크하면 토비가 같이 기뻐해요!")
	for item in todo_items:
		_add_todo_row(str(item))


func _add_todo_row(text: String) -> void:
	var row := HBoxContainer.new()
	row.set_meta("text", text)
	var cb := CheckBox.new()
	cb.text = text
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cb.toggled.connect(_on_todo_toggled.bind(row))
	row.add_child(cb)
	var del := Button.new()
	del.text = "×"
	del.flat = true
	del.tooltip_text = "삭제"
	del.pressed.connect(_on_todo_delete.bind(row))
	row.add_child(del)
	todo_list.add_child(row)


func _on_todo_submit(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty():
		return
	todo_items.append(t)
	_add_todo_row(t)
	todo_input.clear()
	save()


func _on_todo_toggled(on: bool, row: HBoxContainer) -> void:
	if not on:
		return
	var text := str(row.get_meta("text"))
	todo_items.erase(text)
	save()
	for c in row.get_children():
		if c is BaseButton:
			(c as BaseButton).disabled = true
	var tw := row.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(row, "modulate:a", 0.0, 0.45)
	tw.tween_callback(row.queue_free)
	todo_completed.emit(text)


func _on_todo_delete(row: HBoxContainer) -> void:
	todo_items.erase(str(row.get_meta("text")))
	row.queue_free()
	save()


# --- Memo -------------------------------------------------------------

func _build_memo() -> void:
	var v := _content("memo")
	memo_edit = TextEdit.new()
	memo_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	memo_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	memo_edit.placeholder_text = "여기에 적으면 토비가 구경하러 와요"
	memo_edit.text = memo_text
	memo_edit.text_changed.connect(_on_memo_changed)
	v.add_child(memo_edit)


func _on_memo_changed() -> void:
	memo_dirty = true
	memo_save_timer = 1.0
	memo_typed.emit()


# --- Stopwatch --------------------------------------------------------

func _build_stopwatch() -> void:
	var v := _content("stopwatch")
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["SF Mono", "Menlo", "Consolas", "monospace"])
	sw_label = Label.new()
	sw_label.text = format_time(0.0)
	sw_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sw_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sw_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sw_label.add_theme_font_override("font", mono)
	sw_label.add_theme_font_size_override("font_size", 40)
	v.add_child(sw_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	sw_button = Button.new()
	sw_button.text = "시작"
	sw_button.focus_mode = Control.FOCUS_NONE
	sw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw_button.add_theme_stylebox_override("normal", _accent_box())
	sw_button.add_theme_color_override("font_color", Color.WHITE)
	sw_button.add_theme_color_override("font_hover_color", Color.WHITE)
	sw_button.pressed.connect(_sw_toggle)
	row.add_child(sw_button)
	var reset := Button.new()
	reset.text = "초기화"
	reset.focus_mode = Control.FOCUS_NONE
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(_sw_reset)
	row.add_child(reset)
	_hint(v, "스페이스바로도 시작/정지할 수 있어요")
	window_of("stopwatch").window_input.connect(_on_sw_input)


func _sw_toggle() -> void:
	sw_running = not sw_running
	sw_button.text = "정지" if sw_running else "계속"
	stopwatch_changed.emit(sw_running)


func _sw_reset() -> void:
	sw_running = false
	sw_elapsed = 0.0
	sw_label.text = format_time(0.0)
	sw_button.text = "시작"
	stopwatch_reset.emit()


func _on_sw_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_SPACE:
		_sw_toggle()
		window_of("stopwatch").set_input_as_handled()


# --- Calculator -------------------------------------------------------

func _build_calc() -> void:
	var v := _content("calc")
	calc_expr = Label.new()
	calc_expr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	calc_expr.add_theme_font_size_override("font_size", 13)
	calc_expr.add_theme_color_override("font_color", COL_SOFT)
	v.add_child(calc_expr)
	calc_display = Label.new()
	calc_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	calc_display.clip_text = true
	calc_display.add_theme_font_size_override("font_size", 30)
	v.add_child(calc_display)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for key in CALC_KEYS:
		var b := Button.new()
		b.text = key
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		if key in ["÷", "×", "-", "+", "="]:
			b.add_theme_stylebox_override("normal", _accent_box())
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.pressed.connect(_calc_press.bind(key))
		grid.add_child(b)
	window_of("calc").window_input.connect(_on_calc_input)
	_calc_refresh()


func _on_calc_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var key := ""
	var ch := char(k.unicode) if k.unicode > 0 else ""
	if ch in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", "+", "-", "%"]:
		key = ch
	elif ch == "*":
		key = "×"
	elif ch == "/":
		key = "÷"
	elif ch == "=" or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
		key = "="
	elif k.keycode == KEY_BACKSPACE:
		key = "←"
	elif k.keycode == KEY_ESCAPE or k.keycode == KEY_DELETE:
		key = "C"
	if key != "":
		_calc_press(key)
		window_of("calc").set_input_as_handled()


func _calc_press(key: String) -> void:
	if calc_error and key != "C":
		_calc_clear()
	match key:
		"C":
			_calc_clear()
		"±":
			if calc_entry.begins_with("-"):
				calc_entry = calc_entry.substr(1)
			elif calc_entry != "0":
				calc_entry = "-" + calc_entry
		"%":
			calc_entry = format_number(float(calc_entry) / 100.0)
		"←":
			if not calc_new:
				calc_entry = calc_entry.left(-1)
				if calc_entry.is_empty() or calc_entry == "-":
					calc_entry = "0"
		"÷", "×", "-", "+":
			if calc_op != "" and not calc_new:
				if not _calc_apply():
					_calc_fail()
					return
			else:
				calc_acc = float(calc_entry)
			calc_op = key
			calc_new = true
		"=":
			if calc_op != "":
				if not _calc_apply():
					_calc_fail()
					return
				calc_op = ""
			calc_new = true
			_calc_refresh()
			calc_key.emit()
			calc_result.emit(float(calc_entry), false)
			return
		_:
			if calc_new:
				calc_entry = "0." if key == "." else key
				calc_new = false
			elif key == ".":
				if not "." in calc_entry:
					calc_entry += "."
			elif calc_entry == "0":
				calc_entry = key
			elif calc_entry.length() < 15:
				calc_entry += key
	_calc_refresh()
	calc_key.emit()


func _calc_apply() -> bool:
	var b := float(calc_entry)
	var r := b
	match calc_op:
		"+": r = calc_acc + b
		"-": r = calc_acc - b
		"×": r = calc_acc * b
		"÷":
			if b == 0.0:
				return false
			r = calc_acc / b
	calc_acc = r
	calc_entry = format_number(r)
	return true


func _calc_fail() -> void:
	_calc_clear()
	calc_error = true
	calc_display.text = "0으로 못 나눠요"
	calc_key.emit()
	calc_result.emit(0.0, true)


func _calc_clear() -> void:
	calc_entry = "0"
	calc_acc = 0.0
	calc_op = ""
	calc_new = true
	calc_error = false
	_calc_refresh()


func _calc_refresh() -> void:
	calc_display.text = calc_entry
	calc_expr.text = "%s %s" % [format_number(calc_acc), calc_op] if calc_op != "" else ""


# --- Look -------------------------------------------------------------

func _accent_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_ACCENT
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	return sb


func _make_theme() -> Theme:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Apple SD Gothic Neo", "Malgun Gothic", "Noto Sans CJK KR", "NanumGothic", "sans-serif"])
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 15

	var input := StyleBoxFlat.new()
	input.bg_color = Color.WHITE
	input.border_color = Color("#dccbb2")
	input.set_border_width_all(1)
	input.set_corner_radius_all(6)
	input.set_content_margin_all(8)
	var input_focus := input.duplicate() as StyleBoxFlat
	input_focus.border_color = COL_ACCENT
	input_focus.set_border_width_all(2)
	for t in ["LineEdit", "TextEdit"]:
		th.set_stylebox("normal", t, input)
		th.set_stylebox("focus", t, input_focus)
		th.set_color("font_color", t, COL_INK)
		th.set_color("font_placeholder_color", t, COL_SOFT)
		th.set_color("caret_color", t, COL_INK)
		th.set_color("selection_color", t, Color(1.0, 0.72, 0.45, 0.45))
		th.set_color("background_color", t, Color.WHITE)

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("#f3e3c8")
	btn.set_corner_radius_all(6)
	btn.set_content_margin_all(6)
	btn.content_margin_left = 12
	btn.content_margin_right = 12
	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color("#f8ecd9")
	var btn_down := btn.duplicate() as StyleBoxFlat
	btn_down.bg_color = Color("#e6cfa8")
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", btn_hover)
	th.set_stylebox("pressed", "Button", btn_down)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for t in ["Button", "CheckBox", "Label"]:
		th.set_color("font_color", t, COL_INK)
	for t in ["Button", "CheckBox"]:
		th.set_color("font_hover_color", t, COL_INK)
		th.set_color("font_pressed_color", t, COL_SOFT)
		th.set_color("font_focus_color", t, COL_INK)
		th.set_color("font_disabled_color", t, COL_SOFT)
	for s in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
		th.set_stylebox(s, "CheckBox", StyleBoxEmpty.new())
	return th
