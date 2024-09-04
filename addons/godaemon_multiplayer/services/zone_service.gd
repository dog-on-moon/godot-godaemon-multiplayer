extends ServiceBase
class_name ZoneService
## The root node containing Zones in a ClientRoot/ServerRoot.

const ZoneSvc = preload("res://addons/godaemon_multiplayer/services/zone_svc.gd")
var svc: SubViewportContainer

func _ready() -> void:
	svc = ZoneSvc.new()
	add_child(svc)
