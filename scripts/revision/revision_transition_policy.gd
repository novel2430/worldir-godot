class_name RevisionTransitionPolicy
extends RefCounted

const FULL_REWRITE := "FULL_REWRITE"
const LIGHT_REBASE := "LIGHT_REBASE"
const SILENT := "SILENT"

# The 3x3 window has no genuinely distant cardinal ring. Treat cardinal
# previews as visually prominent and diagonal previews as the cheaper/far tier.
const VISIBLE_PREVIEW_MANHATTAN_DISTANCE := 1

func transaction_mode() -> String:
	return FULL_REWRITE

func streaming_mode() -> String:
	return SILENT

func preview_mode(
	current_coord: Vector2i,
	preview_coord: Vector2i,
	is_materialized: bool,
	is_visible: bool
) -> String:
	if not is_materialized or not is_visible:
		return SILENT
	var delta := preview_coord - current_coord
	var manhattan_distance := absi(delta.x) + absi(delta.y)
	return (
		LIGHT_REBASE
		if manhattan_distance <= VISIBLE_PREVIEW_MANHATTAN_DISTANCE
		else SILENT
	)
