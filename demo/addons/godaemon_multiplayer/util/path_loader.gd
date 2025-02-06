extends Object
## A class that provides path loading utilities.

## Gathers the filepaths for all files matching the extension within a given directory.
static func load_filepaths(path: String = 'res://', ext := ".tres", recursive := true) -> Array:
	if not path.ends_with("/"):
		path += '/'
	if not DirAccess.dir_exists_absolute(path):
		push_error("Could not find path: %s" % path)
		return []

	# First need to grab all relevant file paths
	var filepaths: Array = []
	var dir: DirAccess = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and recursive:
				filepaths.append_array(load_filepaths(path + file_name, ext, recursive))
			elif file_name.ends_with(ext):
				filepaths.append(path + file_name)
			file_name = dir.get_next()
	return filepaths

## Loads the resources for all files matching the extension within a given directory.
static func load_resources(path: String = 'res://', ext := ".tres", recursive := true) -> Array:
	# Harvest all filepaths, return them.
	return load_filepaths(path, ext, recursive).map(load)
