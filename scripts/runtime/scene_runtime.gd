class_name SceneRuntime
extends Node

const SceneTransitionScript = preload("res://scripts/runtime/scene_transition.gd")
const ENVIRONMENT_BLEND_SPEED := 1.65
const GROUND_TEXTURE_SIZE := 1024
const GROUND_TEXTURES := {
    "grass": {
        "albedo": "res://assets/oweng/terrain/grass_path_2/grass_path_2_diff_2k.jpg",
        "normal": "res://assets/oweng/terrain/grass_path_2/grass_path_2_nor_gl_2k.jpg",
        "roughness": "res://assets/oweng/terrain/grass_path_2/grass_path_2_rough_2k.jpg",
    },
    "dirt": {
        "albedo": "res://assets/oweng/terrain/brown_mud_dry/brown_mud_dry_diff_2k.jpg",
        "normal": "res://assets/oweng/terrain/brown_mud_dry/brown_mud_dry_nor_gl_2k.jpg",
        "roughness": "res://assets/oweng/terrain/brown_mud_dry/brown_mud_dry_rough_2k.jpg",
    },
    "white_sand": {
        "albedo": "res://assets/oweng/terrain/aerial_beach_01/aerial_beach_01_diff_2k.jpg",
        "normal": "res://assets/oweng/terrain/aerial_beach_01/aerial_beach_01_nor_gl_2k.jpg",
        "roughness": "res://assets/oweng/terrain/aerial_beach_01/aerial_beach_01_rough_2k.jpg",
    },
    "gray_gravel": {
        "albedo": "res://assets/oweng/terrain/rocky_terrain/rocky_terrain_diff_2k.jpg",
        "normal": "res://assets/oweng/terrain/rocky_terrain/rocky_terrain_nor_gl_2k.jpg",
        "roughness": "res://assets/oweng/terrain/rocky_terrain/rocky_terrain_rough_2k.jpg",
    },
}

var road_builder := RoadBuilder.new()
var scene_diff := SceneDiff.new()
var scene_transition: RefCounted = SceneTransitionScript.new()
var region_profiles := RegionProfileCatalog.new()
var _terrain_material_cache: ShaderMaterial = null
var _water_material_cache: ShaderMaterial = null
var _foam_material_cache: ShaderMaterial = null
var active_resolved: ResolvedWorld = null
var current_environment_weights := Color(1.0, 0.0, 0.0, 0.0)
var _visual_profiles: Dictionary = {}
var _world_environment: WorldEnvironment = null
var _sun: DirectionalLight3D = null
var _player: Node3D = null
var _snowfall: GPUParticles3D = null

func _ready() -> void:
    for region_type in ["coastal_forest", "research_base", "snow_forest"]:
        _visual_profiles[region_type] = region_profiles.get_profile(region_type)
    _world_environment = get_node_or_null("../WorldEnvironment") as WorldEnvironment
    _sun = get_node_or_null("../Sun") as DirectionalLight3D
    _player = get_node_or_null("../Player") as Node3D
    if _world_environment != null and _sun != null and _player != null:
        _snowfall = _create_snowfall()
        add_child(_snowfall)

func _process(delta: float) -> void:
    if active_resolved == null or _player == null:
        return
    update_visual_environment(_player.global_position, delta)

func build_candidate(resolved: ResolvedWorld, catalog: PrototypeCatalog) -> Node3D:
    var root := Node3D.new()
    root.name = "CandidateWorld"
    root.set_meta("resolved_world", resolved)
    var terrain_layer := Node3D.new(); terrain_layer.name = "Terrain"; root.add_child(terrain_layer)
    var water_layer := Node3D.new(); water_layer.name = "Water"; root.add_child(water_layer)
    var regions := Node3D.new(); regions.name = "Regions"; root.add_child(regions)
    var networks := Node3D.new(); networks.name = "Networks"; root.add_child(networks)
    var entities := Node3D.new(); entities.name = "Entities"; root.add_child(entities)
    var distributions := Node3D.new(); distributions.name = "Distributions"; root.add_child(distributions)
    var decorations := Node3D.new(); decorations.name = "Decorations"; root.add_child(decorations)

    if resolved.terrain != null:
        terrain_layer.add_child(_build_terrain(resolved.terrain))
    for water in resolved.waters:
        water_layer.add_child(_build_water(water))
    for region in resolved.regions:
        regions.add_child(_build_region(region, resolved.terrain == null))
    for network in resolved.networks:
        networks.add_child(road_builder.build(network, resolved.terrain))
    for entity in resolved.entities:
        var node := _instantiate(entity.prototype_id, catalog)
        if node == null:
            root.free(); return null
        node.name = _safe_name(entity.id)
        node.transform = entity.transform
        entities.add_child(node)
    for distribution in resolved.distributions:
        var group := Node3D.new(); group.name = _safe_name(distribution.id); distributions.add_child(group)
        for instance_data in distribution.instances:
            var node := _instantiate(String(instance_data.prototype_id), catalog)
            if node == null:
                root.free(); return null
            node.name = _safe_name(String(instance_data.id))
            node.transform = instance_data.transform
            group.add_child(node)
    for decoration in resolved.decorations:
        var group := Node3D.new(); group.name = _safe_name(decoration.id); decorations.add_child(group)
        for instance_data in decoration.instances:
            var node := _instantiate(String(instance_data.prototype_id), catalog)
            if node == null:
                root.free(); return null
            node.name = _safe_name(String(instance_data.id))
            node.transform = instance_data.transform
            group.add_child(node)
    return root

func commit_candidate(world_root: Node3D, candidate: Node3D) -> void:
    for child in world_root.get_children():
        world_root.remove_child(child)
        child.queue_free()
    world_root.add_child(candidate)
    candidate.name = "GeneratedWorld"
    _activate_visual_world(candidate.get_meta("resolved_world", null) as ResolvedWorld)

func transition_candidate(
    world_root: Node3D,
    candidate: Node3D,
    old_world: ResolvedWorld,
    new_world: ResolvedWorld
) -> Dictionary:
    var active_root := world_root.get_node_or_null("GeneratedWorld") as Node3D
    if active_root == null or old_world == null:
        commit_candidate(world_root, candidate)
        return scene_diff.compare(old_world, new_world)
    var patch := scene_diff.compare(old_world, new_world)
    await scene_transition.apply(active_root, candidate, patch, new_world)
    _activate_visual_world(new_world)
    return patch

func _activate_visual_world(resolved: ResolvedWorld) -> void:
    active_resolved = resolved
    if resolved == null or resolved.terrain == null or _player == null:
        return
    current_environment_weights = region_weights_at(_player.global_position)
    _apply_visual_environment(current_environment_weights)

func region_weights_at(position: Vector3) -> Color:
    if active_resolved == null or active_resolved.terrain == null:
        return Color(1.0, 0.0, 0.0, 0.0)
    return active_resolved.terrain.sample_region_weights(Vector2(position.x, position.z))

func update_visual_environment(position: Vector3, delta: float) -> void:
    var target := region_weights_at(position)
    var blend := 1.0 - exp(-maxf(0.0, delta) * ENVIRONMENT_BLEND_SPEED)
    current_environment_weights = current_environment_weights.lerp(target, blend)
    var total := (
        current_environment_weights.r
        + current_environment_weights.g
        + current_environment_weights.b
    )
    if total > 0.0001:
        current_environment_weights.r /= total
        current_environment_weights.g /= total
        current_environment_weights.b /= total
    _apply_visual_environment(current_environment_weights)
    if _snowfall != null:
        _snowfall.global_position = position + Vector3(0.0, 8.0, 0.0)

func _apply_visual_environment(weights: Color) -> void:
    if _world_environment == null or _world_environment.environment == null or _sun == null:
        return
    var coastal: Dictionary = _visual_profiles.get("coastal_forest", {})
    var research: Dictionary = _visual_profiles.get("research_base", {})
    var snow: Dictionary = _visual_profiles.get("snow_forest", {})
    var coastal_light: Dictionary = coastal.get("lighting", {})
    var research_light: Dictionary = research.get("lighting", {})
    var snow_light: Dictionary = snow.get("lighting", {})
    var coastal_air: Dictionary = coastal.get("atmosphere", {})
    var research_air: Dictionary = research.get("atmosphere", {})
    var snow_air: Dictionary = snow.get("atmosphere", {})

    var environment := _world_environment.environment
    _sun.light_color = _weighted_color(
        coastal_light.sun_color, research_light.sun_color, snow_light.sun_color, weights
    )
    _sun.light_energy = _weighted_float(
        coastal_light.sun_energy, research_light.sun_energy, snow_light.sun_energy, weights
    )
    environment.ambient_light_color = _weighted_color(
        coastal_light.ambient_color,
        research_light.ambient_color,
        snow_light.ambient_color,
        weights
    )
    environment.ambient_light_energy = _weighted_float(
        coastal_light.ambient_energy,
        research_light.ambient_energy,
        snow_light.ambient_energy,
        weights
    )
    environment.fog_light_color = _weighted_color(
        coastal_air.fog_color, research_air.fog_color, snow_air.fog_color, weights
    )
    environment.fog_density = _weighted_float(
        coastal_air.fog_density, research_air.fog_density, snow_air.fog_density, weights
    )
    if environment.sky != null and environment.sky.sky_material is ProceduralSkyMaterial:
        var sky_material := environment.sky.sky_material as ProceduralSkyMaterial
        sky_material.sky_top_color = _weighted_color(
            coastal_light.sky_top_color,
            research_light.sky_top_color,
            snow_light.sky_top_color,
            weights
        )
        sky_material.sky_horizon_color = _weighted_color(
            coastal_light.sky_horizon_color,
            research_light.sky_horizon_color,
            snow_light.sky_horizon_color,
            weights
        )
    if _snowfall != null:
        var snow_intensity := _weighted_float(
            coastal_air.snowfall, research_air.snowfall, snow_air.snowfall, weights
        )
        _snowfall.amount_ratio = clampf(snow_intensity, 0.0, 1.0)
        _snowfall.emitting = snow_intensity > 0.01
        _snowfall.visible = snow_intensity > 0.005

func _weighted_color(a: Color, b: Color, c: Color, weights: Color) -> Color:
    var result := a * weights.r + b * weights.g + c * weights.b
    result.a = 1.0
    return result

func _weighted_float(a: float, b: float, c: float, weights: Color) -> float:
    return a * weights.r + b * weights.g + c * weights.b

func _create_snowfall() -> GPUParticles3D:
    var particles := GPUParticles3D.new()
    particles.name = "Snowfall"
    particles.amount = 520
    particles.amount_ratio = 0.0
    particles.lifetime = 3.4
    particles.randomness = 0.48
    particles.visibility_aabb = AABB(Vector3(-18.0, -13.0, -18.0), Vector3(36.0, 26.0, 36.0))
    particles.emitting = false
    particles.visible = false

    var process_material := ParticleProcessMaterial.new()
    process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    process_material.emission_box_extents = Vector3(14.0, 7.0, 14.0)
    process_material.direction = Vector3(0.08, -1.0, 0.04)
    process_material.spread = 12.0
    process_material.initial_velocity_min = 3.2
    process_material.initial_velocity_max = 5.8
    process_material.gravity = Vector3(0.15, -0.65, 0.05)
    particles.process_material = process_material

    var flake_material := StandardMaterial3D.new()
    flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
    flake_material.albedo_color = Color(0.92, 0.96, 1.0, 0.82)
    var flake := QuadMesh.new()
    flake.size = Vector2(0.055, 0.16)
    flake.material = flake_material
    particles.draw_pass_1 = flake
    return particles

func _instantiate(prototype_id: String, catalog: PrototypeCatalog) -> Node3D:
    return catalog.instantiate_prototype(prototype_id) as Node3D

func _build_terrain(terrain: Resource) -> StaticBody3D:
    var body := StaticBody3D.new()
    body.name = "WorldSurface"
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "TerrainMesh"
    mesh_instance.mesh = _terrain_mesh(terrain)
    mesh_instance.material_override = _terrain_material()
    body.add_child(mesh_instance)
    var collision := CollisionShape3D.new()
    collision.name = "TerrainCollision"
    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(mesh_instance.mesh.get_faces())
    collision.shape = shape
    body.add_child(collision)
    return body

func _terrain_mesh(terrain: Resource) -> ArrayMesh:
    var vertex_count: int = terrain.grid_size * terrain.grid_size
    var vertices := PackedVector3Array()
    var normals := PackedVector3Array()
    var tangents := PackedFloat32Array()
    var colors := PackedColorArray()
    var uvs := PackedVector2Array()
    var uv2s := PackedVector2Array()
    vertices.resize(vertex_count)
    normals.resize(vertex_count)
    tangents.resize(vertex_count * 4)
    colors.resize(vertex_count)
    uvs.resize(vertex_count)
    uv2s.resize(vertex_count)
    var step_x: float = terrain.world_bounds.size.x / float(terrain.grid_size - 1)
    var step_z: float = terrain.world_bounds.size.y / float(terrain.grid_size - 1)
    for z_index in range(terrain.grid_size):
        for x_index in range(terrain.grid_size):
            var index: int = z_index * terrain.grid_size + x_index
            var x: float = terrain.world_bounds.position.x + float(x_index) * step_x
            var z: float = terrain.world_bounds.position.y + float(z_index) * step_z
            vertices[index] = Vector3(x, terrain.heights[index], z)
            colors[index] = terrain.surface_masks[index]
            uvs[index] = Vector2(
                float(x_index) / float(terrain.grid_size - 1),
                float(z_index) / float(terrain.grid_size - 1)
            )
            uv2s[index] = Vector2(terrain.shore_wetness[index], 0.0)
    for z_index in range(terrain.grid_size):
        for x_index in range(terrain.grid_size):
            var index: int = z_index * terrain.grid_size + x_index
            var left: float = terrain.heights[z_index * terrain.grid_size + maxi(0, x_index - 1)]
            var right: float = terrain.heights[z_index * terrain.grid_size + mini(terrain.grid_size - 1, x_index + 1)]
            var back: float = terrain.heights[maxi(0, z_index - 1) * terrain.grid_size + x_index]
            var front: float = terrain.heights[mini(terrain.grid_size - 1, z_index + 1) * terrain.grid_size + x_index]
            var x_span := step_x * (1.0 if x_index == 0 or x_index == terrain.grid_size - 1 else 2.0)
            var z_span := step_z * (1.0 if z_index == 0 or z_index == terrain.grid_size - 1 else 2.0)
            normals[index] = Vector3((left - right) / x_span, 1.0, (back - front) / z_span).normalized()
            var tangent := Vector3(1.0, -normals[index].x / maxf(normals[index].y, 0.001), 0.0).normalized()
            tangents[index * 4] = tangent.x
            tangents[index * 4 + 1] = tangent.y
            tangents[index * 4 + 2] = tangent.z
            tangents[index * 4 + 3] = -1.0

    var indices := PackedInt32Array()
    for z_index in range(terrain.grid_size - 1):
        for x_index in range(terrain.grid_size - 1):
            var a: int = z_index * terrain.grid_size + x_index
            var b: int = a + 1
            var c: int = a + terrain.grid_size
            var d: int = c + 1
            # Clockwise in XZ is Godot's upward-facing front side.
            indices.append_array(PackedInt32Array([a, b, d, a, d, c]))
    var arrays := []
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX] = vertices
    arrays[Mesh.ARRAY_NORMAL] = normals
    arrays[Mesh.ARRAY_TANGENT] = tangents
    arrays[Mesh.ARRAY_COLOR] = colors
    arrays[Mesh.ARRAY_TEX_UV] = uvs
    arrays[Mesh.ARRAY_TEX_UV2] = uv2s
    arrays[Mesh.ARRAY_INDEX] = indices
    var mesh := ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
    return mesh

func _terrain_material() -> ShaderMaterial:
    if _terrain_material_cache != null:
        return _terrain_material_cache
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec3 coastal_primary;
uniform vec3 coastal_secondary;
uniform vec3 coastal_accent;
uniform vec3 research_primary;
uniform vec3 research_secondary;
uniform vec3 research_accent;
uniform vec3 snow_primary;
uniform vec3 snow_secondary;
uniform vec3 snow_accent;

uniform sampler2D grass_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D grass_roughness : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D dirt_roughness : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_roughness : repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_albedo : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel_roughness : repeat_enable, filter_linear_mipmap_anisotropic;

varying vec3 world_position;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
               mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec4 influence = COLOR;
    vec3 weights = max(influence.rgb, vec3(0.0));
    weights /= max(weights.r + weights.g + weights.b, 0.0001);
    float broad_noise = value_noise(world_position.xz * 0.035);
    float detail_noise = value_noise(world_position.xz * 0.11 + vec2(17.0, 41.0));
    float fine_noise = value_noise(world_position.xz * 0.29 + vec2(71.0, 13.0));

    vec2 grass_uv = world_position.xz / 4.8;
    vec2 dirt_uv = world_position.xz / 4.1 + vec2(0.31, 0.17);
    vec2 sand_uv = world_position.xz / 5.8 + vec2(0.63, 0.24);
    vec2 gravel_uv = world_position.xz / 3.7 + vec2(0.12, 0.71);
    vec3 grass_color = texture(grass_albedo, grass_uv).rgb;
    vec3 dirt_color = texture(dirt_albedo, dirt_uv).rgb;
    vec3 sand_color = texture(sand_albedo, sand_uv).rgb;
    vec3 gravel_color = texture(gravel_albedo, gravel_uv).rgb;

    float coastal_dirt = mix(0.18, 0.34, smoothstep(0.48, 0.82, detail_noise));
    float coastal_sand = mix(0.035, 0.105, smoothstep(0.67, 0.90, broad_noise));
    float coastal_grass = 1.0 - coastal_dirt - coastal_sand;
    float research_dirt = mix(0.20, 0.34, smoothstep(0.58, 0.86, detail_noise));
    float research_gravel = 1.0 - research_dirt;
    float snow_gravel = mix(0.13, 0.29, smoothstep(0.62, 0.88, detail_noise));
    float snow_sand = 1.0 - snow_gravel;

    vec4 layer_weights = vec4(
        weights.r * coastal_grass,
        weights.r * coastal_dirt + weights.g * research_dirt,
        weights.r * coastal_sand + weights.b * snow_sand,
        weights.g * research_gravel + weights.b * snow_gravel
    );
    layer_weights /= max(dot(layer_weights, vec4(1.0)), 0.0001);

    vec3 surface = (
        grass_color * layer_weights.x
        + dirt_color * layer_weights.y
        + sand_color * layer_weights.z
        + gravel_color * layer_weights.w
    );
    vec3 profile_tint = (
        coastal_primary * weights.r
        + research_primary * weights.g
        + snow_primary * weights.b
    );
    surface = mix(surface, profile_tint * 1.55, 0.10);
    vec3 local_path = (
        dirt_color * weights.r
        + gravel_color * weights.g
        + mix(sand_color, gravel_color, 0.24) * weights.b
    );
    surface = mix(surface, local_path, influence.a * 0.46);
    surface *= mix(0.96, 1.04, fine_noise);

    vec3 grass_n = texture(grass_normal, grass_uv).rgb * 2.0 - 1.0;
    vec3 dirt_n = texture(dirt_normal, dirt_uv).rgb * 2.0 - 1.0;
    vec3 sand_n = texture(sand_normal, sand_uv).rgb * 2.0 - 1.0;
    vec3 gravel_n = texture(gravel_normal, gravel_uv).rgb * 2.0 - 1.0;
    vec3 detail_normal = normalize(
        grass_n * layer_weights.x
        + dirt_n * layer_weights.y
        + sand_n * layer_weights.z
        + gravel_n * layer_weights.w
    );
    float pbr_roughness = (
        texture(grass_roughness, grass_uv).r * layer_weights.x
        + texture(dirt_roughness, dirt_uv).r * layer_weights.y
        + texture(sand_roughness, sand_uv).r * layer_weights.z
        + texture(gravel_roughness, gravel_uv).r * layer_weights.w
    );

    ALBEDO = surface;
    NORMAL_MAP = detail_normal * 0.5 + 0.5;
    NORMAL_MAP_DEPTH = 0.62;
    ROUGHNESS = clamp(pbr_roughness, 0.58, 1.0);
    SPECULAR = 0.12;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    var coastal_surface: Dictionary = region_profiles.get_profile("coastal_forest").surface
    var research_surface: Dictionary = region_profiles.get_profile("research_base").surface
    var snow_surface: Dictionary = region_profiles.get_profile("snow_forest").surface
    material.set_shader_parameter("coastal_primary", coastal_surface.primary_color)
    material.set_shader_parameter("coastal_secondary", coastal_surface.secondary_color)
    material.set_shader_parameter("coastal_accent", coastal_surface.accent_color)
    material.set_shader_parameter("research_primary", research_surface.primary_color)
    material.set_shader_parameter("research_secondary", research_surface.secondary_color)
    material.set_shader_parameter("research_accent", research_surface.accent_color)
    material.set_shader_parameter("snow_primary", snow_surface.primary_color)
    material.set_shader_parameter("snow_secondary", snow_surface.secondary_color)
    material.set_shader_parameter("snow_accent", snow_surface.accent_color)
    for ground_type in GROUND_TEXTURES.keys():
        var texture_paths: Dictionary = GROUND_TEXTURES[ground_type]
        for channel in ["albedo", "normal", "roughness"]:
            var uniform_prefix := "sand" if ground_type == "white_sand" else String(ground_type)
            material.set_shader_parameter(
                "%s_%s" % [uniform_prefix, channel],
                _load_ground_texture(String(texture_paths[channel]))
            )
    material.set_meta("oweng_pbr_ground_paths", GROUND_TEXTURES.duplicate(true))
    _terrain_material_cache = material
    return _terrain_material_cache

func _load_ground_texture(path: String) -> ImageTexture:
    # Read source pixels directly so the runtime and tests do not depend on
    # editor-generated .import remaps for the migrated OwenG textures.
    var image := Image.new()
    var error := image.load(path)
    if error != OK:
        push_error("Failed to load OwenG ground texture '%s': %s" % [path, error_string(error)])
        return null
    if image.get_width() > GROUND_TEXTURE_SIZE or image.get_height() > GROUND_TEXTURE_SIZE:
        image.resize(GROUND_TEXTURE_SIZE, GROUND_TEXTURE_SIZE, Image.INTERPOLATE_LANCZOS)
    if not image.has_mipmaps():
        image.generate_mipmaps()
    return ImageTexture.create_from_image(image)

func _build_water(water: Resource) -> Node3D:
    var root := Node3D.new()
    root.name = _safe_name(water.id)
    var water_mesh := MeshInstance3D.new()
    water_mesh.name = "WaterMesh"
    water_mesh.mesh = _water_mesh(water)
    water_mesh.material_override = _water_material()
    water_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(water_mesh)
    var foam := MeshInstance3D.new()
    foam.name = "ShoreFoam"
    foam.mesh = _foam_mesh(water)
    foam.material_override = _foam_material()
    foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    root.add_child(foam)
    return root

func _water_mesh(water: Resource) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var depth_segments := 12
    for shore_index in range(water.shoreline.size() - 1):
        var a_shore: Vector2 = water.shoreline[shore_index]
        var b_shore: Vector2 = water.shoreline[shore_index + 1]
        var a_boundary := _water_boundary_point(water, a_shore)
        var b_boundary := _water_boundary_point(water, b_shore)
        for depth_index in range(depth_segments):
            var near_t := float(depth_index) / float(depth_segments)
            var far_t := float(depth_index + 1) / float(depth_segments)
            var a_near := a_shore.lerp(a_boundary, near_t)
            var b_near := b_shore.lerp(b_boundary, near_t)
            var a_far := a_shore.lerp(a_boundary, far_t)
            var b_far := b_shore.lerp(b_boundary, far_t)
            _water_triangle(st, a_near, b_far, b_near, water, near_t, far_t, near_t)
            _water_triangle(st, a_near, a_far, b_far, water, near_t, far_t, far_t)
    return st.commit()

func _water_triangle(
    st: SurfaceTool,
    a: Vector2,
    b: Vector2,
    c: Vector2,
    water: Resource,
    depth_a: float,
    depth_b: float,
    depth_c: float
) -> void:
    var a3 := Vector3(a.x, water.sea_level, a.y)
    var b3 := Vector3(b.x, water.sea_level, b.y)
    var c3 := Vector3(c.x, water.sea_level, c.y)
    if (b3 - a3).cross(c3 - a3).dot(Vector3.DOWN) < 0.0:
        _water_vertex(st, a, water, depth_a)
        _water_vertex(st, c, water, depth_c)
        _water_vertex(st, b, water, depth_b)
    else:
        _water_vertex(st, a, water, depth_a)
        _water_vertex(st, b, water, depth_b)
        _water_vertex(st, c, water, depth_c)

func _water_vertex(st: SurfaceTool, point: Vector2, water: Resource, depth: float) -> void:
    st.set_normal(Vector3.UP)
    st.set_color(Color(1.0 - smoothstep(0.0, 0.58, depth), 0.0, 0.0, 1.0))
    st.add_vertex(Vector3(point.x, water.sea_level, point.y))

func _water_boundary_point(water: Resource, shore_point: Vector2) -> Vector2:
    var result := shore_point
    if absf(water.seaward_direction.x) > 0.5:
        result.x = water.polygon[water.polygon.size() - 1].x
    else:
        result.y = water.polygon[water.polygon.size() - 1].y
    return result

func _foam_mesh(water: Resource) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var foam_width := 0.58
    var height: float = water.sea_level + 0.045
    for index in range(water.shoreline.size() - 1):
        var a: Vector2 = water.shoreline[index]
        var b: Vector2 = water.shoreline[index + 1]
        var a_sea: Vector2 = a + water.seaward_direction * foam_width
        var b_sea: Vector2 = b + water.seaward_direction * foam_width
        _flat_triangle(st, Vector3(a.x, height, a.y), Vector3(b_sea.x, height, b_sea.y), Vector3(b.x, height, b.y))
        _flat_triangle(st, Vector3(a.x, height, a.y), Vector3(a_sea.x, height, a_sea.y), Vector3(b_sea.x, height, b_sea.y))
    return st.commit()

func _flat_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    if (b - a).cross(c - a).dot(Vector3.DOWN) < 0.0:
        var swap := b
        b = c
        c = swap
    for point in [a, b, c]:
        st.set_normal(Vector3.UP)
        st.add_vertex(point)

func _water_material() -> ShaderMaterial:
    if _water_material_cache != null:
        return _water_material_cache
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

varying vec3 world_position;

void vertex() {
    vec3 source_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float phase_a = source_world.x * 0.14 + TIME * 0.65;
    float phase_b = source_world.z * 0.18 - TIME * 0.50;
    float phase_c = (source_world.x + source_world.z) * 0.095 + TIME * 0.38;
    float wave = sin(phase_a) * 0.055;
    wave += sin(phase_b) * 0.042;
    wave += sin(phase_c) * 0.025;
    VERTEX.y += wave;
    float slope_x = cos(phase_a) * 0.055 * 0.14 + cos(phase_c) * 0.025 * 0.095;
    float slope_z = cos(phase_b) * 0.042 * 0.18 + cos(phase_c) * 0.025 * 0.095;
    NORMAL = normalize(vec3(-slope_x, 1.0, -slope_z));
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float variation = sin(world_position.x * 0.08 + world_position.z * 0.055) * 0.5 + 0.5;
    float moving_ripple = sin(world_position.x * 0.26 + world_position.z * 0.11 + TIME * 0.90) * 0.56;
    moving_ripple += sin(-world_position.x * 0.08 + world_position.z * 0.31 - TIME * 0.72) * 0.44;
    float crest = smoothstep(0.38, 0.88, moving_ripple);
    float trough = smoothstep(0.42, 0.92, -moving_ripple);
    float fresnel = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 3.0);
    vec3 deep_water = mix(vec3(0.045, 0.235, 0.34), vec3(0.06, 0.315, 0.39), variation);
    vec3 shallow_water = vec3(0.16, 0.47, 0.46);
    vec3 surface = mix(deep_water, shallow_water, COLOR.r * 0.72);
    surface *= mix(1.0, 1.16, crest);
    surface *= mix(1.0, 0.90, trough);
    surface = mix(surface, vec3(0.20, 0.48, 0.50), fresnel * 0.22);
    ALBEDO = surface;
    ROUGHNESS = mix(0.66, 0.49, crest);
    SPECULAR = 0.36;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    _water_material_cache = material
    return _water_material_cache

func _foam_material() -> ShaderMaterial:
    if _foam_material_cache != null:
        return _foam_material_cache
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float variation = sin(world_position.x * 0.35 + world_position.z * 0.23) * 0.5 + 0.5;
    ALBEDO = mix(vec3(0.60, 0.69, 0.62), vec3(0.68, 0.76, 0.67), variation);
    ROUGHNESS = 0.95;
    SPECULAR = 0.08;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    _foam_material_cache = material
    return _foam_material_cache

func _build_region(region: ResolvedRegion, render_surface: bool = true) -> Node3D:
    var root: Node3D = Node3D.new(); root.name = _safe_name(region.id)
    if not render_surface or region.polygon.size() < 3: return root
    var mesh_instance: MeshInstance3D = MeshInstance3D.new()
    var height: float = _region_height(region.semantic_type)
    var feather_width := _region_feather_width(region.semantic_type)
    mesh_instance.mesh = _build_region_mesh(region.polygon, height, feather_width)
    if mesh_instance.mesh == null:
        return root
    var material: StandardMaterial3D = StandardMaterial3D.new()
    material.albedo_color = _region_color(region.semantic_type)
    material.roughness = 1.0
    if feather_width > 0.0:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        material.vertex_color_use_as_albedo = true
        material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
    mesh_instance.material_override = material
    root.add_child(mesh_instance)
    return root

func _build_region_mesh(polygon: PackedVector2Array, height: float, feather_width: float) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    if feather_width <= 0.0:
        var indices := Geometry2D.triangulate_polygon(polygon)
        if indices.is_empty():
            return null
        for raw_index in indices:
            _region_vertex(st, polygon[int(raw_index)], height, Color.WHITE)
        return st.commit()

    var center := Vector2.ZERO
    for point in polygon:
        center += point
    center /= float(polygon.size())
    var inner := PackedVector2Array()
    for point in polygon:
        inner.append(point.move_toward(center, minf(feather_width, point.distance_to(center) * 0.25)))
    var inner_indices := Geometry2D.triangulate_polygon(inner)
    if inner_indices.is_empty():
        return null
    for raw_index in inner_indices:
        _region_vertex(st, inner[int(raw_index)], height, Color.WHITE)

    # The outer strip fades into the shared ground. Keep a tiny residual alpha
    # so the transition remains legible without revealing a razor-straight seam.
    var edge_color := Color(1.0, 1.0, 1.0, 0.04)
    for index in range(polygon.size()):
        var next := (index + 1) % polygon.size()
        _region_triangle(st, polygon[index], polygon[next], inner[next], height, edge_color, edge_color, Color.WHITE)
        _region_triangle(st, polygon[index], inner[next], inner[index], height, edge_color, Color.WHITE, Color.WHITE)
    return st.commit()

func _region_triangle(
    st: SurfaceTool,
    a: Vector2,
    b: Vector2,
    c: Vector2,
    height: float,
    color_a: Color,
    color_b: Color,
    color_c: Color
) -> void:
    var a3 := Vector3(a.x, height, a.y)
    var b3 := Vector3(b.x, height, b.y)
    var c3 := Vector3(c.x, height, c.y)
    # Godot considers clockwise triangles front-facing. Normalize every strip
    # triangle so its visible side stays upward regardless of polygon winding.
    if (b3 - a3).cross(c3 - a3).dot(Vector3.DOWN) < 0.0:
        _region_vertex(st, a, height, color_a)
        _region_vertex(st, c, height, color_c)
        _region_vertex(st, b, height, color_b)
    else:
        _region_vertex(st, a, height, color_a)
        _region_vertex(st, b, height, color_b)
        _region_vertex(st, c, height, color_c)

func _region_vertex(st: SurfaceTool, p: Vector2, height: float, color: Color) -> void:
    st.set_normal(Vector3.UP)
    st.set_color(color)
    st.add_vertex(Vector3(p.x, height, p.y))

func _region_feather_width(kind: String) -> float:
    match kind:
        "coastal_forest", "research_base", "snow_forest": return 3.2
        _: return 0.0

func _region_height(kind: String) -> float:
    match kind:
        "coastal_forest": return 0.016
        "research_base": return 0.022
        "snow_forest": return 0.018
        _: return 0.018

func _region_color(kind: String) -> Color:
    match kind:
        "coastal_forest": return Color(0.17, 0.245, 0.145)
        "research_base": return Color(0.285, 0.27, 0.205)
        "snow_forest": return Color(0.72, 0.75, 0.76)
        _: return Color(0.22, 0.235, 0.18)

func _safe_name(value: String) -> String:
    return value.replace(":", "_").replace("/", "_")
