@tool
extends VBoxContainer

const ReplicationConstants = preload("res://addons/authoritative_multiplayer/internal/replication_constants.gd")

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
	tree.set_column_expand(3, false)

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
	
	var undo_redo := plugin.get_undo_redo()
	undo_redo.create_action("Add property")
	undo_redo.add_do_method(self, &"_add_property", object, property_path, ReplicationConstants.DEFAULT_SEND_FILTER, ReplicationConstants.DEFAULT_RECV_FILTER)
	undo_redo.add_undo_method(self, &"_remove_property", object, property_path)
	undo_redo.commit_action()

func _add_property(object: Node, property_path: NodePath, send: int, recv: int):
	if not is_instance_valid(object):
		return
	const key_name := ReplicationConstants.META_SYNC_PROPERTIES
	if not object.has_meta(key_name):
		object.set_meta(key_name, [])
	if property_path in object.get_meta(key_name):
		return
	object.get_meta(key_name).append(property_path)
	
	const key_send := ReplicationConstants.META_SYNC_PROPERTIES_SEND
	if not object.has_meta(key_send):
		object.set_meta(key_send, [])
	object.get_meta(key_send).append(send)
	
	const key_recv := ReplicationConstants.META_SYNC_PROPERTIES_RECV
	if not object.has_meta(key_recv):
		object.set_meta(key_recv, [])
	object.get_meta(key_recv).append(recv)
	
	EditorInterface.mark_scene_as_unsaved()
	_add_property_to_tree(property_path, send, recv)

func _remove_property(object: Node, property_path: NodePath):
	if not is_instance_valid(object):
		return
	const key_name := ReplicationConstants.META_SYNC_PROPERTIES
	var idx: int = object.get_meta(key_name, []).find(property_path)
	if idx == -1:
		return
	object.get_meta(key_name).pop_at(idx)
	const key_send := ReplicationConstants.META_SYNC_PROPERTIES_SEND
	object.get_meta(key_send).pop_at(idx)
	const key_recv := ReplicationConstants.META_SYNC_PROPERTIES_RECV
	object.get_meta(key_recv).pop_at(idx)
	
	if not object.get_meta(key_name, []):
		object.remove_meta(key_name)
		object.remove_meta(key_send)
		object.remove_meta(key_recv)
	
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
	const key_name := ReplicationConstants.META_SYNC_PROPERTIES
	const key_send := ReplicationConstants.META_SYNC_PROPERTIES_SEND
	const key_recv := ReplicationConstants.META_SYNC_PROPERTIES_RECV
	for idx in object.get_meta(key_name, []).size():
		var np: NodePath = object.get_meta(key_name)[idx]
		var send: int = object.get_meta(key_send)[idx]
		var recv: int = object.get_meta(key_recv)[idx]
		_add_property_to_tree(np, send, recv)

func _add_property_to_tree(property: NodePath, send: int, recv: int):
	var object := EditorInterface.get_inspector().get_edited_object()
	if not (object and object is Node):
		return
	var value := object.get_indexed(property)
	var type := typeof(value)
	
	var item := tree.create_item()
	item.set_selectable(0, false)
	item.set_selectable(1, false)
	item.set_selectable(2, false)
	item.set_selectable(3, false)
	item.set_metadata(0, property)
	item.set_text(0, String(property))
	item.set_icon(0, editor_theme.get_icon(get_type_name(type), &"EditorIcons"))
	item.add_button(3, editor_theme.get_icon(&"Remove", &"EditorIcons"))
	
	item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_CENTER)
	item.set_cell_mode(1, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(1, 0, ReplicationConstants.PeerFilterBitfieldToName.size(), 1)
	item.set_text(1, ",".join(ReplicationConstants.PeerFilterBitfieldToName.values()))
	item.set_range(1, ReplicationConstants.real_filter_to_editor_filter(send))
	item.set_editable(1, true)
	
	item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
	item.set_cell_mode(2, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(2, 0, ReplicationConstants.PeerFilterBitfieldToName.size(), 1)
	item.set_text(2, ",".join(ReplicationConstants.PeerFilterBitfieldToName.values()))
	item.set_range(2, ReplicationConstants.real_filter_to_editor_filter(recv))
	item.set_editable(2, true)

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
	var properties: Array = object.get_meta(ReplicationConstants.META_SYNC_PROPERTIES, [])
	var property: NodePath = NodePath(item.get_metadata(0))
	var idx := properties.find(property)
	if idx == -1:
		return
	var send: int = object.get_meta(ReplicationConstants.META_SYNC_PROPERTIES_SEND)[idx]
	var recv: int = object.get_meta(ReplicationConstants.META_SYNC_PROPERTIES_RECV)[idx]
	var undo_redo := plugin.get_undo_redo()
	undo_redo.create_action("Remove property")
	undo_redo.add_do_method(self, &"_remove_property", object, property)
	undo_redo.add_undo_method(self, &"_add_property", object, property, send, recv)
	undo_redo.commit_action()

func _tree_item_edited():
	var item := tree.get_edited()
	if not item:
		return
	var object := EditorInterface.get_inspector().get_edited_object()
	if not (object and object is Node):
		return
	var properties: Array = object.get_meta(ReplicationConstants.META_SYNC_PROPERTIES, [])
	var property: NodePath = NodePath(item.get_metadata(0))
	var idx := properties.find(property)
	if idx == -1:
		return
	var send: int = object.get_meta(ReplicationConstants.META_SYNC_PROPERTIES_SEND)[idx]
	var recv: int = object.get_meta(ReplicationConstants.META_SYNC_PROPERTIES_RECV)[idx]
	
	var undo_redo := plugin.get_undo_redo()
	var column := tree.get_edited_column()
	match column:
		1:
			# Setting sender
			undo_redo.create_action("Set sender mode")
			undo_redo.add_do_method(self, &"_set_sender", item, object, idx, int(item.get_range(column)))
			undo_redo.add_undo_method(self, &"_set_sender", item, object, idx, ReplicationConstants.real_filter_to_editor_filter(send))
			undo_redo.commit_action()
		2:
			# Setting receiver
			undo_redo.create_action("Set receiver mode")
			undo_redo.add_do_method(self, &"_set_receiver", item, object, idx, int(item.get_range(column)))
			undo_redo.add_undo_method(self, &"_set_receiver", item, object, idx, ReplicationConstants.real_filter_to_editor_filter(recv))
			undo_redo.commit_action()

func _set_sender(item: TreeItem, object: Node, idx: int, send: int):
	if not is_instance_valid(object):
		return
	object.get_meta(ReplicationConstants.META_SYNC_PROPERTIES_SEND)[idx] = ReplicationConstants.editor_filter_to_real_filter(send)
	item.set_range(1, send)
	EditorInterface.mark_scene_as_unsaved()

func _set_receiver(item: TreeItem, object: Node, idx: int, recv: int):
	if not is_instance_valid(object):
		return
	object.get_meta(ReplicationConstants.META_SYNC_PROPERTIES_RECV)[idx] = ReplicationConstants.editor_filter_to_real_filter(recv)
	item.set_range(2, recv)
	EditorInterface.mark_scene_as_unsaved()
