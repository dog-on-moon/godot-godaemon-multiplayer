@tool
extends ReplicationConfigBase
class_name ReplicationMethodConfig

enum Flag { DebugPrint = 1, CallLocal = 2 }

## Determines the ratelimit set for this method.
@export_range(0.0, 10.0, 0.01) var ratelimit := 0.0:
	set(x):
		ratelimit = x
		emit_changed()

## Determines the flags for this replication.
@export_flags("Debug Print:1", "Call Local:2") var flags := 0:
	set(x):
		flags = x
		emit_changed()

func set_debug_print(m: bool):
	if m:
		flags |= 1
	else:
		flags &= ~1

func set_call_local(m: bool):
	if m:
		flags |= 2
	else:
		flags &= ~2

func get_debug_print() -> bool:
	return flags & 1

func get_call_local() -> bool:
	return flags & 2
