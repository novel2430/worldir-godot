class_name SpatialPayloadStore
extends Node

var payloads: Dictionary = {}

func put(fact_id: String, payload: Dictionary) -> void:
    payloads[fact_id] = payload.duplicate(true)

func get_payload(fact_id: String) -> Dictionary:
    return payloads.get(fact_id, {})

func erase(fact_id: String) -> void:
    payloads.erase(fact_id)
