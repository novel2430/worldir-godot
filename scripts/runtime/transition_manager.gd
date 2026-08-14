class_name TransitionManager
extends Node

# V0 keeps transition intentionally small: candidate is prepared off-tree, then swapped atomically.
# This class is the extension point for dissolve/growth/fade transitions later.
func transition(_old_root: Node3D, _candidate: Node3D) -> bool:
    return true
