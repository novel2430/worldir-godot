class_name PromptPanel
extends PanelContainer

@onready var input: LineEdit = %PromptInput
@onready var status: Label = %StatusLabel
@onready var send_button: Button = %SendButton
@onready var clearing_button: Button = %ClearingButton
@onready var coordinator: WorldCoordinator = get_tree().current_scene.get_node("WorldCoordinator")

func _ready() -> void:
    send_button.pressed.connect(_submit)
    input.text_submitted.connect(func(_text): _submit())
    clearing_button.pressed.connect(func(): coordinator.create_demo_clearing())
    coordinator.status_changed.connect(func(message): status.text = message)
    coordinator.busy_changed.connect(func(value): send_button.disabled = value)

func _submit() -> void:
    coordinator.submit_prompt(input.text)
    input.clear()
