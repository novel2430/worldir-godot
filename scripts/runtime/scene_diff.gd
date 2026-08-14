class_name SceneDiff
extends RefCounted

func summarize(old_world: ResolvedWorld, new_world: ResolvedWorld) -> Dictionary:
    return {
        "regions": [old_world.regions.size() if old_world else 0, new_world.regions.size()],
        "networks": [old_world.networks.size() if old_world else 0, new_world.networks.size()],
        "entities": [old_world.entities.size() if old_world else 0, new_world.entities.size()],
        "distributions": [old_world.distributions.size() if old_world else 0, new_world.distributions.size()],
    }
