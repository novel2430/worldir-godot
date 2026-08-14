class_name RuntimeBindingResolver
extends RefCounted

func resolve_domain(
    binding: Dictionary,
    spatial_payloads: Dictionary,
    world_bounds: Rect2,
    default_size: Vector2 = Vector2(12.0, 12.0)
) -> Rect2:
    if binding.is_empty():
        return Rect2()
    var payload := _payload_rect(binding, spatial_payloads, default_size)
    if not payload.has_area():
        return Rect2()
    var mode := String(binding.get("placement", "inside"))
    match mode:
        "inside":
            return _clamp_rect(payload, world_bounds)
        "at":
            return _clamp_rect(Rect2(payload.get_center() - default_size * 0.5, default_size), world_bounds)
        "near":
            var gap := 4.0
            var preferred := Rect2(
                Vector2(payload.end.x + gap, payload.get_center().y - default_size.y * 0.5),
                default_size
            )
            if preferred.end.x > world_bounds.end.x:
                preferred.position.x = payload.position.x - gap - default_size.x
            return _clamp_rect(preferred, world_bounds)
    return Rect2()

func payload_center(binding: Dictionary, spatial_payloads: Dictionary) -> Vector2:
    var payload := _payload_rect(binding, spatial_payloads, Vector2(2.0, 2.0))
    return payload.get_center() if payload.has_area() else Vector2.ZERO

func _payload_rect(binding: Dictionary, spatial_payloads: Dictionary, default_size: Vector2) -> Rect2:
    var fact_id := String(binding.get("runtime_fact_id", ""))
    var payload_value: Variant = spatial_payloads.get(fact_id, {})
    if typeof(payload_value) != TYPE_DICTIONARY:
        return Rect2()
    var payload: Dictionary = payload_value
    if payload.has("aabb2") and typeof(payload["aabb2"]) == TYPE_DICTIONARY:
        var a: Dictionary = payload["aabb2"]
        return Rect2(
            Vector2(float(a.get("x", 0.0)), float(a.get("z", 0.0))),
            Vector2(maxf(0.0, float(a.get("w", 0.0))), maxf(0.0, float(a.get("d", 0.0))))
        )
    if payload.has("center") and typeof(payload["center"]) == TYPE_DICTIONARY:
        var c: Dictionary = payload["center"]
        var center := Vector2(float(c.get("x", 0.0)), float(c.get("z", 0.0)))
        return Rect2(center - default_size * 0.5, default_size)
    return Rect2()

func _clamp_rect(rect: Rect2, bounds: Rect2) -> Rect2:
    var size := Vector2(minf(rect.size.x, bounds.size.x), minf(rect.size.y, bounds.size.y))
    var pos := rect.position
    pos.x = clampf(pos.x, bounds.position.x, bounds.end.x - size.x)
    pos.y = clampf(pos.y, bounds.position.y, bounds.end.y - size.y)
    return Rect2(pos, size)
