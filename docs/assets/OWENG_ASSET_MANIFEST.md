# Asset Manifest — ArtLab V1

记录日期：2026-08-14。第三方资源均来自 Poly Haven；其官方资产许可页声明 HDRI、纹理和 3D 模型均以 CC0 发布：<https://polyhaven.com/license>。即使 CC0 不要求署名，本项目仍记录作者与来源。

## User-provided Generated Assets

- Source type：User-provided Generated Asset
- 原始来源：用户提供的 `lux3d_reconstruction.zip`。`assets/generated/source/` 不纳入 Git；V2 必要 GLB 的恢复清单和相对路径见 `docs/ASSET_SETUP.md`。
- 原件大小：116,618,599 bytes
- 原件处理：只读检查；未修改原 ZIP。
- 项目内位置：`assets/generated/source/<group>/`
- 授权说明：用户提供；不视作第三方 CC0。用途仅为本地 ArtLab 导入、尺度、材质与组合测试。
- Godot 结果：17/17 GLB 加载成功；每个文件为 1 个 MeshInstance、1 个 material slot、2 张内嵌纹理。
- 机器可读报告：`reports/generated_asset_inspection.tsv`

| ID | 原始文件名 | Group | Bytes | AABB W×H×D (m) | Wrapper scale | 备注 |
| --- | --- | --- | ---: | --- | ---: | --- |
| generated_01 | blue_roof_coastal_cottage.glb | forest_seaside | 4,165,872 | 2.8647×0.8500×1.0739 | 1.57 | 实际渲染内容是 rowboat；源命名/内容错配 |
| generated_02 | blue_white_wooden_rowboat_2712846_2.glb | forest_seaside | 4,471,712 | 0.4036×0.2789×1.1684 | 3.85 | 原始尺度明显偏小 |
| generated_03 | canvas_ridge_tent.glb | forest_seaside | 3,961,540 | 3.0962×2.2000×3.4119 | 1.00 | 尺度合理 |
| generated_04 | rustic_wooden_cabin.glb | forest_seaside | 4,252,536 | 5.4319×6.5000×7.7751 | 1.00 | 尺度合理，当前组合效果最佳 |
| generated_05 | weathered_wooden_rowboat_2712647_2.glb | forest_seaside | 4,294,452 | 1.1574×0.3428×0.4295 | 3.90 | 原始尺度明显偏小 |
| generated_06 | abandoned_radar_tower_2711741_2.glb | industrial | 5,245,476 | 10.4334×18.0000×8.9791 | 1.00 | 尺度合理；网格细节从远处易闪烁 |
| generated_07 | abandoned_soviet_research_station_2711371_2.glb | industrial | 5,639,488 | 20.0746×20.0000×16.1039 | 1.00 | 最大资产；Gallery 需较大间距 |
| generated_08 | rusted_radiation_warning_sign_2712064_2.glb | industrial | 4,243,736 | 0.7396×1.0266×0.1011 | 2.15 | 原始尺度偏小 |
| generated_09 | rusted_soviet_4x4_cargo_truck_2712264_2.glb | industrial | 5,260,284 | 0.4797×0.4416×1.1133 | 4.50 | 原始尺度明显偏小 |
| generated_10 | rusted_soviet_6x6_cargo_truck.glb | industrial | 5,486,008 | 2.9142×2.8500×7.9765 | 1.00 | 尺度合理 |
| generated_11 | rusted_tidal_danger_sign_2711885_2.glb | industrial | 4,533,288 | 1.1685×2.2000×0.4700 | 1.00 | 尺度合理 |
| generated_12 | snow_log_cabin_with_porch.glb | snow_forest | 4,808,868 | 5.3986×6.5000×8.0194 | 1.00 | 尺度合理 |
| generated_13 | snow_maritime_memorial_monument.glb | snow_forest | 4,845,764 | 2.4118×7.0000×2.4198 | 1.00 | 尺度合理 |
| generated_14 | snow_ruined_archway_2709821_2.glb | snow_forest | 4,772,624 | 6.2103×6.0000×2.5861 | 1.00 | 尺度合理 |
| generated_15 | snow_ruined_concrete_bunker_2709399_2.glb | snow_forest | 4,270,980 | 4.0662×4.5000×4.5525 | 1.00 | 尺度合理 |
| generated_16 | snow_ruined_concrete_wall_2708823_2.glb | snow_forest | 4,795,340 | 7.0286×5.5000×1.3835 | 1.00 | GLB 正常；随包 preview PNG 损坏 |
| generated_17 | snow_steep_roof_log_cabin.glb | snow_forest | 4,561,764 | 5.6444×6.5000×6.7393 | 1.00 | 尺度合理 |

Wrapper scale 是非破坏性 uniform scale；原始 GLB 保持不变。朝向保持源文件方向，测试场景可从多角度自由查看。

## Third-party CC0 Models（Poly Haven，1K GLTF）

所有条目的 License 为 CC0，原始格式为 GLTF + BIN + JPG PBR maps；下载页面为 `https://polyhaven.com/a/<asset_id>`。

| Asset ID | 名称 / 类别 | 作者 / 来源组织 | 下载页面 | 项目内路径 | 用途 / 备注 |
| --- | --- | --- | --- | --- | --- |
| quiver_tree_02 | Quiver Tree 02 / Tree | Dario Barresi, Rico Cilliers / Poly Haven | <https://polyhaven.com/a/quiver_tree_02> | `assets/vegetation/trees/quiver_tree_02/` | Beach/稀疏树；形似棕榈，不适合温带密林 |
| searsia_lucida | Searsia Lucida / Tree | James Ray Cock, Jenelle van Heerden / Poly Haven | <https://polyhaven.com/a/searsia_lucida> | `assets/vegetation/trees/searsia_lucida/` | 中型阔叶树 |
| pine_sapling_small | Pine Sapling Small / Tree | Rob Tuytel, Rico Cilliers / Poly Haven | <https://polyhaven.com/a/pine_sapling_small> | `assets/vegetation/trees/pine_sapling_small/` | Forest Edge 小松树；选择 small 版避免巨大几何 |
| fir_sapling_medium | Fir Sapling Medium / Tree | Poly Haven | <https://polyhaven.com/a/fir_sapling_medium> | `assets/vegetation/trees/fir_sapling_medium/` | Snow Forest 限量成熟冷杉层；主场景预算 18 株，控制高面数成本 |
| shrub_01 | Shrub 01 / Bush | Rico Cilliers / Poly Haven | <https://polyhaven.com/a/shrub_01> | `assets/vegetation/bushes/shrub_01/` | 灌木散布 |
| shrub_02 | Shrub 02 / Bush | Rico Cilliers / Poly Haven | <https://polyhaven.com/a/shrub_02> | `assets/vegetation/bushes/shrub_02/` | 灌木散布 |
| shrub_03 | Shrub 03 / Bush | Rico Cilliers / Poly Haven | <https://polyhaven.com/a/shrub_03> | `assets/vegetation/bushes/shrub_03/` | 灌木散布 |
| grass_medium_01 | Grass Medium 01 / Ground plant | Rob Tuytel, Rico Cilliers / Poly Haven | <https://polyhaven.com/a/grass_medium_01> | `assets/vegetation/grass/grass_medium_01/` | Gallery 真实草簇；大面积草另用 MultiMesh |
| grass_medium_02 | Grass Medium 02 / Ground plant | Rico Cilliers / Poly Haven | <https://polyhaven.com/a/grass_medium_02> | `assets/vegetation/grass/grass_medium_02/` | Gallery 真实草簇 |
| rock_07 | Rock 07 / Rock | Jenelle van Heerden / Poly Haven | <https://polyhaven.com/a/rock_07> | `assets/rocks/rock_07/` | 通用岩石散布 |
| rock_09 | Rock 09 / Rock | Jenelle van Heerden / Poly Haven | <https://polyhaven.com/a/rock_09> | `assets/rocks/rock_09/` | 通用岩石散布 |
| rock_moss_set_01 | Rock Moss Set 01 / Rock | Kless Gyzen / Poly Haven | <https://polyhaven.com/a/rock_moss_set_01> | `assets/rocks/rock_moss_set_01/` | 草地/森林苔岩 |
| namaqualand_boulder_04 | Namaqualand Boulder 04 / Rock | Jenelle van Heerden / Poly Haven | <https://polyhaven.com/a/namaqualand_boulder_04> | `assets/rocks/namaqualand_boulder_04/` | Beach/草地较大岩石 |
| dead_tree_trunk | Dead Tree Trunk / Fallen log | Rob Tuytel / Poly Haven | <https://polyhaven.com/a/dead_tree_trunk> | `assets/props/logs/dead_tree_trunk/` | 倒木 / forest edge prop |
| wooden_crate_01 | Wooden Crate 01 / Prop | Poly Haven | <https://polyhaven.com/a/wooden_crate_01> | `assets/props/interactive/wooden_crate_01/` | V1 `Interactive` 分类示例；未来 inspect/container hook，无玩法逻辑 |

未下载更大的 `fir_tree_01` 与 `pine_tree_01`；本轮以限量 `fir_sapling_medium` 提供成熟冷杉层，避免进一步增加运行成本。

## Third-party CC0 Models（OpenGameArt）

| Asset | Creator / Contributors | Source / License | Local Path | 用途 / 备注 |
| --- | --- | --- | --- | --- |
| Tree (`tree-24`) | musdasch；Yughues、para | <https://opengameart.org/content/tree-24> / CC0 | `assets/vegetation/trees/birch_oga/` | 成熟 Broadleaf 基底；ArtLab 运行时用白灰树皮与深色横纹建立 Birch 视觉身份 |

## Third-party CC0 PBR Textures（Poly Haven，2K JPG）

每套保留 Diffuse、OpenGL Normal 与 Roughness 三张图。

| Asset ID | 名称 / 类别 | 作者 | 下载页面 | 项目内路径 | 用途 |
| --- | --- | --- | --- | --- | --- |
| grass_path_2 | Grass Path 2 / Grass ground | Rob Tuytel | <https://polyhaven.com/a/grass_path_2> | `assets/terrain/grass_path_2/` | Grass swatch 与 terrain grass |
| brown_mud_dry | Brown Mud Dry / Dirt | Rob Tuytel | <https://polyhaven.com/a/brown_mud_dry> | `assets/terrain/brown_mud_dry/` | Dirt swatch 与单体测试地面 |
| aerial_beach_01 | Aerial Beach 01 / Sand | Rob Tuytel | <https://polyhaven.com/a/aerial_beach_01> | `assets/terrain/aerial_beach_01/` | Sand swatch 与 Beach |
| rocky_terrain | Rocky Terrain / Rock ground | Amal Kumar | <https://polyhaven.com/a/rocky_terrain> | `assets/terrain/rocky_terrain/` | Rock swatch 与陡坡混合 |

## Third-party CC0 HDRIs（Poly Haven，1K HDR）

| Asset ID | 名称 / 类型 | 作者 | 下载页面 | 项目内路径 | 用途 |
| --- | --- | --- | --- | --- | --- |
| meadow | Meadow / HDRI | Sergej Majboroda | <https://polyhaven.com/a/meadow> | `assets/environment/meadow_1k.hdr` | Neutral Daylight；Gallery、Generated、Grassland |
| blaubeuren_hillside | Blaubeuren Hillside / HDRI | Andreas Mischok | <https://polyhaven.com/a/blaubeuren_hillside> | `assets/environment/blaubeuren_hillside_1k.hdr` | Warm / high-contrast comparison；Beach |
