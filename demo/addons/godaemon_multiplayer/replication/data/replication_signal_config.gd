@tool
extends ReplicationConfigBase
class_name ReplicationSignalConfig

enum Flag { DebugPrint = 1 }

@export_flags("Debug Print:1") var flags := 0:
	set(x):
		flags = x
		emit_changed()

@export var arg_count := 0

func set_debug_print(m: bool):
	if m:
		flags |= 1
	else:
		flags &= ~1

func get_debug_print() -> bool:
	return flags & 1
