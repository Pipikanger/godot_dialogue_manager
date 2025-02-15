@tool
extends EditorPlugin


const DialogueConstants = preload("res://addons/dialogue_manager/constants.gd")
const DialogueImportPlugin = preload("res://addons/dialogue_manager/import_plugin.gd")
const DialogueSettings = preload("res://addons/dialogue_manager/components/settings.gd")
const MainView = preload("res://addons/dialogue_manager/views/main_view.tscn")


var import_plugin: DialogueImportPlugin
var main_view

var dialogue_file_cache: Dictionary = {}


func _enter_tree():
	add_autoload_singleton("DialogueManager", "res://addons/dialogue_manager/dialogue_manager.gd")
	add_custom_type("DialogueLabel", "RichTextLabel", preload("res://addons/dialogue_manager/dialogue_label.gd"), _get_plugin_icon())
	
	if Engine.is_editor_hint():
		import_plugin = DialogueImportPlugin.new()
		import_plugin.editor_plugin = self
		add_import_plugin(import_plugin)
		
		main_view = MainView.instantiate()
		main_view.editor_plugin = self
		get_editor_interface().get_editor_main_screen().add_child(main_view)
		_make_visible(false)
		
		update_dialogue_file_cache()
		get_editor_interface().get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
		get_editor_interface().get_file_system_dock().files_moved.connect(_on_files_moved)
		get_editor_interface().get_file_system_dock().file_removed.connect(_on_file_removed)


func _exit_tree():
	remove_autoload_singleton("DialogueManager")
	remove_custom_type("DialogueLabel")
	
	remove_import_plugin(import_plugin)
	import_plugin = null
	
	if is_instance_valid(main_view):
		main_view.queue_free()
	
	get_editor_interface().get_resource_filesystem().filesystem_changed.disconnect(_on_filesystem_changed)
	get_editor_interface().get_file_system_dock().files_moved.disconnect(_on_files_moved)


func _has_main_screen() -> bool:
	return true


func _make_visible(next_visible: bool) -> void:
	if is_instance_valid(main_view):
		main_view.visible = next_visible


func _get_plugin_name() -> String:
	return "Dialogue"


func _get_plugin_icon() -> Texture2D:
	var base_color = get_editor_interface().get_editor_settings().get_setting("interface/theme/base_color")
	var theme = "light" if base_color.v > 0.5 else "dark"
	var base_icon = load("res://addons/dialogue_manager/assets/icons/icon_%s.svg" % theme) as Texture2D
	var size = get_editor_interface().get_editor_main_screen().get_theme_icon("Godot", "EditorIcons").get_size()
	var image: Image = base_icon.get_image()
	image.resize(size.x, size.y, Image.INTERPOLATE_TRILINEAR)
	return ImageTexture.create_from_image(image)


func _handles(object) -> bool:
	return object is Resource and object.has_meta("dialogue_manager_version")


func _edit(object) -> void:
	if is_instance_valid(main_view):
		main_view.open_resource(object)


func _apply_changes() -> void:
	if is_instance_valid(main_view):
		main_view.apply_changes()


func _build() -> bool:
	# Ignore errors in other files if we are just running the test scene
	if DialogueSettings.get_user_value("is_running_test_scene", true): return true
	
	var can_build: bool = true
	var is_first_file: bool = true
	for dialogue_file in dialogue_file_cache.values():
		if dialogue_file.errors.size() > 0:
			# Open the first file
			if is_first_file:
				get_editor_interface().edit_resource(load(dialogue_file.path))
				main_view.show_build_error_dialog()
				is_first_file = false
			push_error("You have %d error(s) in %s" % [dialogue_file.errors.size(), dialogue_file.path])
			can_build = false
	return can_build


## Keep track of known files and their dependencies
func add_to_dialogue_file_cache(path: String, resource_path: String, parse_results: Dictionary) -> void:
	dialogue_file_cache[path] = {
		path = path,
		resource_path = resource_path,
		dependencies = Array(parse_results.imported_paths).filter(func(d): return d != path),
		errors = []
	}
	
	save_dialogue_cache()
	recompile_dependent_files(path)


## Keep track of compile errors
func add_errors_to_dialogue_file_cache(path: String, errors: Array[Dictionary]) -> void:
	if dialogue_file_cache.has(path):
		dialogue_file_cache[path]["errors"] = errors
	else:
		dialogue_file_cache[path] = { 
			path = path,
			errors = errors 
		}
		
	save_dialogue_cache()
	recompile_dependent_files(path)


## Update references to a moved file
func update_import_paths(from_path: String, to_path: String) -> void:
	# Update its own reference in the cache
	if dialogue_file_cache.has(from_path):
		dialogue_file_cache[to_path] = dialogue_file_cache[from_path].duplicate()
		dialogue_file_cache.erase(from_path)
	
	# Reopen the file if it's already open
	if main_view.current_file_path == from_path:
		main_view.current_file_path = ""
		main_view.open_file(to_path)
	
	# Update any other files that import the moved file
	var dependents = dialogue_file_cache.values().filter(func(d): return from_path in d.dependencies)
	for dependent in dependents:
		dependent.dependencies.erase(from_path)
		dependent.dependencies.append(to_path)
		
		# Update the live buffer
		if main_view.current_file_path == dependent.path:
			main_view.code_edit.text = main_view.code_edit.text.replace(from_path, to_path)
			main_view.pristine_text = main_view.code_edit.text

		# Open the file and update the path
		var file = File.new()
		file.open(dependent.path, File.READ)
		var text = file.get_as_text().replace(from_path, to_path)
		file.close()
		file.open(dependent.path, File.WRITE)
		file.store_string(text)
		file.close()
	
	save_dialogue_cache()


## Rebuild any files that depend on this path
func recompile_dependent_files(path: String) -> void:
	# Rebuild any files that depend on this one
	var dependents = dialogue_file_cache.values().filter(func(d): return path in d.dependencies)
	for dependent in dependents:
		if dependent.has("path") and dependent.has("resource_path"):
			import_plugin.compile_file(dependent.path, dependent.resource_path, false)


## Make sure the cache points to real files
func update_dialogue_file_cache() -> void:
	var cache: Dictionary = {}
	
	# Open our cache file if it exists
	var file: File = File.new()
	if file.file_exists(DialogueConstants.CACHE_PATH):
		file.open(DialogueConstants.CACHE_PATH, File.READ)
		cache = JSON.parse_string(file.get_as_text())
		file.close()
	
	# Scan for dialogue files
	var current_files: PackedStringArray = _get_dialogue_files_in_filesystem()
	
	# Remove any files that don't exist any more
	for path in cache.keys():
		if not path in current_files:
			cache.erase(path)
			DialogueSettings.remove_recent_file(path)
	
	dialogue_file_cache = cache


## Persist the cache
func save_dialogue_cache() -> void:
	var file: File = File.new()
	file.open(DialogueConstants.CACHE_PATH, File.WRITE)
	file.store_string(JSON.stringify(dialogue_file_cache))
	file.close()


## Recursively find any dialogue files in a directory
func _get_dialogue_files_in_filesystem(path: String = "res://") -> PackedStringArray:
	var files: PackedStringArray = []
	
	var dir = Directory.new()
	if dir.open(path) == OK:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			var file_path: String = (path + "/" + file_name).simplify_path()
			if dir.current_is_dir():
				if not file_name in [".godot", ".tmp"]:
					files.append_array(_get_dialogue_files_in_filesystem(file_path))
			elif file_name.get_extension() == "dialogue":
				files.append(file_path)
			file_name = dir.get_next()
	
	return files


### Signals


func _on_filesystem_changed() -> void:
	update_dialogue_file_cache()


func _on_files_moved(old_file: String, new_file: String) -> void:
	update_import_paths(old_file, new_file)
	DialogueSettings.move_recent_file(old_file, new_file)


func _on_file_removed(file: String) -> void:
	recompile_dependent_files(file)
	if is_instance_valid(main_view) and main_view.current_file_path == file:
		main_view.current_file_path = ""
