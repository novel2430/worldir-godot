class_name RegionProfileCatalog
extends RefCounted

# Step 01 establishes the fixed OwenG profile shape and prototype policy seam.
# Visual values are intentionally descriptive placeholders; later steps own the
# continuous terrain, surface, lighting, atmosphere and transition realization.
const PROFILES := {
	"coastal_forest": {
		"terrain": {
			"character": "gentle",
			"macro_scale": 0.52,
			"detail_scale": 0.20,
			"rolling_scale": 0.25,
			"height_limit": 2.15,
		},
		"surface": {
			"layers": ["ground.grass", "ground.dirt", "ground.white_sand"],
			"primary_color": Color(0.16, 0.245, 0.105),
			"secondary_color": Color(0.29, 0.205, 0.105),
			"accent_color": Color(0.61, 0.57, 0.39),
		},
		"distribution_visual_policy": {
			"tree": ["oweng_tree_birch", "oweng_tree_pine"],
			"grass": ["oweng_grass_01"],
			"shrub": ["oweng_shrub_01", "oweng_shrub_02"],
			"rock": ["oweng_rock_09", "oweng_rock_boulder"],
			"fallen_log": ["oweng_fallen_log"],
		},
		"entity_prototype_policy": {
			"rowboat": ["oweng_rowboat_weathered"],
			"tent": ["oweng_tent_canvas"],
			"cabin": ["oweng_cabin_coastal"],
		},
		"path_style": {
			"style": "forest_footpath",
			"color": Color(0.31, 0.225, 0.115),
			"edge_color": Color(0.21, 0.16, 0.085),
		},
		"lighting": {
			"character": "clear_warm",
			"sun_color": Color(1.0, 0.86, 0.69),
			"sun_energy": 0.90,
			"ambient_color": Color(0.73, 0.79, 0.70),
			"ambient_energy": 0.88,
			"sky_top_color": Color(0.18, 0.38, 0.58),
			"sky_horizon_color": Color(0.72, 0.79, 0.76),
			"sky_ground_color": Color(0.28, 0.31, 0.28),
		},
		"atmosphere": {
			"character": "coastal_clear",
			"fog_density": 0.0065,
			"fog_color": Color(0.73, 0.79, 0.74),
			"snowfall": 0.0,
			"cloud_amount": 0.28,
			"cloud_opacity": 0.48,
			"cloud_color": Color(0.92, 0.94, 0.91),
			"cloud_shadow_color": Color(0.50, 0.55, 0.56),
			"cloud_scale": 1.10,
			"cloud_speed": 0.0025,
			"sun_strength": 0.85,
		},
		"transition": {"character": "soft_natural"},
	},
	"research_base": {
		"terrain": {
			"character": "controlled",
			"macro_scale": 0.08,
			"detail_scale": 0.02,
			"rolling_scale": 0.015,
			"height_limit": 1.15,
		},
		"surface": {
			"layers": ["ground.gray_gravel", "ground.dirt"],
			"primary_color": Color(0.29, 0.30, 0.285),
			"secondary_color": Color(0.245, 0.215, 0.175),
			"accent_color": Color(0.38, 0.39, 0.37),
		},
		"distribution_visual_policy": {
			"tree": ["oweng_tree_pine"],
			"grass": ["oweng_grass_01"],
			"shrub": ["oweng_shrub_02"],
			"rock": ["oweng_rock_07", "oweng_rock_09", "oweng_rock_boulder"],
		},
		"entity_prototype_policy": {
			"research_station": ["oweng_research_station"],
			"radar_tower": ["oweng_radar_tower"],
			"radiation_warning_sign": ["oweng_radiation_warning_sign"],
			"tidal_danger_sign": ["oweng_tidal_danger_sign"],
			"cargo_truck": ["oweng_cargo_truck"],
			"crate": ["oweng_crate_real"],
		},
		"path_style": {
			"style": "industrial_gravel",
			"color": Color(0.34, 0.35, 0.34),
			"edge_color": Color(0.23, 0.235, 0.225),
		},
		"lighting": {
			"character": "cold_desaturated",
			"sun_color": Color(0.78, 0.82, 0.84),
			"sun_energy": 0.72,
			"ambient_color": Color(0.61, 0.65, 0.66),
			"ambient_energy": 0.70,
			"sky_top_color": Color(0.30, 0.37, 0.43),
			"sky_horizon_color": Color(0.60, 0.63, 0.62),
			"sky_ground_color": Color(0.26, 0.28, 0.29),
		},
		"atmosphere": {
			"character": "light_fog",
			"fog_density": 0.0105,
			"fog_color": Color(0.62, 0.65, 0.64),
			"snowfall": 0.0,
			"cloud_amount": 0.64,
			"cloud_opacity": 0.68,
			"cloud_color": Color(0.73, 0.76, 0.77),
			"cloud_shadow_color": Color(0.36, 0.40, 0.43),
			"cloud_scale": 1.34,
			"cloud_speed": 0.0040,
			"sun_strength": 0.42,
		},
		"transition": {"character": "controlled"},
	},
	"snow_forest": {
		"terrain": {
			"character": "rolling",
			"macro_scale": 0.72,
			"detail_scale": 0.34,
			"rolling_scale": 1.16,
			"height_limit": 4.20,
		},
		"surface": {
			"layers": ["ground.white_sand", "ground.gray_gravel"],
			"primary_color": Color(0.78, 0.82, 0.84),
			"secondary_color": Color(0.43, 0.46, 0.47),
			"accent_color": Color(0.65, 0.68, 0.67),
		},
		"distribution_visual_policy": {
			"tree": ["oweng_tree_pine", "oweng_tree_fir"],
			"shrub": ["oweng_shrub_01", "oweng_shrub_02"],
			"rock": ["oweng_rock_07", "oweng_rock_boulder"],
		},
		"entity_prototype_policy": {
			"cabin": ["oweng_cabin_snow"],
			"maritime_memorial": ["oweng_maritime_memorial"],
			"ruined_archway": ["oweng_ruined_archway"],
			"bunker": ["oweng_bunker"],
			"concrete_wall": ["oweng_concrete_wall"],
		},
		"path_style": {
			"style": "compacted_snow",
			"color": Color(0.69, 0.73, 0.75),
			"edge_color": Color(0.49, 0.52, 0.53),
		},
		"lighting": {
			"character": "cold",
			"sun_color": Color(0.70, 0.79, 0.90),
			"sun_energy": 0.62,
			"ambient_color": Color(0.59, 0.68, 0.76),
			"ambient_energy": 0.76,
			"sky_top_color": Color(0.31, 0.40, 0.52),
			"sky_horizon_color": Color(0.68, 0.72, 0.74),
			"sky_ground_color": Color(0.49, 0.55, 0.61),
		},
		"atmosphere": {
			"character": "fog_snow",
			"fog_density": 0.0170,
			"fog_color": Color(0.72, 0.77, 0.81),
			"snowfall": 1.0,
			"cloud_amount": 0.82,
			"cloud_opacity": 0.74,
			"cloud_color": Color(0.76, 0.82, 0.89),
			"cloud_shadow_color": Color(0.44, 0.51, 0.60),
			"cloud_scale": 1.56,
			"cloud_speed": 0.0060,
			"sun_strength": 0.24,
		},
		"transition": {"character": "soft_snow"},
	},
}

func has_profile(region_type: String) -> bool:
	return PROFILES.has(region_type)

func get_profile(region_type: String) -> Dictionary:
	var profile: Dictionary = PROFILES.get(region_type, {})
	return profile.duplicate(true)
