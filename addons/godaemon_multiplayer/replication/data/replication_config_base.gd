@tool
extends Resource
class_name ReplicationConfigBase

signal updated

## The name of the field.
@export var name := "":
	set(x):
		name = x
		updated.emit()

enum Filter { Server = 1, Owner = 2, Client = 4 }

## Determines the send filter for this config.
@export_flags("Server:1", "Owner:2", "Client:4") var send_filter := 1:
	set(x):
		send_filter = x
		updated.emit()

## Determines the receive filter for this config.
@export_flags("Server:1", "Owner:2", "Client:4") var recv_filter := 7:
	set(x):
		recv_filter = x
		updated.emit()

## Determines if the replication is reliable or not.
@export var reliable := true:
	set(x):
		reliable = x
		updated.emit()

func set_send_filter_flag(mode: bool, filter: Filter):
	if mode:
		send_filter |= int(filter)
	else:
		send_filter &= ~int(filter)

func set_recv_filter_flag(mode: bool, filter: Filter):
	if mode:
		recv_filter |= int(filter)
	else:
		recv_filter &= ~int(filter)

func get_send_filter_flag(filter: Filter) -> bool:
	return send_filter & int(filter)

func get_recv_filter_flag(filter: Filter) -> bool:
	return recv_filter & int(filter)

func serialize() -> Dictionary:
	assert(false)
	return {}

static func deserialize(d: Dictionary) -> ReplicationConfigBase:
	assert(false)
	return null

# enum Filter { Server = 1, Owner = 2, Client = 4 }

static func filter_flags_to_txt(filter: int) -> String:
	match filter:
		0: return "Nobody"
		1: return "Server"
		2: return "Owner"
		3: return "Server+Owner"
		4: return "Not Owner"
		5: return "Server+Not Owner"
		6: return "All Clients"
		7: return "Everyone"
	return "Unknown"
