extends Control

@onready var zone_1: Button = $Panel/HBoxContainer/Zone1
@onready var zone_2: Button = $Panel/HBoxContainer/Zone2
@onready var zone_3: Button = $Panel/HBoxContainer/Zone3

@onready var zone_buttons: Dictionary[int, Button] = {
	0: zone_1,
	1: zone_2,
	2: zone_3
}

var server_zones: Array[Zone] = []

@onready var mp := Godaemon.mp(self)
@onready var zone_service := Godaemon.zone_service(self)

func _ready() -> void:
	Godaemon.rpcs(self).set_rpc_server_receive_only(self, &"_request_zone")
	Godaemon.rpcs(self).set_rpc_ratelimit(self, &"_request_zone", 1, 0.1)
	
	if mp.is_client():
		for idx in zone_buttons:
			zone_buttons[idx].pressed.connect(_request_zone.rpc.bind(idx))
	else:
		hide()

@rpc("any_peer")
func _request_zone(idx: int):
	var peer := multiplayer.get_remote_sender_id()
	var zone: Zone = server_zones[idx]
	if zone_service.has_interest(peer, zone):
		zone_service.remove_interest(peer, zone)
		_request_zone_callback.rpc_id(peer, idx, false)
	else:
		zone_service.add_interest(peer, zone)
		_request_zone_callback.rpc_id(peer, idx, true)

@rpc("authority")
func _request_zone_callback(idx: int, active: bool):
	assert(mp.is_client())
	zone_buttons[idx].flat = active
