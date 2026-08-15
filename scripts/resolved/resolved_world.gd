class_name ResolvedWorld
extends Resource

var seed: int = 1
var world_bounds: Rect2 = Rect2(-80.0, -80.0, 160.0, 160.0)
# Kept as Resource here so headless script entry points do not depend on the
# editor-generated global-class cache for the backend-only ResolvedTerrain.
var terrain: Resource = null
var waters: Array = []
var regions: Array = []
var networks: Array = []
var entities: Array = []
var distributions: Array = []
var decorations: Array = []
var warnings: PackedStringArray = PackedStringArray()
var errors: PackedStringArray = PackedStringArray()

func find_region(object_id: String) -> ResolvedRegion:
    for item in regions:
        if item.id == object_id:
            return item
    return null

func find_network(object_id: String) -> ResolvedNetwork:
    for item in networks:
        if item.id == object_id:
            return item
    return null

func find_entity(object_id: String) -> ResolvedEntity:
    for item in entities:
        if item.id == object_id:
            return item
    return null

func find_distribution(object_id: String) -> ResolvedDistribution:
    for item in distributions:
        if item.id == object_id:
            return item
    return null

func find_decoration(decoration_id: String) -> ResolvedDecoration:
    for item in decorations:
        if item.id == decoration_id:
            return item
    return null

func find_water(water_id: String) -> Resource:
    for item in waters:
        if item.id == water_id:
            return item
    return null
