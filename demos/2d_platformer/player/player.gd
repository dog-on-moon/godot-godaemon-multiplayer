extends CharacterBody2D

const SPEED := 400.0
const JUMP_VELOCITY := -700.0
const GRAVITY := 2.0

@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var camera_2d: Camera2D = $Camera2D
@onready var username_label: Label = $UsernameRoot/UsernameLabel

@export var color := Color.WHITE:
	set(x):
		color = x
		if not is_node_ready():
			await ready
		sprite_2d.modulate = x

var left := false
var right := false
var jump := false

func _ready() -> void:
	if Godaemon.mp(self).is_local_owner(self):
		camera_2d.enabled = true
		camera_2d.make_current()
	else:
		set_physics_process(false)
		set_process_unhandled_input(false)
	
	var us: UsernameService = Godaemon.service(self, UsernameService)
	username_label.text = us.get_username(Godaemon.mp(self).get_node_owner(self))

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if int(jump) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := int(right) - int(left)
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

func _unhandled_input(event: InputEvent) -> void:
	# This is (by and far) not the ideal way of handling movement input in Godot,
	# but managing state in _input allows compatability with the MultiplayerTestFrames.
	if event.is_action_pressed(&"ui_left"):
		left = true
	elif event.is_action_released(&"ui_left"):
		left = false
	
	if event.is_action_pressed(&"ui_right"):
		right = true
	elif event.is_action_released(&"ui_right"):
		right = false
	
	if event.is_action_pressed(&"ui_accept"):
		jump = true
	elif event.is_action_released(&"ui_accept"):
		jump = false
	
