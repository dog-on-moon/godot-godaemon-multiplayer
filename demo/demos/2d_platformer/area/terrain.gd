@tool
extends StaticBody2D

@onready var collision_polygon_2d: CollisionPolygon2D = $CollisionPolygon2D

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func _draw() -> void:
	if collision_polygon_2d:
		draw_colored_polygon(collision_polygon_2d.polygon, Color.WHITE)
