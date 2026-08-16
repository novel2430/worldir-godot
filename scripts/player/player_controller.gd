class_name PlayerController
extends CharacterBody3D

@export var move_speed := 5.2
@export var vertical_speed := 3.6
@export var acceleration := 16.0
@export var deceleration := 21.0
@export var look_smoothing := 17.0
@export var mouse_sensitivity := 0.0018

@onready var pivot: Node3D = $CameraPivot

var _target_yaw := 0.0
var _target_pitch := 0.0

func _ready() -> void:
    motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
    _target_yaw = rotation.y
    _target_pitch = pivot.rotation.x
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        _target_yaw -= event.relative.x * mouse_sensitivity
        _target_pitch = clampf(
            _target_pitch - event.relative.y * mouse_sensitivity,
            deg_to_rad(-80.0),
            deg_to_rad(80.0)
        )
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
    var look_blend := 1.0 - exp(-look_smoothing * maxf(delta, 0.0))
    rotation.y = lerp_angle(rotation.y, _target_yaw, look_blend)
    pivot.rotation.x = lerp_angle(pivot.rotation.x, _target_pitch, look_blend)

func _physics_process(delta: float) -> void:
    var x := 0.0
    var z := 0.0
    var y := 0.0
    var focus_owner := get_viewport().gui_get_focus_owner()
    var typing := focus_owner is LineEdit or focus_owner is TextEdit
    if not typing:
        if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): x -= 1.0
        if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): x += 1.0
        if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): z -= 1.0
        if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): z += 1.0
        if Input.is_key_pressed(KEY_SPACE): y += 1.0
        if Input.is_key_pressed(KEY_SHIFT): y -= 1.0
    var input := Vector2(x, z).normalized()
    var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
    var target_velocity := Vector3(
        direction.x * move_speed,
        y * vertical_speed,
        direction.z * move_speed
    )
    var has_input := not input.is_zero_approx() or not is_zero_approx(y)
    var response := acceleration if has_input else deceleration
    velocity = velocity.move_toward(target_velocity, response * delta)
    move_and_slide()
