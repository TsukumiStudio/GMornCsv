@tool
extends EditorPlugin

const VIEW := preload("gmorn_csv_view.tscn")
var _view: Control

func _enter_tree() -> void:
	_view = VIEW.instantiate()
	EditorInterface.get_editor_main_screen().add_child(_view)
	_view.hide()
	_view.saved.connect(func(path: String): EditorInterface.get_resource_filesystem().update_file(path))
	EditorInterface.get_file_system_dock().selection_changed.connect(_selection_changed)

func _exit_tree() -> void:
	EditorInterface.get_file_system_dock().selection_changed.disconnect(_selection_changed)
	_view.queue_free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "GMornCsv"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("GridContainer", "EditorIcons")

func _make_visible(visible: bool) -> void:
	if is_instance_valid(_view):
		_view.visible = visible

func _selection_changed() -> void:
	var paths := EditorInterface.get_selected_paths()
	if paths.size() == 1 and paths[0].get_extension().to_lower() == "csv":
		_view.request_open(paths[0])
		EditorInterface.set_main_screen_editor("GMornCsv")

func _get_unsaved_status(_for_scene: String) -> String:
	if is_instance_valid(_view):
		_view._finish_edit()
	return _view.file_path if is_instance_valid(_view) and _view.dirty else ""

func _save_external_data() -> void:
	if is_instance_valid(_view) and _view.dirty:
		_view.save_file()
