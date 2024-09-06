@tool
extends VBoxContainer

const REPCO = preload("res://addons/godaemon_multiplayer/services/replication/replication_constants.gd")
const Util = preload("res://addons/godaemon_multiplayer/util/util.gd")

var PROPERTY_TYPE_FILTER := PackedInt32Array([
	TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR2I,
	TYPE_RECT2, TYPE_RECT2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_TRANSFORM2D,
	TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_PLANE, TYPE_QUATERNION, TYPE_AABB,
	TYPE_BASIS, TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_COLOR, TYPE_STRING_NAME,
	TYPE_NODE_PATH, TYPE_SIGNAL, TYPE_DICTIONARY, TYPE_ARRAY, TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY,
])

@onready var add_property_button: Button = %AddPropertyButton
@onready var node_label: Button = %NodeLabel
@onready var scene_replicate_button: CheckBox = %SceneReplicateButton
@onready var reload_button: Button = %ReloadButton
@onready var unselected_label: Label = %UnselectedLabel
@onready var tree: Tree = %PropertyTree
@export var plugin: EditorPlugin

@onready var editor_theme := EditorInterface.get_editor_theme()

func _ready() -> void:
	if self == get_tree().edited_scene_root:
		return
	
	EditorInterface.get_inspector().edited_object_changed.connect(_on_edited_object_changed)
	_on_edited_object_changed()
	
	add_property_button.pressed.connect(_add_property_pressed)
	
	scene_replicate_button.toggled.connect(_toggle_scene_replication)
	plugin.scene_changed.connect(_nodes_with_properties_updated)
	_nodes_with_properties_updated()
	
	reload_button.pressed.connect(plugin._reload_editor)
	tree.button_clicked.connect(_tree_button_clicked)
	tree.item_edited.connect(_tree_item_edited)
	
	_finish_themes()
	_update_tree()

func _finish_themes():
	add_property_button.icon = editor_theme.get_icon(&"Add", &"EditorIcons")
	
	tree.set_column_title(0, "Properties")
	tree.set_column_expand(0, true)
	tree.set_column_title(1, "Senders")
	tree.set_column_expand(1, false)
	tree.set_column_custom_minimum_width(1, 120)
	tree.set_column_title(2, "Receivers")
	tree.set_column_custom_minimum_width(2, 120)
	tree.set_column_expand(2, false)
	tree.set_column_title(3, "Reliable")
	tree.set_column_expand(3, false)
	tree.set_column_title(4, "Interpolated")
	tree.set_column_expand(4, false)
	tree.set_column_expand(5, false)

func _toggle_scene_replication(mode: bool):
	var scene_root := get_tree().edited_scene_root
	const key := REPCO.META_REPLICATE_SCENE
	var new_value := null if not mode else 0
	var new_value_exists: bool = new_value == 0
	var value_exists: bool = scene_root.has_meta(key)
	if value_exists != new_value_exists:
		scene_root.set_meta(key, new_value)
		EditorInterface.mark_scene_as_unsaved()
		
		if new_value == 0:
			ReplicationCacheManager.add_node_to_storage(scene_root)
		else:
			ReplicationCacheManager.remove_node_from_storage(scene_root)

func _nodes_with_properties_updated(n=null):
	var scene_root := get_tree().edited_scene_root
	if scene_root:
		scene_replicate_button.button_pressed = scene_root.has_meta(REPCO.META_REPLICATE_SCENE)
		if scene_root.has_meta(REPCO.META_SYNC_PROPERTIES):
			scene_replicate_button.disabled = true
			if not scene_root.has_meta(REPCO.META_REPLICATE_SCENE):
				scene_root.set_meta(REPCO.META_REPLICATE_SCENE, null)
				scene_replicate_button.button_pressed = true
				ReplicationCacheManager.add_node_to_storage(scene_root)
				EditorInterface.mark_scene_as_unsaved()
		else:
			scene_replicate_button.disabled = false

func _on_edited_object_changed():
	var object := EditorInterface.get_inspector().get_edited_object()
	if object and object is Node:
		unselected_label.hide()
		add_property_button.show()
		node_label.show()
		node_label.text = object.name
		node_label.icon = editor_theme.get_icon(object.get_class(), &"EditorIcons")
		_update_tree()
		tree.show()
	else:
		unselected_label.show()
		add_property_button.hide()
		node_label.hide()
		tree.hide()

func _add_property_pressed():
	var object := EditorInterface.get_inspector().get_edited_object()
	if not (object and object is Node):
		return
	EditorInterface.popup_property_selector(object, _on_property_selected, PROPERTY_TYPE_FILTER)

func _on_property_selected(property_path):
	if property_path.is_empty():
		return
	var object := EditorInterface.get_inspector().get_edited_object()
	if not (object and object is Node):
		return
	if REPCO.get_replicated_property(object, property_path):
		return
	
	var undo_redo := plugin.get_undo_redo()
	undo_redo.create_action("Add property")
	undo_redo.add_do_method(
		self, &"_add_property", object, property_path,
		REPCO.DEFAULT_SEND_FILTER,
		REPCO.DEFAULT_RECV_FILTER,
		REPCO.DEFAULT_SYNC_RELIABLE,
		REPCO.DEFAULT_SYNC_INTERP,
	)
	undo_redo.add_undo_method(self, &"_remove_property", object, property_path)
	undo_redo.commit_action()

func _add_property(object: Node, property_path: NodePath, send: int, recv: int, reliable: bool, interp: bool):
	if not is_instance_valid(object):
		return
	REPCO.set_replicated_property(object, property_path, send, recv, reliable, interp)
	_nodes_with_properties_updated()
	EditorInterface.mark_scene_as_unsaved()
	_add_property_to_tree(object, property_path)

func _remove_property(object: Node, property_path: NodePath):
	if not is_instance_valid(object):
		return
	REPCO.remove_replicated_property(object, property_path)
	_nodes_with_properties_updated()
	EditorInterface.mark_scene_as_unsaved()
	_update_tree()

func _update_tree():
	# Set base tree.
	tree.clear()
	tree.create_item()
	
	# Now add more...
	var object := EditorInterface.get_inspector().get_edited_object()
	if not (object and object is Node):
		return
	for property_path in REPCO.get_replicated_property_dict(object):
		_add_property_to_tree(object, property_path)

func _add_property_to_tree(object: Node, property_path: NodePath):
	var value := object.get_indexed(property_path)
	var type := typeof(value)
	
	var property_data := REPCO.get_replicated_property(object, property_path)
	var send: int = property_data[0]
	var recv: int = property_data[1]
	var reliable: bool = property_data[2]
	var interp: bool = property_data[3]
	
	var item := tree.create_item()
	item.set_selectable(0, false)
	item.set_selectable(1, false)
	item.set_selectable(2, false)
	item.set_selectable(3, false)
	item.set_selectable(4, false)
	item.set_selectable(5, false)
	item.set_metadata(0, property_path)
	item.set_text(0, String(property_path))
	item.set_icon(0, editor_theme.get_icon(get_type_name(type), &"EditorIcons"))
	item.add_button(5, editor_theme.get_icon(&"Remove", &"EditorIcons"))
	
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
	item.set_cell_mode(1, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(1, 0, REPCO.PeerFilterBitfieldToName.size(), 1)
	item.set_text(1, ",".join(REPCO.PeerFilterBitfieldToName.values()))
	item.set_range(1, REPCO.real_filter_to_editor_filter(send))
	item.set_editable(1, true)
	
	item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
	item.set_cell_mode(2, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(2, 0, REPCO.PeerFilterBitfieldToName.size(), 1)
	item.set_text(2, ",".join(REPCO.PeerFilterBitfieldToName.values()))
	item.set_range(2, REPCO.real_filter_to_editor_filter(recv))
	item.set_editable(2, true)
	
	item.set_cell_mode(3, TreeItem.CELL_MODE_CHECK)
	item.set_checked(3, reliable)
	item.set_editable(3, true)
	
	item.set_cell_mode(4, TreeItem.CELL_MODE_CHECK)
	item.set_checked(4, interp)
	item.set_editable(4, true)

static func get_type_name(type: int):
	match type:
		TYPE_NIL:
			return "Nil"
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "String"
		TYPE_VECTOR2:
			return "Vector2"
		TYPE_VECTOR2I:
			return "Vector2i"
		TYPE_RECT2:
			return "Rect2"
		TYPE_RECT2I:
			return "Rect2i"
		TYPE_TRANSFORM2D:
			return "Transform2D"
		TYPE_VECTOR3:
			return "Vector3"
		TYPE_VECTOR3I:
			return "Vector3i"
		TYPE_VECTOR4:
			return "Vector4"
		TYPE_VECTOR4I:
			return "Vector4i"
		TYPE_PLANE:
			return "Plane"
		TYPE_AABB:
			return "AABB"
		TYPE_QUATERNION:
			return "Quaternion"
		TYPE_BASIS:
			return "Basis"
		TYPE_TRANSFORM3D:
			return "Transform3D"
		TYPE_PROJECTION:
			return "Projection"
		TYPE_COLOR:
			return "Color"
		TYPE_RID:
			return "RID"
		TYPE_OBJECT:
			return "Object"
		TYPE_CALLABLE:
			return "Callable"
		TYPE_SIGNAL:
			return "Signal"
		TYPE_STRING_NAME:
			return "StringName"
		TYPE_NODE_PATH:
			return "NodePath"
		TYPE_DICTIONARY:
			return "Dictionary"
		TYPE_ARRAY:
			return "Array"
		TYPE_PACKED_BYTE_ARRAY:
			return "PackedByteArray"
		TYPE_PACKED_INT32_ARRAY:
			return "PackedInt32Array"
		TYPE_PACKED_INT64_ARRAY:
			return "PackedInt64Array"
		TYPE_PACKED_FLOAT32_ARRAY:
			return "PackedFloat32Array"
		TYPE_PACKED_FLOAT64_ARRAY:
			return "PackedFloat64Array"
		TYPE_PACKED_STRING_ARRAY:
			return "PackedStringArray"
		TYPE_PACKED_VECTOR2_ARRAY:
			return "PackedVector2Array"
		TYPE_PACKED_VECTOR3_ARRAY:
			return "PackedVector3Array"
		TYPE_PACKED_COLOR_ARRAY:
			return "PackedColorArray"
		TYPE_PACKED_VECTOR4_ARRAY:
			return "PackedVector4Array"
	return ""

func _tree_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int):
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var object := EditorInterface.get_inspector().get_edited_object()
	if not (object and object is Node):
		return
	var property_path: NodePath = NodePath(item.get_metadata(0))
	var data := REPCO.get_replicated_property(object, property_path)
	if data:
		var undo_redo := plugin.get_undo_redo()
		undo_redo.create_action("Remove property")
		undo_redo.add_do_method(self, &"_remove_property", object, property_path)
		undo_redo.add_undo_method(self, &"_add_property", object, property_path, data[0], data[1], data[2], data[3])
		undo_redo.commit_action()

func _tree_item_edited():
	var item := tree.get_edited()
	if not item:
		return
	var object := EditorInterface.get_inspector().get_edited_object()
	if not (object and object is Node):
		return
	var property_path: NodePath = NodePath(item.get_metadata(0))
	var data := REPCO.get_replicated_property(object, property_path)
	if data:
		var send: int = data[0]
		var recv: int = data[1]
		var reliable: bool = data[2]
		var interp: bool = data[3]
		
		var undo_redo := plugin.get_undo_redo()
		var column := tree.get_edited_column()
		match column:
			1:
				# Setting sender
				undo_redo.create_action("Set sender mode")
				undo_redo.add_do_method(self, &"_set_sender", item, object, property_path, int(item.get_range(column)))
				undo_redo.add_undo_method(self, &"_set_sender", item, object, property_path, REPCO.real_filter_to_editor_filter(send))
				undo_redo.commit_action()
			2:
				# Setting receiver
				undo_redo.create_action("Set receiver mode")
				undo_redo.add_do_method(self, &"_set_receiver", item, object, property_path, int(item.get_range(column)))
				undo_redo.add_undo_method(self, &"_set_receiver", item, object, property_path, REPCO.real_filter_to_editor_filter(recv))
				undo_redo.commit_action()
			3:
				# Setting reliable
				undo_redo.create_action("Set reliable mode")
				undo_redo.add_do_method(self, &"_set_reliable", item, object, property_path, item.is_checked(3))
				undo_redo.add_undo_method(self, &"_set_reliable", item, object, property_path, reliable)
				undo_redo.commit_action()
			4:
				# Setting interp
				undo_redo.create_action("Set interp mode")
				undo_redo.add_do_method(self, &"_set_interp", item, object, property_path, item.is_checked(4))
				undo_redo.add_undo_method(self, &"_set_interp", item, object, property_path, interp)
				undo_redo.commit_action()
		return

func _set_sender(item: TreeItem, object: Node, property_path: NodePath, send: int):
	if not is_instance_valid(object):
		return
	REPCO.get_replicated_property(object, property_path)[0] = REPCO.editor_filter_to_real_filter(send)
	item.set_range(1, send)
	EditorInterface.mark_scene_as_unsaved()

func _set_receiver(item: TreeItem, object: Node, property_path: NodePath, recv: int):
	if not is_instance_valid(object):
		return
	REPCO.get_replicated_property(object, property_path)[1] = REPCO.editor_filter_to_real_filter(recv)
	item.set_range(2, recv)
	EditorInterface.mark_scene_as_unsaved()

func _set_reliable(item: TreeItem, object: Node, property_path: NodePath, reliable: bool):
	if not is_instance_valid(object):
		return
	REPCO.get_replicated_property(object, property_path)[2] = reliable
	item.set_checked(3, reliable)
	EditorInterface.mark_scene_as_unsaved()

func _set_interp(item: TreeItem, object: Node, property_path: NodePath, interp: bool):
	if not is_instance_valid(object):
		return
	REPCO.get_replicated_property(object, property_path)[3] = interp
	item.set_checked(4, interp)
	EditorInterface.mark_scene_as_unsaved()
