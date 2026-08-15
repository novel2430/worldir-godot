class_name PlayerController
extends CharacterBody3D

@export var move_speed := 9.0
@export var vertical_speed := 7.0
@export var mouse_sensitivity := 0.0022

@onready var pivot: Node3D = $CameraPivot
var chunk_manager: ChunkManager = null

func set_chunk_manager(value: ChunkManager) -> void:
    chunk_manager = value

func _ready() -> void:
    motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        rotate_y(-event.relative.x * mouse_sensitivity)
        pivot.rotate_x(-event.relative.y * mouse_sensitivity)
        pivot.rotation.x = clamp(pivot.rotation.x, deg_to_rad(-80), deg_to_rad(80))
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventMouseButton and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
    var x := 0.0
    var z := 0.0
    var y := 0.0
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): x += 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): z -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): z += 1.0
    if Input.is_key_pressed(KEY_SPACE): y += 1.0
    if Input.is_key_pressed(KEY_SHIFT): y -= 1.0
    var input := Vector2(x, z).normalized()
    var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
    velocity.x = direction.x * move_speed
    velocity.y = y * vertical_speed
    velocity.z = direction.z * move_speed
    _move_with_chunk_gate(delta)

func _move_with_chunk_gate(delta: float) -> bool:
    if chunk_manager != null and chunk_manager.initialized:
        var predicted := global_position + velocity * delta
        var next_coord := ChunkMath.world_to_chunk(predicted)
        if (
            next_coord != chunk_manager.get_current_chunk_coord()
            and not chunk_manager.prepare_player_entry(next_coord)
        ):
            velocity.x = 0.0
            velocity.z = 0.0
            return false
    move_and_slide()
    if chunk_manager != null and chunk_manager.initialized:
        return chunk_manager.update_player_world_position(global_position)
    return true
