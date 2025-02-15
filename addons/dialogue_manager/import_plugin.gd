@tool
extends EditorImportPlugin


const DialogueParser = preload("res://addons/dialogue_manager/components/parser.gd")
const compiler_version = 2


var editor_plugin


func _get_importer_name() -> String:
	# TODO: change this to force a re-import of all dialogue
	return "dialogue_manager_%s" % compiler_version


func _get_visible_name() -> String:
	return "Dialogue"


func _get_import_order() -> int:
	return IMPORT_ORDER_DEFAULT


func _get_priority() -> float:
	return 1.0


func _get_resource_type():
	return "Resource"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["dialogue"])


func _get_save_extension():
	return "tres"


func _get_preset_count() -> int:
	return 0


func _get_preset_name(preset_index: int) -> String:
	return "Unknown"


func _get_import_options(path: String, preset_index: int) -> Array:
	return []


func _get_option_visibility(path: String, option_name: StringName, options: Dictionary) -> bool:
	return true


func _import(source_file: String, save_path: String, options: Dictionary, platform_variants: Array, gen_files: Array) -> int:
	return compile_file(source_file, "%s.%s" % [save_path, _get_save_extension()])


func compile_file(path: String, resource_path: String, will_cascade_cache_data: bool = true) -> int:
	# Get the raw file contents
	var file: File = File.new()
	var err: int = file.open(path, File.READ)
	if err != OK:
		return err
	var raw_text: String = file.get_as_text()
	file.close()
	
	# Parse the text
	var parser: DialogueParser = DialogueParser.new()
	err = parser.parse(raw_text)
	var data: Dictionary = parser.get_data()
	var errors: Array[Dictionary] = parser.get_errors()
	parser.free()
	
	if err != OK:
		printerr("%d errors found in %s" % [errors.size(), path])
		editor_plugin.add_errors_to_dialogue_file_cache(path, errors)
		return err
		
	# Get the current addon version
	var config: ConfigFile = ConfigFile.new()
	config.load("res://addons/dialogue_manager/plugin.cfg")
	var version: String = config.get_value("plugin", "version")
	
	# Save the results to a resource
	var resource = Resource.new()
	resource.set_meta("dialogue_manager_version", version)
	resource.set_meta("titles", data.titles)
	resource.set_meta("first_title", data.first_title)
	resource.set_meta("lines", data.lines)

	if will_cascade_cache_data:
		editor_plugin.add_to_dialogue_file_cache(path, resource_path, data)
	
	return ResourceSaver.save(resource, resource_path)
