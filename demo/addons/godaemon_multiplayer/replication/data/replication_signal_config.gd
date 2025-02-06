@tool
extends ReplicationConfigBase
class_name ReplicationSignalConfig

enum Flag { DebugPrint = 1 }

@export_flags("Debug Print:1") var flags := 0:
	set(x):
		flags = x
		updated.emit()

@export var arg_count := 0

func set_debug_print(m: bool):
	if m:
		flags |= 1
	else:
		flags &= ~1

func get_debug_print() -> bool:
	return flags & 1

func serialize() -> Dictionary:
	return {
		'name': name,
		'send_filter': serialize_filter(send_filter),
		'recv_filter': serialize_filter(recv_filter),
		'reliable': reliable,
		'flags': flags,
		'arg_count': arg_count,
	}

static func deserialize(d: Dictionary) -> ReplicationSignalConfig:
	var c := ReplicationSignalConfig.new()
	c.name = d.name
	c.send_filter = deserialize_filter(d.send_filter)
	c.recv_filter = deserialize_filter(d.recv_filter)
	c.reliable = bool(d.reliable)
	c.flags = int(d.flags)
	c.arg_count = int(d.get("arg_count", 0))
	return c
