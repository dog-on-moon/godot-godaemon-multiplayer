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

## Internal. Checks for a child callback's potential node whenever a node is added.
static func _child_callback_entered_tree(child: Node, parent: Node, child_path: NodePath, callback: Callable) -> void:
	var potential_node: Node = parent.get_node_or_null(child_path)
	if potential_node:
		callback.call(child)
		parent.child_entered_tree.disconnect(_child_callback_entered_tree.bind(parent, child_path, callback))

## Adds a callback when a potential child with the given nodepath is created.
static func child_callback(parent: Node, child_path: NodePath, callback: Callable) -> void:
	var potential_node: Node = parent.get_node_or_null(child_path)
	if potential_node:
		callback.call(potential_node)
		return

	parent.child_entered_tree.connect(_child_callback_entered_tree.bind(parent, child_path, callback))

## Returns a general purpose name for a given object.
static func get_object_name(obj: Variant) -> String:
	if obj is Callable:
		var method_name: String
		if obj.is_custom():
			return "LambdaFunc"
		else:
			method_name = str(obj.get_method())
			return get_object_name(obj.get_object()) + '(%s)' % method_name

	elif obj is Object:
		var script: Script = null
		if obj is Script:
			script = obj
		elif obj.get_script():
			script = obj.get_script()
		if script:
			return script.resource_path.get_file()
		
		if obj is Resource and obj.resource_name:
			return obj.resource_name
		
		var obj_name = obj.get("name")
		if not obj_name:
			obj_name = obj.get_class()
		return obj_name
	
	return str(obj)
