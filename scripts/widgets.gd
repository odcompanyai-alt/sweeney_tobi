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
signal closed(kind: String)
signal line_added(text: String)
signal home_saved(enabled: bool, hour: int, minute: int)

const SAVE_PATH := "user://widgets.cfg"
const KINDS := ["todo", "memo", "stopwatch", "calc", "lines", "home"]
const TITLES := {"todo": "토비의 할 일", "memo": "토비의 메모", "stopwatch": "토비의 스톱워치", "calc": "토비의 계산기", "lines": "토비에게 대사 가르치기", "home": "귀가 시간 설정"}
const SIZES := {"todo": Vector2i(270, 340), "memo": Vector2i(300, 340), "stopwatch": Vector2i(270, 210), "calc": Vector2i(260, 360), "lines": Vector2i(300, 330), "home": Vector2i(280, 270)}
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
var todo_items: Array = []       # {"text": String, "done": bool}; unfinished first
var memo_text := ""
var lines_input: LineEdit
var lines_list: VBoxContainer
var lines_items: Array = []      # the user's own lines, one String each
var home_check: CheckBox
var home_h_spin: SpinBox
var home_m_spin: SpinBox
var home_status: Label
var home_enabled := false
var home_h := 18
var home_m := 0
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
	_build_lines()
	_build_home()


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


## Open and on screen (a minimized widget counts as closed).
func is_open(kind: String) -> bool:
	var w := window_of(kind)
	return w != null and w.visible and w.mode != Window.MODE_MINIMIZED


## Shows the widget next to the given screen point (Tobi's feet).
func open(kind: String, near: Vector2, usable: Rect2i) -> void:
	var w := window_of(kind)
	if w.mode == Window.MODE_MINIMIZED:
		w.mode = Window.MODE_WINDOWED
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
		"lines": lines_input.grab_focus()
		"home": _home_sync_ui()
	focused.emit(kind)


func close(kind: String) -> void:
	window_of(kind).hide()
	save()
	closed.emit(kind)


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
	cfg.set_value("lines", "items", lines_items)
	cfg.set_value("home", "enabled", home_enabled)
	cfg.set_value("home", "hour", home_h)
	cfg.set_value("home", "minute", home_m)
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		# older versions stored to-dos as plain strings and lines as one text block
		for item in cfg.get_value("todo", "items", []):
			if item is Dictionary:
				todo_items.append({"text": str(item.get("text", "")), "done": bool(item.get("done", false))})
			else:
				todo_items.append({"text": str(item), "done": false})
		memo_text = str(cfg.get_value("memo", "text", ""))
		lines_items = cfg.get_value("lines", "items", [])
		if lines_items.is_empty():
			for line in str(cfg.get_value("lines", "text", "")).split("\n"):
				if not line.strip_edges().is_empty():
					lines_items.append(line.strip_edges())
		home_enabled = bool(cfg.get_value("home", "enabled", false))
		home_h = int(cfg.get_value("home", "hour", 18))
		home_m = int(cfg.get_value("home", "minute", 0))


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
	todo_input = _input_row(v, "할 일을 적고 Enter", _on_todo_submit)
	todo_list = _scroll_list(v)
	_hint(v, "다 한 일을 체크하면 토비가 같이 기뻐해요! 지우려면 × 를 눌러 주세요.")
	_rebuild_todo()


func _rebuild_todo() -> void:
	_clear(todo_list)
	for item in todo_items:
		_add_todo_row(item)


func _add_todo_row(item: Dictionary) -> void:
	var done := bool(item["done"])
	var row := HBoxContainer.new()
	var cb := CheckBox.new()
	cb.button_pressed = done
	cb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cb.toggled.connect(_on_todo_toggled.bind(item))
	row.add_child(cb)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text := str(item["text"]).replace("[", "[lb]")
	label.text = "[s]%s[/s]" % text if done else text
	label.add_theme_color_override("default_color", COL_SOFT if done else COL_INK)
	row.add_child(label)
	row.add_child(_delete_button(_on_todo_delete.bind(item)))
	todo_list.add_child(row)


func _on_todo_submit(text: String) -> void:
	var t := text.strip_edges()
	todo_input.clear()
	if t.is_empty():
		return
	# new items go to the end of the unfinished ones
	todo_items.insert(_todo_open_count(), {"text": t, "done": false})
	_rebuild_todo()
	save()


func _todo_open_count() -> int:
	var n := 0
	for item in todo_items:
		if not bool(item["done"]):
			n += 1
	return n


## Checked: strike through and sink below the unfinished items.
## Unchecked: back to the end of the unfinished items.
func _on_todo_toggled(on: bool, item: Dictionary) -> void:
	var i := todo_items.find(item)
	if i < 0:
		return
	todo_items.remove_at(i)
	item["done"] = on
	if on:
		todo_items.append(item)
	else:
		todo_items.insert(_todo_open_count(), item)
	save()
	call_deferred("_rebuild_todo")   # the checkbox is still inside its signal
	if on:
		todo_completed.emit(str(item["text"]))


func _on_todo_delete(item: Dictionary) -> void:
	var i := todo_items.find(item)
	if i >= 0:
		todo_items.remove_at(i)
	save()
	call_deferred("_rebuild_todo")


# --- Shared list pieces -----------------------------------------------

func _input_row(v: VBoxContainer, placeholder: String, on_submit: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	v.add_child(row)
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(on_submit)
	row.add_child(input)
	var add := Button.new()
	add.text = "추가"
	add.focus_mode = Control.FOCUS_NONE
	add.pressed.connect(func() -> void: on_submit.call(input.text))
	row.add_child(add)
	return input


func _scroll_list(v: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list


func _delete_button(on_press: Callable) -> Button:
	var del := Button.new()
	del.text = "×"
	del.flat = true
	del.focus_mode = Control.FOCUS_NONE
	del.tooltip_text = "삭제"
	del.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	del.add_theme_font_size_override("font_size", 18)
	del.pressed.connect(on_press)
	return del


func _clear(list: Container) -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()


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


# --- Custom lines -----------------------------------------------------

func _build_lines() -> void:
	var v := _content("lines")
	lines_input = _input_row(v, "가르칠 대사를 적고 Enter", _on_line_submit)
	lines_list = _scroll_list(v)
	_hint(v, "토비가 돌아다니다가 가끔 이 중 하나를 말해요.")
	_rebuild_lines()


func _rebuild_lines() -> void:
	_clear(lines_list)
	if lines_items.is_empty():
		var empty := Label.new()
		empty.text = "아직 가르친 대사가 없어요"
		empty.add_theme_color_override("font_color", COL_SOFT)
		lines_list.add_child(empty)
		return
	for i in lines_items.size():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "“%s”" % str(lines_items[i])
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(_delete_button(_on_line_delete.bind(i)))
		lines_list.add_child(row)


func _on_line_submit(text: String) -> void:
	var t := text.strip_edges()
	lines_input.clear()
	if t.is_empty():
		return
	lines_items.append(t)
	_rebuild_lines()
	save()
	line_added.emit(t)


func _on_line_delete(i: int) -> void:
	if i >= 0 and i < lines_items.size():
		lines_items.remove_at(i)
	save()
	call_deferred("_rebuild_lines")


## The lines the user taught Tobi.
func custom_lines() -> PackedStringArray:
	return PackedStringArray(lines_items)


# --- Going-home time --------------------------------------------------

func _build_home() -> void:
	var v := _content("home")
	home_check = CheckBox.new()
	home_check.text = "귀가 시간 알려주기"
	v.add_child(home_check)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	home_h_spin = _home_spin(23, "시")
	home_m_spin = _home_spin(59, "분")
	row.add_child(home_h_spin)
	row.add_child(home_m_spin)
	var ok := Button.new()
	ok.text = "확인"
	ok.focus_mode = Control.FOCUS_NONE
	ok.add_theme_stylebox_override("normal", _accent_box())
	ok.add_theme_color_override("font_color", Color.WHITE)
	ok.add_theme_color_override("font_hover_color", Color.WHITE)
	ok.pressed.connect(_on_home_confirm)
	v.add_child(ok)
	home_status = Label.new()
	home_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	home_status.add_theme_color_override("font_color", Color("#3f8f55"))
	home_status.modulate.a = 0.0
	v.add_child(home_status)
	_hint(v, "[확인]을 눌러야 저장돼요. 토비에게 마우스를 올리면 남은 시간을 알려줘요.")
	_home_sync_ui()


func _home_spin(max_value: int, suffix: String) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = max_value
	spin.step = 1
	spin.suffix = suffix
	spin.custom_minimum_size = Vector2(96, 0)
	return spin


## Puts the saved values back into the controls (drops unsaved edits).
func _home_sync_ui() -> void:
	home_check.button_pressed = home_enabled
	home_h_spin.value = home_h
	home_m_spin.value = home_m
	home_status.modulate.a = 0.0


func _on_home_confirm() -> void:
	home_h_spin.apply()
	home_m_spin.apply()
	home_enabled = home_check.button_pressed
	home_h = int(home_h_spin.value)
	home_m = int(home_m_spin.value)
	save()
	home_status.text = "저장됐어요! %02d:%02d %s" % [home_h, home_m, "알림 켜짐" if home_enabled else "(알림 꺼짐)"]
	home_status.modulate.a = 1.0
	var tw := home_status.create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(home_status, "modulate:a", 0.0, 0.6)
	home_saved.emit(home_enabled, home_h, home_m)


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
