@tool
extends ReplicationConfigBase
class_name ReplicationPropertyConfig

enum Flag { DebugPrint = 1, ReplicateOwnerNotSync = 2 }

enum Sync { Once, Request, Smooth }

## Determines how this property is synced.
@export var sync := Sync.Once:
	set(x):
		sync = x
		updated.emit()

## Determines the flags for this replication.
@export_flags("Debug Print:1", "Replicate Owner but not Sync:2") var flags := 0:
	set(x):
		flags = x
		updated.emit()

func set_debug_print(m: bool):
	if m:
		flags |= 1
	else:
		flags &= ~1

func set_robns(m: bool):
	if m:
		flags |= 2
	else:
		flags &= ~2

func get_debug_print() -> bool:
	return flags & 1

func get_robns() -> bool:
	return flags & 2

func get_sync_text() -> String:
	match sync:
		Sync.Once: return "Once"
		Sync.Request: return "Request"
		Sync.Smooth: return "Smooth"
	return "UnknownSync"

func serialize() -> Dictionary:
	return {
		'name': name,
		'send_filter': serialize_filter(send_filter),
		'recv_filter': serialize_filter(recv_filter),
		'reliable': reliable,
		'sync': serialize_sync(),
		'flags': flags,
	}

static func deserialize(d: Dictionary) -> ReplicationPropertyConfig:
	var c := ReplicationPropertyConfig.new()
	c.name = d.name
	c.send_filter = deserialize_filter(d.send_filter)
	c.recv_filter = deserialize_filter(d.recv_filter)
	c.reliable = bool(d.reliable)
	c.sync = deserialize_sync(d.sync)
	c.flags = int(d.flags)
	return c

func serialize_sync() -> String:
	return get_sync_text()

static func deserialize_sync(s: String) -> Sync:
	match s:
		"Once": 		return Sync.Once
		"Request": 	return Sync.Request
		"Smooth": 	return Sync.Smooth
	return Sync.Once
