extends Node

## Returns an inverted version of the given dictionary (value -> key)
static func invert_dictionary(dict: Dictionary) -> Dictionary:
	var new_dict: Dictionary = {}
	for key in dict.keys():
		new_dict[dict[key]] = key
	return new_dict

## Returns a relative property path between two nodes.
static func relative_property_path(node_a: Node, node_b: Node, property_path: NodePath) -> NodePath:
	if node_a == node_b:
		return property_path
	return NodePath(str(node_a.get_path_to(node_b)) + str(property_path))

## Returns a relative property path between a node and its owner.
static func owner_property_path(node: Node, property_path: NodePath) -> NodePath:
	if node.scene_file_path:
		return property_path
	return relative_property_path(node.owner, node, property_path)

## Returns the nodepath between a node and its owner.
static func owner_path(node: Node) -> NodePath:
	if node.scene_file_path:
		return NodePath()
	return node.owner.get_path_to(node)
