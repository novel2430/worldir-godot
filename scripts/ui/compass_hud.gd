class_name CompassHUD
extends Control

const CARDINALS := [
    {"label": "N", "bearing": 0.0},
    {"label": "E", "bearing": PI * 0.5},
    {"label": "S", "bearing": PI},
    {"label": "W", "bearing": PI * 1.5},
]
const HEADING_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

@export var player_path := NodePath("../../Player")
@export var heading_smoothing := 12.0

var _player: Node3D = null
var _heading := 0.0

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _player = get_node_or_null(player_path) as Node3D
    if _player != null:
        _heading = _player_heading()
    queue_redraw()

func _process(delta: float) -> void:
    if _player == null:
        _player = get_node_or_null(player_path) as Node3D
        if _player == null:
            return
    var blend := 1.0 - exp(-heading_smoothing * maxf(delta, 0.0))
    _heading = lerp_angle(_heading, _player_heading(), blend)
    queue_redraw()

func heading_degrees() -> float:
    return wrapf(rad_to_deg(_heading), 0.0, 360.0)

func _player_heading() -> float:
    var forward := -_player.global_transform.basis.z.normalized()
    return wrapf(atan2(forward.x, -forward.z), 0.0, TAU)

func _draw() -> void:
    var center := Vector2(size.x * 0.5, 38.0)
    var font := ThemeDB.fallback_font
    draw_circle(center, 36.0, Color(0.035, 0.045, 0.055, 0.76))
    draw_arc(center, 31.5, 0.0, TAU, 48, Color(0.88, 0.91, 0.90, 0.48), 1.2, true)

    for tick_index in range(16):
        var bearing := float(tick_index) / 16.0 * TAU
        var relative := bearing - _heading
        var direction := Vector2(sin(relative), -cos(relative))
        var inner_radius := 27.0 if tick_index % 4 == 0 else 29.0
        draw_line(
            center + direction * inner_radius,
            center + direction * 32.0,
            Color(0.88, 0.91, 0.90, 0.72),
            1.0,
            true
        )

    for cardinal: Dictionary in CARDINALS:
        var relative: float = float(cardinal.bearing) - _heading
        var direction := Vector2(sin(relative), -cos(relative))
        var label_position := center + direction * 21.0 + Vector2(-8.0, 4.5)
        var color := (
            Color(0.94, 0.43, 0.32, 1.0)
            if cardinal.label == "N"
            else Color(0.91, 0.93, 0.92, 0.92)
        )
        draw_string(
            font,
            label_position,
            String(cardinal.label),
            HORIZONTAL_ALIGNMENT_CENTER,
            16.0,
            12,
            color
        )

    var marker := PackedVector2Array([
        center + Vector2(0.0, -36.0),
        center + Vector2(-3.5, -30.0),
        center + Vector2(3.5, -30.0),
    ])
    draw_colored_polygon(marker, Color(1.0, 0.76, 0.30, 1.0))

    var degrees := heading_degrees()
    var heading_index := int(round(degrees / 45.0)) % HEADING_NAMES.size()
    var heading_text := "%s · %03d°" % [HEADING_NAMES[heading_index], int(round(degrees)) % 360]
    draw_string(
        font,
        Vector2(0.0, 84.0),
        heading_text,
        HORIZONTAL_ALIGNMENT_CENTER,
        size.x,
        12,
        Color(0.94, 0.95, 0.93, 0.92)
    )
