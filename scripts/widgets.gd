extends Node
## Tobi's desk widgets: a To-Do list and a memo pad, each in its own small
## always-on-top window. Contents are saved to user://widgets.cfg.
## The pet listens to the signals to react (cheer, come over and watch...).

signal todo_completed(text: String)
signal memo_typed
signal focused(kind: String)

const SAVE_PATH := "user://widgets.cfg"
const COL_INK := Color("#4a3228")
const COL_SOFT := Color("#9a8670")
const COL_PAPER := Color("#fff8ec")
const COL_ACCENT := Color("#e8743b")

var ui_scale := 1.0
var todo_win: Window
var memo_win: Window
var todo_input: LineEdit
var todo_list: VBoxContainer
var memo_edit: TextEdit
var todo_items: Array = []
var memo_dirty := false
var memo_save_timer := 0.0


func setup(scale_factor: float) -> void:
	ui_scale = scale_factor
	_load()
	var theme := _make_theme()
	todo_win = _make_window("토비의 할 일", Vector2i(270, 340), theme, "todo")
	memo_win = _make_window("토비의 메모", Vector2i(300, 340), theme, "memo")
	_build_todo()
	_build_memo()


func _process(delta: float) -> void:
	if memo_dirty:
		memo_save_timer -= delta
		if memo_save_timer <= 0.0:
			save()


func window_of(kind: String) -> Window:
	return todo_win if kind == "todo" else memo_win


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
	if kind == "todo":
		todo_input.grab_focus()
	else:
		memo_edit.grab_focus()
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
	cfg.set_value("memo", "text", memo_edit.text if memo_edit else "")
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		todo_items = cfg.get_value("todo", "items", [])
		set_meta("memo_text", str(cfg.get_value("memo", "text", "")))


# ----------------------------------------------------------------------
# Windows
# ----------------------------------------------------------------------

func _make_window(title: String, size: Vector2i, theme: Theme, kind: String) -> Window:
	var w := Window.new()
	w.title = title
	w.size = Vector2i(Vector2(size) * ui_scale)
	w.min_size = Vector2i(Vector2(220, 220) * ui_scale)
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
	head.text = title
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", COL_INK)
	v.add_child(head)
	return w


func _content(w: Window) -> VBoxContainer:
	return w.get_child(0).get_child(0) as VBoxContainer


func _build_todo() -> void:
	var v := _content(todo_win)
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

	var hint := Label.new()
	hint.text = "다 한 일을 체크하면 토비가 같이 기뻐해요!"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_SOFT)
	v.add_child(hint)
	_rebuild_todo()


func _rebuild_todo() -> void:
	for c in todo_list.get_children():
		todo_list.remove_child(c)
		c.queue_free()
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


func _build_memo() -> void:
	var v := _content(memo_win)
	memo_edit = TextEdit.new()
	memo_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	memo_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	memo_edit.placeholder_text = "여기에 적으면 토비가 구경하러 와요"
	memo_edit.text = str(get_meta("memo_text", ""))
	memo_edit.text_changed.connect(_on_memo_changed)
	v.add_child(memo_edit)


func _on_memo_changed() -> void:
	memo_dirty = true
	memo_save_timer = 1.0
	memo_typed.emit()


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
