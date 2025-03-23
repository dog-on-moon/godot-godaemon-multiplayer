@tool
extends ReplicationConfigBase
class_name ReplicationPropertyConfig

enum Flag { DebugPrint = 1, ReplicateOwnerNotSync = 2, AngularLerp = 4, Database = 8 }

enum Sync { Once, Request, Smooth }

## Determines how this property is synced.
@export var sync := Sync.Once:
	set(x):
		sync = x
		emit_changed()

## Determines the flags for this replication.
@export_flags("Debug Print:1", "Replicate Owner but not Sync:2", "AngularLerp:4", "Database:8") var flags := 0:
	set(x):
		flags = x
		emit_changed()

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

func set_angular_lerp(m: bool):
	if m:
		flags |= 4
	else:
		flags &= ~4

func set_database(m: bool):
	if m:
		flags |= 8
	else:
		flags &= ~8

func get_debug_print() -> bool:
	return flags & 1

func get_robns() -> bool:
	return flags & 2

func get_angular_lerp() -> bool:
	return flags & 4

func get_database() -> bool:
	return flags & 8

func get_sync_text() -> String:
	match sync:
		Sync.Once: return "Once"
		Sync.Request: return "Request"
		Sync.Smooth: return "Smooth"
	return "UnknownSync"
