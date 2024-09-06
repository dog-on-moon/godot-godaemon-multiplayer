extends Node

## Returns an inverted version of the given dictionary (value -> key)
static func invert_dictionary(dict: Dictionary) -> Dictionary:
	var new_dict: Dictionary = {}
	for key in dict.keys():
		new_dict[dict[key]] = key
	return new_dict
