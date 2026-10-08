@tool
extends MarginContainer

signal saved(path: String)
var file_path := ""
var dirty := false
var rows: Array[PackedStringArray] = []
@export var grid_color := Color(1, 1, 1, 0.08)
@export var changed_cell_color := Color(0.48, 0.33, 0.10, 1.0)
var _original := PackedByteArray()
var _saved_rows: Array[PackedStringArray] = []
var _row_origins: Array[int] = []
var _saved_row_values: Dictionary = {}
var _column_ids: Array[int] = []
var _saved_columns: Array[int] = []
var _next_column_id := 0
var _menu_row := -1
var _menu_column := -1
@onready var _cell_editor: TextEdit = %CellEditor
var _editing_item: TreeItem
var _editing_column := -1
var _next_row_id := 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _pending_path := ""

func _ready() -> void:
	# 表示文字と編集文字を同じ色・層で描き、フォーカス移動で見た目を変えない。
	RenderingServer.canvas_item_set_z_index(%Table.get_custom_drawing_canvas_item(), 1)
	var selection: StyleBoxFlat = %Table.get_theme_stylebox("selected_focus").duplicate()
	selection.bg_color = Color.TRANSPARENT
	for state in ["selected", "selected_focus", "hovered_selected", "hovered_selected_focus"]:
		%Table.add_theme_stylebox_override(state, selection)
	%Table.add_theme_stylebox_override("hovered", StyleBoxEmpty.new())
	for color in ["font_selected_color", "font_hovered_selected_color", "font_hovered_color"]:
		%Table.add_theme_color_override(color, %Table.get_theme_color("font_color"))
	_cell_editor.hide()
	_cell_editor.gui_input.connect(_cell_input)
	_cell_editor.focus_exited.connect(_finish_edit)
	# 長文でもセル内にスクロールバーを出して文字の位置を押し上げない。
	for child in _cell_editor.get_children(true):
		if child is ScrollBar:
			child.hide()
			child.visibility_changed.connect(child.hide)
	%Unsaved.hide()
	%Error.hide()
	%ContextMenu.hide()
	%ContextMenu.id_pressed.connect(_menu_action)
	%Save.pressed.connect(save_file)
	%Discard.pressed.connect(func(): open_file(file_path))
	%Reload.pressed.connect(func(): request_open(file_path, true))
	%Table.gui_input.connect(_table_input)
	%Table.resized.connect(_finish_edit)
	for child in %Table.get_children(true):
		if child is ScrollBar:
			child.value_changed.connect(func(_value: float): _finish_edit())
	%Table.column_title_clicked.connect(_column_title_clicked)
	%Table.item_selected.connect(_update_toolbar)
	%Unsaved.add_button("保存せずに開く", false, "discard")
	%Unsaved.confirmed.connect(func():
		if save_file():
			open_file(_pending_path))
	%Unsaved.custom_action.connect(func(action: StringName):
		if action == &"discard":
			%Unsaved.hide()
			open_file(_pending_path))
	_update_toolbar()

func request_open(path: String, reload := false) -> void:
	_finish_edit()
	if path.is_empty() or (path == file_path and not reload):
		return
	if dirty:
		_pending_path = path
		%Unsaved.popup_centered()
	else:
		open_file(path)

func open_file(path: String) -> bool:
	_finish_edit(true)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error("CSVを開けません: %s" % path)
		return false
	var next_rows: Array[PackedStringArray] = []
	while file.get_position() < file.get_length():
		next_rows.append(file.get_csv_line())
	file.close()
	rows = next_rows
	file_path = path
	_original = FileAccess.get_file_as_bytes(path)
	_row_origins.assign(range(rows.size()))
	_next_row_id = rows.size()
	_column_ids.assign(range(_column_count()))
	_next_column_id = _column_ids.size()
	_undo.clear()
	_redo.clear()
	_reset_baseline()
	_render_table()
	return true

static func _column_name(column: int) -> String:
	var name := ""
	var number := column + 1
	while number > 0:
		name = char(65 + (number - 1) % 26) + name
		number = floori(float(number - 1) / 26.0)
	return name

func _render_table() -> void:
	_finish_edit()
	%Table.clear()
	var count := _column_ids.size()
	%Table.columns = count + 1
	%Table.set_column_title(0, "行")
	%Table.set_column_custom_minimum_width(0, 52)
	%Table.set_column_expand(0, false)
	for column in count:
		%Table.set_column_title(column + 1, _column_name(column))
		var width := 80.0
		var font: Font = %Table.get_theme_font("font")
		var font_size: int = %Table.get_theme_font_size("font_size")
		for row in rows:
			if column < row.size():
				for line in row[column].split("\n"):
					width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 24.0)
		%Table.set_column_custom_minimum_width(column + 1, mini(360, ceili(width)))
		%Table.set_column_expand(column + 1, false)
	var table_root: TreeItem = %Table.create_item()
	for index in rows.size():
		var item: TreeItem = %Table.create_item(table_root)
		item.set_metadata(0, index)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CUSTOM)
		item.set_text(0, str(index + 1))
		item.set_text_alignment(0, HORIZONTAL_ALIGNMENT_CENTER)
		item.set_custom_draw_callback(0, _draw_row_header)
		for column in count:
			item.set_text(column + 1, rows[index][column] if column < rows[index].size() else "")
			item.set_tooltip_text(column + 1, item.get_text(column + 1))
			item.set_text_overrun_behavior(column + 1, TextServer.OVERRUN_TRIM_CHAR)
			if "\n" in item.get_text(column + 1):
				item.set_cell_mode(column + 1, TreeItem.CELL_MODE_CUSTOM)
				item.set_text(column + 1, rows[index][column])
				item.set_custom_color(column + 1, Color.TRANSPARENT)
				item.set_custom_draw_callback(column + 1, _draw_multiline_cell.bind(column + 1))
				var height: float = %Table.get_theme_font("font").get_height(%Table.get_theme_font_size("font_size")) * rows[index][column].split("\n").size()
				item.set_custom_minimum_height(maxf(item.get_custom_minimum_height(), height))
			item.set_editable(column + 1, false)
			item.set_edit_multiline(column + 1, true)
	_refresh_changes()

func _draw_row_header(item: TreeItem, rect: Rect2) -> void:
	var canvas: RID = %Table.get_custom_drawing_canvas_item()
	%Table.get_theme_stylebox("title_button_normal").draw(canvas, rect)
	var font: Font = %Table.get_theme_font("title_button_font")
	var font_size: int = %Table.get_theme_font_size("title_button_font_size")
	var text := item.get_text(0)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var position := rect.position + Vector2((rect.size.x - width) / 2.0, (rect.size.y - font.get_height(font_size)) / 2.0 + font.get_ascent(font_size))
	font.draw_string(canvas, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, %Table.get_theme_color("font_color"))

func _draw_multiline_cell(item: TreeItem, rect: Rect2, column: int) -> void:
	if item.get_custom_bg_color(column) == changed_cell_color:
		var background := StyleBoxFlat.new()
		background.bg_color = changed_cell_color
		var cell := rect.grow_individual(%Table.get_theme_constant("inner_item_margin_left"), %Table.get_theme_constant("inner_item_margin_top"), %Table.get_theme_constant("inner_item_margin_right"), %Table.get_theme_constant("inner_item_margin_bottom"))
		background.draw(%Table.get_custom_drawing_canvas_item(), cell)
	if item == _editing_item and column == _editing_column:
		return
	var font: Font = %Table.get_theme_font("font")
	var font_size: int = %Table.get_theme_font_size("font_size")
	var height := font.get_height(font_size)
	var paragraph := TextParagraph.new()
	paragraph.add_string(item.get_text(column), font, font_size)
	paragraph.width = rect.size.x
	paragraph.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	var position := rect.position + Vector2(0, floorf((rect.size.y - paragraph.get_line_count() * height) / 2.0))
	var color: Color = %Table.get_theme_color("font_selected_color" if item.is_selected(column) else "font_color")
	for line in paragraph.get_line_count():
		paragraph.draw_line(%Table.get_custom_drawing_canvas_item(), position + Vector2(0, floorf((height - paragraph.get_line_size(line).y) / 2.0)), line, color)
		position.y += height

func _column_count() -> int:
	var count := 1
	for row in rows:
		count = maxi(count, row.size())
	return count

func _table_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.shift_pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			var direction := -1.0 if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT] else 1.0
			for child in %Table.get_children(true):
				if child is HScrollBar:
					child.value += direction * event.factor * child.page / 8.0
			%Table.accept_event()
			return
	if event is InputEventPanGesture and event.shift_pressed:
		for child in %Table.get_children(true):
			if child is HScrollBar:
				child.value += event.delta.x + event.delta.y
		%Table.accept_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var item: TreeItem = %Table.get_item_at_position(event.position)
		var column: int = %Table.get_column_at_position(event.position)
		if column == 0 and item != null:
			_menu_row = item.get_metadata(0)
			_menu_column = -1
			%ContextMenu.clear()
			%ContextMenu.add_item("上に行を追加", 0)
			%ContextMenu.add_item("下に行を追加", 1)
			%ContextMenu.add_item("行を削除", 2)
		else:
			return
		%ContextMenu.position = Vector2i(%Table.get_screen_position() + event.position)
		%ContextMenu.popup()
		%Table.accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		var item: TreeItem = %Table.get_item_at_position(event.position)
		var column: int = %Table.get_column_at_position(event.position)
		if item != null and column > 0:
			%Table.set_selected(item, column)
			_edit_cell(item, column)
			%Table.accept_event()

func _edit_cell(item: TreeItem, column: int) -> void:
	_finish_edit()
	var font: Font = %Table.get_theme_font("font")
	var font_size: int = %Table.get_theme_font_size("font_size")
	var rect: Rect2 = %Table.get_item_area_rect(item, column)
	var style := StyleBoxEmpty.new()
	style.content_margin_left = %Table.get_theme_constant("inner_item_margin_left")
	style.content_margin_right = %Table.get_theme_constant("inner_item_margin_right")
	var text_height := font.get_height(font_size) * item.get_text(column).split("\n").size()
	style.content_margin_top = floorf((rect.size.y - text_height) / 2.0)
	style.content_margin_bottom = style.content_margin_top
	_cell_editor.add_theme_color_override("font_color", %Table.get_theme_color("font_selected_color" if item.is_selected(column) else "font_color"))
	_cell_editor.add_theme_font_override("font", font)
	_cell_editor.add_theme_font_size_override("font_size", font_size)
	_cell_editor.add_theme_constant_override("line_spacing", 0)
	_cell_editor.add_theme_stylebox_override("normal", style)
	_cell_editor.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_cell_editor.add_theme_stylebox_override("read_only", style)
	_cell_editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_editing_item = item
	_editing_column = column
	_cell_editor.position = rect.position
	_cell_editor.size = rect.size
	_cell_editor.text = item.get_text(column)
	item.set_custom_color(column, Color.TRANSPARENT)
	_cell_editor.show()
	_cell_editor.grab_focus()
	_cell_editor.set_caret_column(0)
	# 複数行は元々透明色のため、色指定だけでは再描画されず元の文字が残る。
	%Table.queue_redraw()

func _cell_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_finish_edit(true)
			%Table.grab_focus()
			%Table.accept_event()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			if event.shift_pressed:
				_cell_editor.insert_text_at_caret("\n")
			else:
				_finish_edit()
				%Table.grab_focus()
			%Table.accept_event()

func _finish_edit(cancel := false) -> void:
	if _editing_item == null:
		return
	var item := _editing_item
	var column := _editing_column
	_editing_item = null
	if not item.get_custom_draw_callback(column).is_valid():
		item.clear_custom_color(column)
	_cell_editor.hide()
	%Table.queue_redraw()
	if not cancel:
		item.set_text(column, _cell_editor.text)
		_cell_edited(item, column - 1)

func _column_title_clicked(column: int, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT or column < 0:
		return
	%ContextMenu.clear()
	if column == 0:
		_menu_row = 0
		_menu_column = -1
		%ContextMenu.add_item("先頭に行を追加", 0)
	else:
		_menu_row = -1
		_menu_column = column - 1
		%ContextMenu.add_item("左に列を追加", 3)
		%ContextMenu.add_item("右に列を追加", 4)
		%ContextMenu.add_item("列を削除", 5)
		%ContextMenu.set_item_disabled(2, _column_ids.size() == 1)
	%ContextMenu.position = Vector2i(%Table.get_screen_position() + %Table.get_local_mouse_position())
	%ContextMenu.popup()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or file_path.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
		save_file()
		get_viewport().set_input_as_handled()

func _shortcut_input(event: InputEvent) -> void:
	if _cell_editor.has_focus():
		return
	if not is_visible_in_tree() or file_path.is_empty() or not event is InputEventKey:
		return
	if not event.pressed or event.echo or not (event.ctrl_pressed or event.meta_pressed):
		return
	if event.keycode == KEY_Z:
		_restore_history(_redo, _undo) if event.shift_pressed else _restore_history(_undo, _redo)
	elif event.keycode == KEY_Y:
		_restore_history(_redo, _undo)
	else:
		return
	get_viewport().set_input_as_handled()

func _snapshot() -> Dictionary:
	# ponytail: 小規模CSVは全体コピー。巨大な表で重くなったらセル単位の履歴へ移す。
	return {"rows": rows.duplicate(true), "ids": _row_origins.duplicate(), "columns": _column_ids.duplicate()}

func _record_edit() -> void:
	_undo.append(_snapshot())
	_redo.clear()

func _restore_history(source: Array[Dictionary], destination: Array[Dictionary]) -> void:
	if source.is_empty():
		return
	destination.append(_snapshot())
	var state: Dictionary = source.pop_back()
	rows.assign(state["rows"])
	_row_origins.assign(state["ids"])
	_column_ids.assign(state["columns"])
	_render_table()

func _reset_baseline() -> void:
	_saved_rows = rows.duplicate(true)
	_saved_columns = _column_ids.duplicate()
	_saved_row_values.clear()
	for index in rows.size():
		_saved_row_values[_row_origins[index]] = rows[index].duplicate()
	dirty = false

func _refresh_changes() -> void:
	dirty = rows != _saved_rows
	var table_root: TreeItem = %Table.get_root()
	if table_root != null:
		for index in rows.size():
			var item := table_root.get_child(index)
			var origin := _row_origins[index]
			for column in %Table.columns - 1:
				var changed := not _saved_row_values.has(origin)
				if _saved_row_values.has(origin):
					var original_row: PackedStringArray = _saved_row_values[origin]
					var old_column := _saved_columns.find(_column_ids[column])
					changed = old_column < 0 or (column < rows[index].size() and (old_column >= original_row.size() or rows[index][column] != original_row[old_column]))
				if changed:
					item.set_custom_bg_color(column + 1, changed_cell_color, item.get_custom_draw_callback(column + 1).is_valid())
				else:
					item.set_custom_bg_color(column + 1, grid_color, true)
	_update_toolbar()

func _cell_edited(item: TreeItem, column: int) -> void:
	var index: int = item.get_metadata(0)
	if column < rows[index].size() and rows[index][column] == item.get_text(column + 1):
		return
	_record_edit()
	while rows[index].size() <= column:
		rows[index].append("")
	rows[index][column] = item.get_text(column + 1)
	_render_table()
	var edited: TreeItem = %Table.get_root().get_child(index)
	edited.select(column + 1)
	%Table.set_selected(edited, column + 1)

func _menu_action(id: int) -> void:
	if id in [0, 1]:
		_insert_row(_menu_row + (1 if id == 1 else 0))
	elif id == 2:
		_delete_row(_menu_row)
	elif id in [3, 4]:
		_insert_column(_menu_column + (1 if id == 4 else 0))
	elif id == 5:
		_delete_column(_menu_column)

func _insert_row(index: int) -> void:
	_record_edit()
	var row := PackedStringArray()
	row.resize(_column_ids.size())
	rows.insert(index, row)
	_row_origins.insert(index, _next_row_id)
	_next_row_id += 1
	_render_table()

func _delete_row(index: int) -> void:
	_record_edit()
	rows.remove_at(index)
	_row_origins.remove_at(index)
	_render_table()

func _insert_column(index: int) -> void:
	_record_edit()
	_column_ids.insert(index, _next_column_id)
	_next_column_id += 1
	for row_index in rows.size():
		while rows[row_index].size() < index:
			rows[row_index].append("")
		rows[row_index].insert(index, "")
	_render_table()

func _delete_column(index: int) -> void:
	if _column_ids.size() == 1:
		return
	_record_edit()
	_column_ids.remove_at(index)
	for row_index in rows.size():
		if index < rows[row_index].size():
			rows[row_index].remove_at(index)
	_render_table()

func _update_toolbar() -> void:
	%FilePath.text = file_path + (" *" if dirty else "") if not file_path.is_empty() else "GMornCsv"
	%Save.disabled = not dirty
	%Discard.disabled = not dirty
	%Reload.disabled = file_path.is_empty()

func save_file() -> bool:
	_finish_edit()
	if file_path.is_empty():
		return false
	if not FileAccess.file_exists(file_path) or FileAccess.get_file_as_bytes(file_path) != _original:
		_error("CSVが外部で変更されています。上書きせず、再読込してください。")
		return false
	var temporary := file_path + ".csv-editor-tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		_error("CSVを書き込めません: %s" % file_path)
		return false
	for row in rows:
		file.store_csv_line(row)
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temporary, file_path)
	if result != OK:
		DirAccess.remove_absolute(temporary)
		_error("CSVを保存できません: %s" % error_string(result))
		return false
	_original = FileAccess.get_file_as_bytes(file_path)
	_reset_baseline()
	_refresh_changes()
	saved.emit(file_path)
	return true

func _error(message: String) -> void:
	%Error.dialog_text = message
	%Error.popup_centered()
