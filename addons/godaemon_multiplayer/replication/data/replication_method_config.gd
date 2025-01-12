@tool
extends ReplicationConfigBase
class_name ReplicationMethodConfig

enum Flag { DebugPrint = 1, CallLocal = 2 }

## Determines the ratelimit set for this method.
@export_range(0.0, 10.0, 0.01) var ratelimit := 0.0:
	set(x):
		ratelimit = x
		updated.emit()

## Determines the flags for this replication.
@export_flags("Debug Print:1", "Call Local:2") var flags := 0:
	set(x):
		flags = x
		updated.emit()

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

func serialize() -> Dictionary:
	return {
		'name': name,
		'send_filter': serialize_filter(send_filter),
		'recv_filter': serialize_filter(recv_filter),
		'reliable': reliable,
		'ratelimit': ratelimit,
		'flags': flags,
	}

static func deserialize(d: Dictionary) -> ReplicationMethodConfig:
	var c := ReplicationMethodConfig.new()
	c.name = d.name
	c.send_filter = deserialize_filter(d.send_filter)
	c.recv_filter = deserialize_filter(d.recv_filter)
	c.reliable = bool(d.reliable)
	c.ratelimit = float(d.ratelimit)
	c.flags = int(d.flags)
	return c
