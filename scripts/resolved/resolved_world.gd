class_name ResolvedWorld
extends Resource

var seed: int = 1
# Procedural placement may use a Chunk-scoped seed while terrain continues to
# sample the one global world seed. V0 callers leave both values identical.
var realization_seed: int = 1
var environment: Dictionary = {}
# WorldBackend assigns this from the live backend configuration before lowering.
var world_bounds: Rect2 = Rect2()
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
