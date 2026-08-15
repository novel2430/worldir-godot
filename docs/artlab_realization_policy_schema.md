# ArtLab Realization Policy v1 字段与版本规则

实时配置位于 `data/configs/artlab_realization_policy.json`，机器可读约束位于
`data/configs/artlab_realization_policy.schema.json`。配置中的值也是当前默认值；
`RealizationPolicy.DEFAULT_VALUES` 保留同值的兼容副本。

## 版本与加载

- v1 唯一支持的 format 是 `worldir-godot-artlab-realization-policy-v1`。
- 缺失文件、非法 JSON、非对象根或未知 format 会原子回退到完整内置默认值。
- v1 中缺失字段使用内置默认值；类型错误字段单独回退并产生 warning；未知字段忽略
  并产生 warning。
- 只增加可安全忽略、且有内置默认值的字段时可以保留 v1。删除字段、重命名字段、
  改变单位/含义或改变确定性语义时必须发布新 format。
- 新 format 必须显式加入 loader 的支持列表并提供迁移测试；旧 loader 对新 format
  必须完整回退，不能部分解释。
- Policy 在 `RealizationPolicy` 构造时读取一次，之后是不可变快照。本项目不做运行中
  热重载；调参后重新启动生成进程，以免 Same Inputs 在同一进程内随磁盘状态漂移。
- `fingerprint()` 是解析并补齐默认值后的 SHA-256。诊断、截图和性能报告必须记录该
  fingerprint，确保结果能够绑定到精确 Policy 快照。

## 单位与范围

| 字段组 | 单位/范围 | 消费位置 |
|---|---|---|
| `terrain.geometry.*_m` | 世界米，非负或正数 | `TerrainResolver` 高度与振幅 |
| `terrain.geometry.*_frequency` | 每世界米的采样频率，必须大于 0 | `TerrainResolver` 确定性噪声 |
| `*_strength`、`*_multiplier` | 归一化 `[0,1]` | 地形、材质或候选接受权重 |
| `terrain.influences.*_m` | 世界米 | Region、道路、建筑、海岸过渡 |
| `coast_*_offset_m` | 相对 sea level 的有符号世界米 | 海岸地形塑形 |
| `surface.palette.*` | 线性 RGB/RGBA，每通道 `[0,1]` | `SceneRuntime` terrain shader |
| `surface.variation_*` | 非负颜色倍率 | terrain shader 细节变化 |
| `surface.roughness/specular` | `[0,1]` | terrain shader 材质参数 |
| `target_area_per_candidate_m2` | 每候选平方米，必须大于 0 | `ForestDresser` 候选预算 |
| `legacy_area_per_instance_m2` | 兼容回退平方米，必须大于 0 | v1 旧规则回退 |
| `acceptance_probability` | `[0,1]` | 候选数量预算 |
| `cap` | 正整数/Region | dressing 层实例上限 |
| `cluster_count` | 非负整数/Region | 聚类中心数量 |
| `cluster_radius_m` | 世界米 | 聚类采样半径 |
| `road_clearance_m` | 世界米 | 网络硬净距 |
| `edge_profiles.*_*_m` | 从 Region 数学边缘向内的世界米 | dressing 边缘权重 |
| `building_clearing.*_radius_m` | 世界米 | 建筑周围 dressing 衰减 |
| `footprint_*_scale` | TSCN 实测 footprint 的无量纲倍数 | 不同尺寸建筑 clearing |
| `network_corridors.*.outer_extra_width_m` | 从道路边缘向外的世界米 | 平滑道路/路径植被走廊 |

## 跨字段约束

- `forest_height_limit_m >= base_height_limit_m`。
- 所有 start/end 对必须满足 `start < end`。
- `minimum_outer_radius_m > minimum_inner_radius_m`。
- `footprint_outer_scale > footprint_inner_scale`。
- `variation_min <= variation_max`。
- Region role 和 `dressing.region_types` 只能引用现有合法 World IR Region 类型。
- dressing layers 固定为 `dead_tree / rock / bush / grass`；这不会扩展 World IR 类型。

`tools/validate_project.py` 在提交前检查这些跨字段关系；真实 Godot 测试覆盖运行时
fallback、未知版本、局部字段缺失、错误类型与 fingerprint 稳定性。
