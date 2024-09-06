extends Node

@onready var mp := MultiplayerRoot.fetch(self)
@onready var username_service: UsernameService = mp.get_service(UsernameService)
@onready var zone := Zone.fetch(self, mp)

@onready var scene_name := get_parent().name

func _ready() -> void:
	zone.interest_added.connect(
		func (peer: int):
			if mp.is_client():
				var my_username := username_service.get_local_username()
				var username := username_service.get_username(peer)
				print('[%s]: I see %s in %s' % [my_username, username, scene_name])
				
				if peer == mp.local_peer:
					_unreliable_hello.rpc()
					_reliable_hello.rpc()
	)
	zone.interest_removed.connect(
		func (peer: int):
			if mp.is_client():
				var my_username := username_service.get_local_username()
				var username := username_service.get_username(peer)
				print('[%s]: %s is leaving %s' % [my_username, username, scene_name])
	)

@rpc("unreliable")
func _unreliable_hello():
	if mp.is_server():
		return
	var my_username := username_service.get_local_username()
	var username := username_service.get_username(multiplayer.get_remote_sender_id())
	print('[%s]: %s says hi in %s! (unreliable)' % [my_username, username, scene_name])

@rpc("reliable")
func _reliable_hello():
	if mp.is_server():
		return
	var my_username := username_service.get_local_username()
	var username := username_service.get_username(multiplayer.get_remote_sender_id())
	print('[%s]: %s says hi in %s! (reliable)' % [my_username, username, scene_name])
