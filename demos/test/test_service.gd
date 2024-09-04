extends Node
class_name TestService

@onready var mp := MultiplayerNode.fetch(self)
@onready var username_service: UsernameService = mp.get_service(UsernameService)

func _ready() -> void:
	username_service.username_updated.connect(
		func (peer: int, username: StringName):
			if peer == multiplayer.get_unique_id():
				print('Hi! Im %s!' % username)
	)
	username_service.username_request_failed.connect(print.bind('Request failed :O'))
	if mp.is_client():
		username_service.request_username(&"Moondog")
