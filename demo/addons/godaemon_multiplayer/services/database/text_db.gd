extends DBBase
class_name TextDB
## A basic DB implementation using binary text files in the user directory.

var folder_name: String

func _init(_folder_name := "db") -> void:
	folder_name = _folder_name

func write(collection: String, key: String, properties: Dictionary[String, Variant]):
	var err := DirAccess.make_dir_recursive_absolute(get_directory(collection))
	if err != OK:
		push_error("TextDB.write: %s" % error_string(err))
		return
	var f := FileAccess.open(get_file_path(collection, key), FileAccess.WRITE)
	f.store_buffer(var_to_bytes(properties))
	f.close()

func read(collection: String, key: String) -> Dictionary[String, Variant]:
	var path := get_file_path(collection, key)
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var buffer := f.get_buffer(f.get_length())
	f.close()
	if not buffer: return {}
	var properties: Dictionary[String, Variant] = {}
	properties.assign(bytes_to_var(buffer))
	return properties

func get_directory(collection: String) -> String:
	return "user://%s/%s/" % [folder_name, collection]

func get_file_path(collection: String, key: String) -> String:
	return "%s/%s" % [get_directory(collection), key]
