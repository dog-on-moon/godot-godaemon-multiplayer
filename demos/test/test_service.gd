extends ServiceBase
class_name TestService

@onready var username_service: UsernameService = mp.get_service(UsernameService)

const TERMINAL = preload("res://addons/godaemon_multiplayer/util/terminal.tscn")
var terminal

func _ready() -> void:
	terminal = TERMINAL.instantiate()
	add_child(terminal)
	
	terminal.info("Node: %s" % mp.name)
	
	username_service.username_updated.connect(
		func (peer: int, username: StringName):
			if peer == multiplayer.get_unique_id():
				terminal.info("New username: %s" % username)
				print('Hi! Im %s!' % username)
				if username == &"Moondog":
					send_message('Hi %s.' % username)
	)
	username_service.username_request_failed.connect(print.bind('Request failed :O'))
	if mp.is_client():
		username_service.request_username(&"Moondog")

func recv_message(args: Variant):
	terminal.info("New message: %s" % [args])
	print('%s: %s' % [mp.name, args])
