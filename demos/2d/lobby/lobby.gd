extends Control

const LOBBY_PEER = preload("res://demos/2d/lobby/lobby_peer.tscn")

@onready var domain_label: Label = $DomainLabel
@onready var peer_label: RichTextLabel = $PeerLabel

var lobby_peers := []:
	set(x):
		lobby_peers = x
		update_peer_text()

func _ready() -> void:
	domain_label.text = "Server" if MultiplayerManager.is_server() else "Client"
	
	if MultiplayerManager.is_server():
		MultiplayerManager.hook_add_peer(add_peer)
		MultiplayerManager.hook_remove_peer(remove_peer)

@rpc("call_local", "authority", "reliable")
func update_peer_text():
	var peer_names := PackedStringArray()
	for lobby_peer in get_children():
		if 'peer' in lobby_peer:
			var n: String = lobby_peer.username
			if lobby_peer.peer == MultiplayerManager.peer_id:
				n = '[color=red]%s[/color]' % n
			peer_names.append(n)
	peer_label.text = 'Peers:\n' + '\n'.join(peer_names)

func add_peer(peer: int):
	var lobby_peer := LOBBY_PEER.instantiate()
	lobby_peer.peer = peer
	lobby_peer.username = "Player%s" % peer
	# MultiplayerManager.add_replicated_child(self, lobby_peer)
	add_child(lobby_peer)
	lobby_peers.append(lobby_peer)
	update_peer_text.rpc()
	update_peer_text()

func remove_peer(peer: int):
	for p in lobby_peers:
		if p.peer == peer:
			remove_child(p)
			p.queue_free()
			lobby_peers.erase(p)
			update_peer_text.rpc()
			update_peer_text()
			break
