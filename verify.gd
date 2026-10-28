extends SceneTree

const VIEW := preload("gmorn_csv_view.tscn")
const PATH := "user://csv_editor_test.csv"
const OTHER := "user://csv_editor_other.csv"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["id", "title", "empty"]))
	file.store_csv_line(PackedStringArray(["jirai_1", "でいどりーむ, \"正式\"\n2行目", ""]))
	file.store_csv_line(PackedStringArray(["short"]))
	file.close()
	file = FileAccess.open(OTHER, FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["other"]))
	file.close()
	var view = VIEW.instantiate()
	root.size = Vector2i(1000, 600)
	root.add_child(view)
	assert(view.open_file(PATH))
	assert(view.rows.size() == 3 and view.rows[1][1] == "でいどりーむ, \"正式\"\n2行目")
	assert(view.rows[1][2] == "" and view.rows[2].size() == 1)
	await process_frame
	await process_frame
	var table: Tree = view.get_node("%Table")
	var item := table.get_root().get_child(1)
	assert(item.get_text(0) == "2", "行番号が消えた")
	item.select(2)
	assert(table.get_column_title(1) == "A" and table.get_column_title(3) == "C")
	assert(view._column_name(25) == "Z" and view._column_name(26) == "AA" and view._column_name(701) == "ZZ" and view._column_name(702) == "AAA")
	assert(not item.is_editable(2) and not table.edit_selected(), "選択しただけで編集が始まる")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = table.get_item_area_rect(item, 2).get_center()
	table.gui_input.emit(click)
	assert(not view._cell_editor.visible, "シングルクリックで編集が始まる")
	click.double_click = true
	table.gui_input.emit(click)
	await process_frame
	assert(view._cell_editor.visible, "ダブルクリックで編集が始まらない")
	var editor: TextEdit = view._cell_editor
	assert(editor != null)
	editor.text = "HANAKIN DANCIN'"
	var cell_save := InputEventKey.new()
	cell_save.keycode = KEY_S
	cell_save.ctrl_pressed = true
	cell_save.pressed = true
	view._input(cell_save)
	assert(not view._cell_editor.visible, "編集を確定できない")
	assert(not view.dirty and view.rows[1][1] == "HANAKIN DANCIN'", "編集中のCtrl Sでセルを確定・保存できない")
	item = table.get_root().get_child(1)
	view._edit_cell(item, 2)
	editor.text = "取り消す編集"
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	editor.gui_input.emit(cancel)
	assert(not editor.visible and view.rows[1][1] == "HANAKIN DANCIN'", "Escでセル編集を取り消せない")
	view._edit_cell(item, 2)
	editor.text = "改行セル"
	editor.set_caret_column(2)
	var newline := InputEventKey.new()
	newline.keycode = KEY_ENTER
	newline.shift_pressed = true
	newline.pressed = true
	root.push_input(newline, true)
	await process_frame
	assert(editor.visible and editor.text == "改行\nセル", "Shift Enterでセル内改行を入れられない")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	editor.gui_input.emit(enter)
	assert(not editor.visible and view.rows[1][1] == "改行\nセル", "Enterで改行セルを確定できない")
	_shortcut(view, KEY_Z)
	item = table.get_root().get_child(1)
	view._record_edit()
	view.rows[1][1] = "再編集"
	item.set_text(2, "再編集")
	view._refresh_changes()
	assert(item.get_custom_bg_color(2) == view.changed_cell_color, "変更セルが色付けされない")
	assert(item.get_custom_bg_color(1) == view.grid_color, "未変更セルまで色付けされた")
	view.request_open(OTHER)
	assert(view.file_path == PATH and view.get_node("%Unsaved").visible, "未保存のCSVを確認なく閉じた")
	view.get_node("%Unsaved").hide()
	assert(view.save_file())
	assert(not view.dirty)
	assert(item.get_custom_bg_color(2) == view.grid_color, "保存しても色が戻らない")
	_shortcut(view, KEY_Z)
	assert(view.dirty and view.rows[1][1] == "HANAKIN DANCIN'", "保存後のCtrl Zが効かない")
	_shortcut(view, KEY_Y)
	assert(not view.dirty and view.rows[1][1] == "再編集", "Ctrl Yが効かない")
	assert(view.open_file(PATH) and view.rows[1][1] == "再編集")
	view._insert_column(0)
	assert(view.rows[1][0] == "" and view.rows[1][2] == "再編集")
	assert(table.get_root().get_child(1).get_custom_bg_color(1) == view.changed_cell_color)
	assert(table.get_root().get_child(1).get_custom_bg_color(3) == view.grid_color, "列挿入で未変更セルまで強調された")
	_shortcut(view, KEY_Z)
	assert(not view.dirty and view.rows[1][1] == "再編集")
	_shortcut(view, KEY_Y)
	view._delete_column(0)
	assert(not view.dirty)
	_shortcut(view, KEY_Z)
	assert(view.dirty and table.get_column_title(4) == "D")
	view.get_node("%Discard").pressed.emit()

	assert(view.rows[1][2] == "" and view.rows[2].size() == 1, "保存で空欄・列数が変わった")
	view.rows[1][1] = "破棄する編集"
	view._render_table()
	assert(view.dirty)
	view.get_node("%Discard").pressed.emit()
	assert(not view.dirty and view.rows[1][1] == "再編集", "変更を破棄できない")
	assert(view.get_node("%Save").disabled and view.get_node("%Discard").disabled)
	view.rows[1][1] = "戻す編集"
	view._render_table()
	assert(view.dirty)
	view.rows[1][1] = "再編集"
	view._render_table()
	assert(not view.dirty and view.get_node("%Save").disabled and view.get_node("%Discard").disabled, "元の値に戻しても変更扱いになる")
	var right := InputEventMouseButton.new()
	right.pressed = true
	right.button_index = MOUSE_BUTTON_RIGHT
	right.position = table.get_item_area_rect(table.get_root().get_child(2), 0).get_center()
	table.gui_input.emit(right)
	assert(view.get_node("%ContextMenu").visible and view.get_node("%ContextMenu").get_item_text(1) == "下に行を追加")
	view.get_node("%ContextMenu").id_pressed.emit(1)
	view.get_node("%ContextMenu").hide()
	assert(view.dirty and view.rows.size() == 4)
	view.get_node("%Table").get_root().get_child(3).select(1)
	right.position = table.get_item_area_rect(table.get_root().get_child(3), 0).get_center()
	table.gui_input.emit(right)
	view.get_node("%ContextMenu").id_pressed.emit(2)
	view.get_node("%ContextMenu").hide()
	assert(view.rows.size() == 3 and not view.dirty, "追加した行を削除しても変更扱いになる")
	# 編集の確定で単行の列幅も、改行の行高も伸び縮みする。
	await process_frame
	await process_frame
	var original_width := table.get_column_width(2)
	var original_height := table.get_item_area_rect(table.get_root().get_child(1), 2).size.y
	view._edit_cell(table.get_root().get_child(1), 2)
	editor.text = "W".repeat(24)
	editor.gui_input.emit(enter)
	await process_frame
	await process_frame
	var widened_width := table.get_column_width(2)
	assert(widened_width > original_width, "単行セルを伸ばしても列幅が再計算されない")
	assert(table.get_selected() == table.get_root().get_child(1) and table.get_selected_column() == 2, "再計算で編集セルの選択が消えた")
	view._edit_cell(table.get_root().get_child(1), 2)
	editor.text = "短い\n改行\nセル"
	editor.gui_input.emit(enter)
	await process_frame
	await process_frame
	# 元の幅と同じかは書体しだい（取り込む側の書体で元の文字の幅が変わる）なので、伸ばした幅から縮むことを見る。
	assert(table.get_column_width(2) < widened_width, "短くしても列幅が縮まない")
	assert(table.get_item_area_rect(table.get_root().get_child(1), 2).size.y > original_height, "改行しても行が高くならない")
	view._edit_cell(table.get_root().get_child(1), 2)
	editor.text = "短い"
	editor.gui_input.emit(enter)
	await process_frame
	await process_frame
	assert(table.get_item_area_rect(table.get_root().get_child(1), 2).size.y == original_height, "改行を消しても行が縮まない")
	_shortcut(view, KEY_Z)
	await process_frame
	assert(table.get_item_area_rect(table.get_root().get_child(1), 2).size.y > original_height, "Undoで行高が戻らない")
	_shortcut(view, KEY_Y)
	await process_frame
	assert(table.get_item_area_rect(table.get_root().get_child(1), 2).size.y == original_height, "Redoで行高が戻らない")
	view.get_node("%Discard").pressed.emit()
	view.rows[0][0] = "編集中"
	view._render_table()
	var external := "id,title\nexternal,外部変更\n"
	file = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string(external)
	file.close()
	assert(not view.save_file(), "外部変更を上書きした")
	assert(FileAccess.get_file_as_string(PATH) == external and view.dirty)
	view.get_node("%Error").hide()
	view.request_open(OTHER)
	view.get_node("%Unsaved").custom_action.emit(&"discard")
	assert(view.file_path == OTHER and not view.dirty)
	view.request_open(PATH)
	assert(view.file_path == PATH and view.rows[1][1] == "外部変更")
	file = FileAccess.open(PATH, FileAccess.WRITE)
	for row_index in 120:
		var wide := PackedStringArray()
		for column in 15:
			wide.append("column_%d____________________" % column)
		file.store_csv_line(wide)
	file.close()
	assert(view.open_file(PATH))
	await process_frame
	await process_frame
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.position = table.get_global_rect().get_center()
	wheel.global_position = wheel.position
	wheel.shift_pressed = true
	root.push_input(wheel, true)
	await process_frame
	assert(table.get_scroll().x > 0 and table.get_scroll().y == 0, "Shiftホイールが横スクロールにならない")
	wheel = wheel.duplicate()
	wheel.shift_pressed = false
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	root.push_input(wheel, true)
	await process_frame
	assert(table.get_scroll().y > 0, "通常ホイールが縦スクロールにならない")
	table.column_title_clicked.emit(1, MOUSE_BUTTON_RIGHT)
	assert(view.get_node("%ContextMenu").visible and view.get_node("%ContextMenu").get_item_text(2) == "列を削除")
	view.get_node("%ContextMenu").hide()
	view._insert_row(1)
	var save_key := InputEventKey.new()
	save_key.keycode = KEY_S
	save_key.ctrl_pressed = true
	save_key.pressed = true
	view._input(save_key)
	assert(not view.dirty, "Ctrl Sで保存できない")
	view.free()
	DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(OTHER)
	print("CSV EDITOR TEST: PASS")
	quit()

func _shortcut(view: Control, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.ctrl_pressed = true
	event.pressed = true
	view._shortcut_input(event)
