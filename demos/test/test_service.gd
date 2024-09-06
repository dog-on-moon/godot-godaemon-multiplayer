extends ServiceBase
class_name TestService

@onready var username_service: UsernameService = mp.get_service(UsernameService)

const TERMINAL = preload("res://addons/godaemon_multiplayer/util/terminal/terminal.tscn")
var terminal

func _ready() -> void:
	terminal = TERMINAL.instantiate()
	terminal.hide()
	add_child(terminal)
	
	terminal.info("Node: %s" % mp.name)
	
	username_service.username_updated.connect(
		func (peer: int, username: StringName):
			if peer == multiplayer.get_unique_id():
				terminal.info("New username: %s" % username)
				print('Hi! Im %s!' % username)
				# if username == &"Moondog":
				# 	send_message('Hi %s.' % username)
	)
	username_service.username_request_failed.connect(print.bind('Request failed :O'))
	if mp.is_client():
		username_service.request_username(&"Moondog")
	else:
		var zone_service: ZoneService = mp.get_service(ZoneService)
		var red_zone := zone_service.add_zone(preload("res://demos/test/red.tscn").instantiate())
		var green_zone := zone_service.add_zone(preload("res://demos/test/green.tscn").instantiate())
		var blue_zone := zone_service.add_zone(preload("res://demos/test/blue.tscn").instantiate())
		
		var potential_zones := [
			red_zone, green_zone,
			blue_zone,
		]
		
		mp.peer_connected.connect(
			func (peer: int):
				while true:
					var zone_in := potential_zones.duplicate()
					var zone_out := potential_zones.duplicate()
					zone_in.shuffle()
					zone_out.shuffle()
					
					const BASE := 0.1
					const RAND := 0.1
					for z in zone_in:
						zone_service.add_interest(peer, z)
						await get_tree().create_timer(BASE + randf() * RAND).timeout
					for z in zone_out:
						zone_service.remove_interest(peer, z)
						await get_tree().create_timer(BASE + randf() * RAND).timeout
		)
