class_name PromptPanel
extends PanelContainer

const DEBUG_HEIGHT := 172.0
const COMPACT_HEIGHT := 62.0
const COMPACT_GAP_HEIGHT := 96.0

@export var debug_mode := true:
    set(value):
        debug_mode = value
        if is_node_ready():
            _apply_debug_mode()

@onready var input: LineEdit = %PromptInput
@onready var status: Label = %StatusLabel
@onready var send_button: Button = %SendButton
@onready var clearing_button: Button = %ClearingButton
@onready var debug_header: Control = %DebugHeader
@onready var debug_details: Control = %DebugDetails
@onready var gap_panel: PanelContainer = %GapPanel
@onready var gap_label: Label = %GapLabel
@onready var coordinator: WorldCoordinator = get_node_or_null("../../WorldCoordinator") as WorldCoordinator

var _last_error := ""

func _ready() -> void:
    _apply_debug_mode()
    send_button.pressed.connect(_submit)
    input.text_submitted.connect(func(_text): _submit())
    if coordinator == null:
        _show_error("IR GAP · WorldCoordinator is unavailable")
        send_button.disabled = true
        return
    clearing_button.pressed.connect(func(): coordinator.create_demo_clearing())
    coordinator.status_changed.connect(_on_status_changed)
    coordinator.busy_changed.connect(_on_busy_changed)

func _submit() -> void:
    var prompt := input.text.strip_edges()
    if coordinator == null or prompt.is_empty():
        return
    coordinator.submit_prompt(prompt)
    input.clear()

func _on_busy_changed(value: bool) -> void:
    send_button.disabled = value
    send_button.text = "Working…" if value else "Apply"

func _on_status_changed(message: String) -> void:
    status.text = message
    if _is_error_message(message):
        _show_error(message)
    else:
        _last_error = ""
        gap_panel.visible = false
        _update_height()

func _is_error_message(message: String) -> bool:
    var normalized := message.to_lower()
    return (
        normalized.begins_with("ir gap")
        or normalized.begins_with("compiler error")
        or normalized.begins_with("invalid compiler")
        or normalized.begins_with("backend rejected")
        or normalized.contains("failed")
    )

func _show_error(message: String) -> void:
    _last_error = message
    gap_label.text = "IR GAP"
    gap_panel.visible = not debug_mode
    _update_height()

func _apply_debug_mode() -> void:
    debug_header.visible = debug_mode
    debug_details.visible = debug_mode
    gap_panel.visible = not debug_mode and not _last_error.is_empty()
    _update_height()

func _update_height() -> void:
    var target_height := DEBUG_HEIGHT
    if not debug_mode:
        target_height = COMPACT_GAP_HEIGHT if gap_panel.visible else COMPACT_HEIGHT
    offset_top = offset_bottom - target_height
