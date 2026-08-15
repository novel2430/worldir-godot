# WorldIR × OwenG — Godot 最终目标与冻结架构总纲

> **状态**：Final Implementation Baseline  
> **用途**：后续 Godot Coding Agent、Backend 实现、素材接入、测试与验收的共同总纲  
> **适用基线**：World IR V2 / Runtime Context V1 / Compile Result V1 / Godot V0.85 之后的 OwenG-aligned 路线  
> **核心原则**：API Contract 不变；World IR JSON shape 基本不变；收窄 semantic vocabulary，并让 Godot 以 Region Environment Archetype 驱动 OwenG 风格的连续视觉世界。

---

## 0. 文档优先级与冻结范围

从本阶段开始，本文是 **Godot OwenG-aligned 路线的冻结架构基线**。

如果旧文档中的示例 vocabulary 与本文冲突，例如旧的：

```text
forest
coast
town
village
graveyard
road
```

则对于当前 Godot 实现阶段，以本文为准。

旧 World IR V2 中以下结构继续有效，不修改：

```text
Region
Network
Entity
Distribution

placement.anchor
placement.relations[]
Network.topology
Distribution.population
runtime_bindings
runtime_fact_ops
```

也就是说：

> **我们没有重做 World IR 的结构语言，而是冻结一个更小、完全围绕 OwenG 已验证视觉能力的 active semantic set。**

---

# 1. 最终产品目标

当前阶段的最终目标不是建设一个通用、无限扩展的 World Language，也不是实现多 Chunk streaming 系统。

最终要做的是：

> **用户通过自然语言持续编辑一个大型、连续、可游玩的 Godot 世界。世界由少量高完成度 Region Environment Archetype 组成，Region 之间像 OwenG 一样自然渐变；World IR 明确控制世界中实际存在的 Region / Path / Entity / Distribution，而 Godot Backend 负责把这些语义稳定 lower 成具体地形、材质、模型、数量、坐标与动画变化。**

目标体验包括：

1. 世界是一个连续空间，而不是三个 Scene 的硬切换；
2. 玩家可以从 coastal forest 走入 research base，再走入 snow forest；
3. 地形、地表材质、植被风格、路径外观、光照、雾、降雪等会连续变化；
4. Entity 仍然是离散的重要对象，不进行荒谬的跨类型 morph；
5. 用户可以继续通过 Prompt 修改世界，例如：
   - “雪森林里的石头少一点”；
   - “这个区域的树多一点”；
   - “把 cabin 移到 path 附近”；
6. Server 返回新的完整 IR；Godot 重新 lower，并通过 Scene Diff / Transition 把 Old World 平滑变成 New World；
7. 同一个 IR + Seed + Backend Config 应尽量产生稳定、可复现的世界。

---

# 2. 冻结的总体架构

```text
User Prompt
    │
    ▼
LLM Compiler Server
    │
    │  POST /v1/compile
    ▼
World IR V2
├── regions[]
├── networks[]
├── entities[]
└── distributions[]
    │
    ▼
Godot World Backend
├── Region Lowering
├── Owner Region Resolution
├── Region Profile Resolution
├── Network Lowering
├── Prototype / Asset Resolution
├── Entity Placement
├── Distribution Population Lowering
└── Terrain / Surface Resolution
    │
    ▼
Resolved World
    │
    ▼
Scene Diff + Transition
    │
    ▼
Playable Continuous World
```

系统边界永久保持：

```text
IR
→ WHAT exists / semantic intent

Godot Backend
→ WHERE exactly / HOW MANY exactly / WHICH asset / HOW it is rendered

Scene Runtime
→ instantiate / remove / move / animate
```

---

# 3. 世界模型：一个 World，不引入 Semantic Chunk

## 3.1 不采用 multi-chunk semantic model

当前阶段不引入：

```text
chunk_id
chunk_coord
active chunk
dormant chunk
lookahead chunk
LLM prefetch chunk
chunk streaming semantics
```

World IR 描述的是一个完整的、大型 World Frame。

世界内部由多个 Region 组成：

```text
World
├── Region A: coastal_forest
├── Region B: research_base
├── Region C: snow_forest
└── Path / Entity / Distribution
```

Region 是环境变化的语义单位。

如果未来为了性能把 Terrain 切成 tile / chunk，这只能是 **Godot 内部 rendering optimization**，不能改变 World IR、Region ownership 或 Compiler 心智模型。

因此固定原则是：

> **Chunk 可以未来成为实现细节，但不能成为当前 World IR 的语义。**

---

# 4. Active Semantic Vocabulary

## 4.1 Region.type

第一版只支持三个 Environment Archetype：

```text
coastal_forest
research_base
snow_forest
```

不支持泛化：

```text
forest
coast
town
village
graveyard
swamp
desert
```

这里 `Region.type` 不再表示普通区域标签，而表示：

> **一个完整的 Environment Archetype。**

例如：

```text
snow_forest
→ snow terrain/surface policy
→ cold lighting
→ fog
→ snowfall
→ snow-compatible prototype policy
```

这些视觉实现全部属于 Godot RegionProfile，不进入 IR。

---

## 4.2 Network.type

第一版收窄为：

```text
path
```

Path 可以穿越多个 Region。

同一条 Path 的语义保持不变，但视觉可以随所在 Region 变化：

```text
coastal_forest
→ forest footpath

research_base
→ gravel / industrial path

snow_forest
→ compacted snow trail
```

Network 不要求 owner Region，也不受 “exactly inside one Region” 限制。

---

## 4.3 Entity.type

第一版 Entity vocabulary 以 OwenG 已有真实模型能力为边界，冻结为：

```text
rowboat
tent
cabin
research_station
radar_tower
warning_sign
cargo_truck
crate
maritime_memorial
ruined_archway
bunker
concrete_wall
```

其中一个 semantic type 可以根据 owner Region 选择不同模型 variant。

例如：

```text
cabin + coastal_forest
→ rustic coastal cabin variant

cabin + snow_forest
→ snow cabin variant
```

`warning_sign`、`cargo_truck` 等也允许 Backend 在同一 semantic type 下选择 OwenG 已有 variant。

---

## 4.4 Distribution.type

第一版冻结为：

```text
tree
grass
shrub
rock
```

Distribution 表示真正存在于 IR 中的重复 population。

具体树种、草模型、灌木 variant、岩石 variant 不进入 IR。

例如：

```text
IR:
type = tree
inside = snow_region

Godot:
owner Region = snow_forest
→ pine / fir prototype policy
```

---

# 5. Region Ownership Invariants

这是当前 Godot Backend 必须强制执行的新 invariant。

## 5.1 Region 不允许 nesting

非法：

```text
snow_forest inside research_base
```

Region 之间可以：

```text
anchor
direction_of
near
```

但不能形成 Region containment hierarchy。

---

## 5.2 Entity 必须 exactly inside 一个 Region

每个 Entity 必须存在且只存在一个：

```json
{"type":"inside","target":"some_region_id"}
```

非法情况：

```text
Entity 没有 owner Region
Entity inside 两个 Region
Entity inside 非 Region target
```

---

## 5.3 Distribution 必须 exactly inside 一个 Region

同样，每个 Distribution 必须且只能拥有一个 owner Region。

例如：

```text
rocks
→ inside snow_area
→ owner_region = snow_area
→ owner_region.type = snow_forest
```

---

## 5.4 Owner Region 是 Backend asset resolution 的核心上下文

Entity / Distribution 的资产选择固定采用：

```text
(semantic_type, owner_region.type)
→ prototype policy
```

例如：

```text
(tree, coastal_forest)
→ birch / pine

(tree, snow_forest)
→ pine / fir

(cabin, coastal_forest)
→ rustic cabin

(cabin, snow_forest)
→ snow cabin
```

---

# 6. 最重要的责任边界：IR 决定存在，Profile 决定表现

固定规则：

```text
IR
→ WHAT exists

RegionProfile
→ HOW it looks
```

因此 RegionProfile **禁止偷偷生成 semantic objects**。

例如：

```text
snow_forest
```

不能自动意味着 Godot 自己 spawn：

```text
cabin
tree
rock
```

如果这些对象存在，它们必须真的出现在 IR：

```text
entities[]
distributions[]
```

RegionProfile 只能决定：

```text
snow_forest + tree
→ pine/fir

snow_forest + rock
→ cold rock variant

snow_forest + cabin
→ snow cabin
```

这条规则防止 Compiler 与 Godot 双重生成对象。

---

# 7. RegionProfile：Backend-only 固定设计

RegionProfile 是 Godot Backend 的正式组件，但 **永远不进入 World IR**。

概念结构固定为：

```text
RegionProfile
├── terrain
├── surface
├── distribution_visual_policy
├── entity_prototype_policy
├── path_style
├── lighting
├── atmosphere
└── transition
```

---

## 7.1 terrain

负责：

```text
height character
relief amplitude
noise character
local flattening policy
```

例如：

```text
coastal_forest
→ gentle terrain

research_base
→ controlled / buildable terrain

snow_forest
→ rolling terrain
```

Profile 只能控制地形表现，不能新增 Region 或 object。

---

## 7.2 surface

第一版尽量复用 OwenG 已有地面素材：

```text
ground.grass
ground.dirt
ground.white_sand
ground.gray_gravel
```

Profile 定义：

```text
texture layer weights
tint
desaturation
roughness / material tuning
```

目标对应：

```text
coastal_forest
→ grass / dirt / beach-like white sand

research_base
→ gray gravel / dirt / desaturated industrial ground

snow_forest
→ snow-like white ground / gravel / exposed rock
```

允许继续使用 OwenG 当前以 white-sand texture 模拟 snow 的视觉 cheat。

---

## 7.3 distribution_visual_policy

它只决定已有 Distribution 的 visual realization，例如：

```text
(tree, coastal_forest)
→ birch-heavy + pine

(tree, snow_forest)
→ pine + fir

(grass, coastal_forest)
→ grass asset variants

(shrub, coastal_forest)
→ shrub variants

(rock, snow_forest)
→ OwenG cold rock variants
```

它不能决定：

```text
有没有 tree Distribution
有没有 rock Distribution
数量是 high 还是 low
```

---

## 7.4 entity_prototype_policy

决定同一个 Entity semantic type 在不同 Region 下选哪个 OwenG model variant。

Entity 仍然是离散对象，不参与 Environment morph。

---

## 7.5 path_style

Path geometry 属于 Network lowering。

Profile 只决定 Path 在局部 Region 中的视觉：

```text
surface texture
width tuning
edge softness
tint / roughness
```

同一条 Path 可以连续穿越三个 Region，而不拆成三个 Network。

---

## 7.6 lighting

RegionProfile 控制：

```text
sun color
sun energy
ambient color
ambient energy
sky energy
exposure
```

运行时只维护一套全局主要 lighting environment。

玩家位置决定当前 profile blend weights，并据此插值全局 lighting。

---

## 7.7 atmosphere

Profile 控制：

```text
fog density
fog color
precipitation policy
snow particle intensity
```

例如 snow_forest 可以启用降雪，coastal_forest 不启用。

---

# 8. Region 间空间渐进：复刻 OwenG 的核心能力

Region transition 不是 Scene 切换，也不是 Chunk loading。

它是：

> **根据世界位置，计算相邻 Region Profile 的连续 spatial weights。**

V0.85 已有 Region polygon influence / smooth boundary 的基础，应继续采用 Region polygon + signed-distance / smoothstep 的方向。

---

## 8.1 必须渐进的层

### A. Terrain Geometry

Region 边界附近地形高度/relief 连续过渡，禁止明显高度断层。

### B. Surface / Material

地表 texture weights、tint 等连续 blend。

这是最主要的视觉渐变层。

### C. Path Style

Path 穿越不同 Region 时材质/颜色/边缘表现连续变化。

### D. Lighting

根据玩家位置在 Region Profile 之间插值全局 lighting。

### E. Atmosphere

Fog、snow 等随玩家进入对应 Region 逐渐增强/减弱。

### F. Distribution Visual Composition

Population **是否存在、数量多少** 不进行 Profile 偷偷补全。

但对于相邻 Region 都显式存在同 semantic Distribution 的情况，可以在 transition band 内对 compatible visual prototype pool 做权重混合。

例如两侧都存在 `tree` Distribution：

```text
coastal_forest side
birch-heavy / pine
        ↓
transition
        ↓
snow_forest side
pine / fir
```

注意：

- IR ownership 不变；
- instance 仍属于唯一 owner Region；
- 不因为 Profile blend 新增 semantic population；
- 只有 visual variant composition 可以渐进。

---

## 8.2 不做空间 morph 的层

Entity 保持离散：

```text
research_station
radar_tower
cabin
rowboat
...
```

不能做：

```text
40% research_station + 60% snow_cabin
```

Entity 的出现/消失属于 **IR edit temporal transition**，而不是 Region spatial transition。

---

# 9. Population：具体数量与摆放全部由 Godot Backend 负责

Server / IR 只描述 population intent。

Godot 负责最终 realization。

---

## 9.1 count 模式

如果 IR：

```json
{
  "amount": {
    "mode": "count",
    "value": 27
  }
}
```

Godot 应尽量生成精确：

```text
27 instances
```

若真实空间完全无法容纳，应 Backend validation 明确失败，而不是偷偷大幅减少。

---

## 9.2 density 模式

如果 IR：

```json
{
  "amount": {
    "mode": "density",
    "value": "high"
  }
}
```

Godot 根据：

```text
owner Region 可用面积
semantic type
prototype footprint / spacing
Region profile tuning
Backend density mapping
```

计算 concrete count。

例如：

```text
rock density=high
→ 最终可能是 60 个

tree density=high
→ 最终可能是 140 棵
```

具体数字属于 Backend config，不属于 IR contract。

---

## 9.3 arrangement

IR 可以表达：

```text
uniform
random
clustered
```

Godot 决定具体算法，例如：

```text
seeded random sampling
cluster center sampling
minimum spacing
Poisson-like rejection
collision rejection
terrain slope rejection
path / entity clearance
```

算法不进入 IR。

---

## 9.4 density_profile

如果 IR 指定 gradient 等 density profile，Godot 在 owner Region domain 中完成实际 sampling 权重计算。

仍然保持：

```text
IR = qualitative spatial intent
Godot = concrete instance positions
```

---

# 10. Population Edit 必须稳定，不允许整片随机重洗

这是后续交互体验的固定要求。

例如原 IR：

```text
snow_rocks density = high
```

玩家说：

```text
“snow_area 的石头少一点”
```

Server 返回新完整 IR：

```text
snow_rocks density = medium
```

Godot 重新 lower 后必须尽量做到：

```text
Old: 64 rocks
New: 38 rocks
```

但不是随机重新生成 38 个完全不同的位置。

要求 Distribution lowering 使用稳定 deterministic instance identity / ranking，使：

```text
数量减少
→ 尽量保留旧实例的稳定子集，只移除多余实例

数量增加
→ 尽量保留旧实例，再新增实例
```

因此：

> **“少一点石头”应该看起来像石头逐渐消失，而不是整个 Region 的石头瞬间重新洗牌。**

这也是 Scene Diff 能产生好看 transition 的前提。

---

# 11. 两种 Transition 必须明确区分

系统同时存在两种完全不同的 transition。

## 11.1 Spatial Region Transition

发生原因：

```text
玩家在世界中移动
```

表现：

```text
Region A Profile
→ smooth spatial blend
→ Region B Profile
```

影响：

```text
terrain
surface
path style
compatible distribution visual composition
lighting
atmosphere
```

---

## 11.2 Temporal IR Edit Transition

发生原因：

```text
用户提交新 Prompt
→ Server 返回 New IR
```

流程：

```text
IR0
↓
Compile
↓
IR1
↓
ResolvedWorld0 vs ResolvedWorld1
↓
Scene Diff
↓
Animated Transition
↓
Commit
```

影响：

```text
Entity add/remove/move
Distribution instance add/remove
Path update
Region geometry/profile changes
Surface changes
```

这两类 Transition 不应混成一个系统。

---

# 12. Compiler Server Contract：保持不变

Godot 继续使用：

```text
GET  /health
GET  /info
POST /v1/compile
```

Compile Result 保持：

```json
{
  "status": "ok",
  "world_ir": {
    "regions": [],
    "networks": [],
    "entities": [],
    "distributions": []
  },
  "runtime_bindings": [],
  "runtime_fact_ops": [],
  "meta": {}
}
```

固定规则：

```text
world_ir = 完整的新 IR，不是 patch
```

以下版本暂时保持：

```text
world_ir_version = "2"
runtime_context_version = "1"
compile_result_version = "1"
```

Godot 不因本次 semantic vocabulary 改造而修改 HttpCompilerClient 或 CompileResult parser。

---

# 13. Transaction / Commit 规则继续冻结

每次 Prompt update：

```text
Current IR0
+ Runtime Facts0
+ Prompt
        ↓
POST /v1/compile
        ↓
Candidate IR1
+ Bindings
+ Fact Ops
        ↓
Candidate Runtime Facts
        ↓
Godot Backend Lowering
        ↓
ResolvedWorld1
        ↓
Scene Diff / Transition
        ↓
全部成功
        ↓
COMMIT
```

任何步骤失败：

```text
保持 IR0 / Runtime Facts0 / Scene0
```

Server HTTP 200 不等于立刻 commit。

---

# 14. Prototype / Asset System：正式做法

OwenG 素材已经迁入当前项目后，继续遵循：

```text
World IR semantic type
        ↓
Owner Region
        ↓
RegionProfile / Prototype Policy
        ↓
Prototype Catalog
        ↓
Concrete Godot Resource / TSCN Prototype
```

Godot lowerer 不应散落硬编码 GLB 路径。

推荐固定：

```text
OwenG migrated source assets
→ Asset Registry
→ Prototype / Prototype Descriptor
→ Prototype Catalog
→ Backend
```

具体 placement 必须基于真实 prototype bounds / footprint，而不是猜尺寸。

OwenG 的素材 license / source metadata 应继续保留。

---

# 15. OwenG Visual Scope：第一版必须完整覆盖的能力

## 15.1 Coastal Forest

至少实现：

```text
gentle terrain
grass / dirt ground
beach-like white-sand transition
birch / pine visual policy
grass
shrubs
rocks
clear / warmer lighting
rowboat / tent / cabin compatible assets
```

---

## 15.2 Research Base

至少实现：

```text
controlled terrain
gray gravel / dirt industrial surface
sparse vegetation visual policy
cold / desaturated lighting
light fog
research station
radar tower
warning sign
cargo truck
crate
```

注意：这些 Entity 必须由 IR 显式存在，Profile 不自动 spawn。

---

## 15.3 Snow Forest

至少实现：

```text
rolling terrain
snow-like / gravel surface
pine / fir visual policy
rocks
cold lighting
fog
snowfall
snow cabin
maritime memorial
ruined archway
bunker
concrete wall
```

同样，Entity / Distribution 必须来自 IR。

---

# 16. Entity / Region Compatibility

Backend 必须维护明确 capability / compatibility policy。

第一版建议冻结：

```text
coastal_forest
├── rowboat
├── tent
└── cabin

research_base
├── research_station
├── radar_tower
├── warning_sign
├── cargo_truck
└── crate

snow_forest
├── cabin
├── maritime_memorial
├── ruined_archway
├── bunker
└── concrete_wall
```

Distribution：

```text
coastal_forest
├── tree
├── grass
├── shrub
└── rock

research_base
├── tree
├── grass
├── shrub
└── rock

snow_forest
├── tree
├── shrub
└── rock
```

如果 IR 请求 Backend 不支持的 `(semantic_type, owner_region.type)` 组合：

```text
Backend capability error
```

不能静默替换成不相关模型。

是否允许某些稀疏 vegetation 组合，统一由 capability catalog 决定，不散落在 lowerer 中。

---

# 17. Godot 固定模块职责

后续实现按以下责任边界推进。

## 17.1 Compiler Client

负责：

```text
HTTP
JSON Contract
health/info/compile
```

不负责：

```text
Region Profile
Asset
Placement
Transition
```

---

## 17.2 Region Lowering

负责：

```text
Region semantic placement
→ concrete Region polygon/domain
```

Region polygon 是 Environment Profile 空间权重计算的基础。

---

## 17.3 Owner Region Resolver

负责对 Entity / Distribution：

```text
找到 exactly one inside Region
验证 invariant
提供 owner_region_id / owner_region_type
```

---

## 17.4 RegionProfileCatalog

负责：

```text
coastal_forest
research_base
snow_forest
→ RegionProfile
```

Profile 不由 Server 返回。

---

## 17.5 Prototype / Asset Catalog

负责：

```text
semantic type
+ owner Region type
→ compatible concrete prototypes
```

并提供：

```text
bounds
footprint
scale correction
resource path
metadata
```

---

## 17.6 Network Lowering

负责：

```text
path topology
→ concrete curve / width / geometry
```

Path visual style根据当前位置的 Region Profile 决定。

---

## 17.7 Entity Lowering

负责：

```text
semantic placement
+ owner Region
+ prototype footprint
→ concrete prototype + Transform
```

---

## 17.8 Distribution Lowering

负责：

```text
population amount
arrangement
density profile
owner Region domain
prototype policy
spacing / collision
→ deterministic instances
```

---

## 17.9 Terrain Resolver / Surface Runtime

负责：

```text
Region polygon influence
RegionProfile terrain
RegionProfile surface
Path influence
→ one continuous terrain/surface
```

---

## 17.10 Resolved World

保存已经完成 lowering 的 Godot value data：

```text
Region polygons/profile references
Path curves
Entity prototype + transform
Distribution concrete instances
Terrain resolved data
```

不能保存 live SceneTree Node reference。

---

## 17.11 Scene Runtime

只负责：

```text
instantiate
remove
move
update
render
```

不能重新解释：

```text
inside
near
along
direction_of
```

---

## 17.12 Scene Diff / Transition Manager

负责：

```text
ResolvedWorld0
vs
ResolvedWorld1
→ concrete scene operations + animation
```

---

## 17.13 World Coordinator

负责完整 transaction：

```text
Compile
→ Candidate State
→ Lower
→ Diff
→ Transition
→ Commit / Rollback
```

---

# 18. Determinism 与 Instance Identity

固定 contract：

```text
Same IR
+ Same Runtime Input
+ Same Seed
+ Same Backend Config
+ Same Asset/Prototype Catalog Version
→ Same Resolved World
```

Distribution instance ID 必须稳定，例如概念上：

```text
snow_rocks:000
snow_rocks:001
...
```

实际生成算法可以使用 hash/rank，而不要求必须是数组 prefix，但必须支持：

```text
population 增减时最大限度保留旧实例 identity
```

这是增量 Scene Diff 的基础。

---

# 19. 必须支持的核心编辑案例

## Case A — 减少某 Region 的石头

Current IR：

```text
snow_area: snow_forest
snow_rocks: rock inside snow_area density=high
```

用户：

```text
“snow_area 的石头少一点”
```

Server：

```text
rock density high → medium
```

Godot：

```text
re-lower population
→ concrete count decreases
→ preserve stable subset
→ diff removes excess rocks
→ animated disappearance
```

---

## Case B — 增加树木

```text
tree density medium → high
```

Godot：

```text
retain old tree instances
+ deterministically add new instances
```

资产 variant 仍由 owner Region Profile 决定。

---

## Case C — 修改 Region type

例如 Server 合法地把某 Region 从：

```text
coastal_forest
→ snow_forest
```

Godot 应重新 resolve：

```text
terrain profile
surface
lighting/atmosphere contribution
compatible distribution prototype variants
compatible entity prototype variants
path style
```

但不能凭 Profile 新增 IR 中不存在的 objects。

---

## Case D — Path 跨 Region

同一 Network：

```text
path west → east
```

经过：

```text
coastal_forest
→ research_base
→ snow_forest
```

保持一个 Path semantic object；只改变局部 material/style。

---

# 20. 第一版验收场景

至少准备一个固定 regression fixture：

```text
World
├── coastal_region: coastal_forest
├── research_region: research_base
├── snow_region: snow_forest
│
├── main_path: path
│   └── traverses all three regions
│
├── coastal entities
├── research entities
├── snow entities
│
├── coastal distributions
├── research distributions
└── snow distributions
```

必须验证：

1. 三个 Region 可以在一个连续世界同时存在；
2. Region 之间无硬材质边界；
3. Terrain relief 连续；
4. Path 连续且局部外观随 Region 改变；
5. Lighting / fog / snowfall 随玩家位置连续变化；
6. Tree / rock / grass / shrub 只在 IR 存在时生成；
7. Entity/Distribution exactly one owner Region；
8. Region nesting 被拒绝；
9. 同 Seed 重跑得到稳定 Resolved World；
10. “石头少一点”只移除稳定子集，不重洗整片 population；
11. Scene edit 成功后才 commit Current IR；
12. Profile 不会生成重复 cabin/tree/rock。

---

# 21. 明确不做的事情

当前冻结范围明确不做：

```text
Semantic multi-chunk world
Chunk streaming / LLM chunk prefetch
Infinite world
Region nesting
Arbitrary Region vocabulary
Generic biome composition language
Generic climate fields in IR
Profile id in IR
Texture/material/fog/shader fields in IR
Godot-side semantic completion
Profile auto-spawn Entity / Distribution
Generic road/river/railway system
Complex Terrain Solver
Global Constraint Optimization
Procedural Building Generation
Interior Generation
Runtime generated Mesh pipeline
Arbitrary asset style planner
```

也暂不恢复旧：

```text
graveyard
town
village
church
house
tombstone
road
```

等不属于 OwenG-aligned active catalog 的旧能力。

如果未来要加，必须作为新的明确 milestone，而不是在当前 Backend 中偷偷兼容。

---

# 22. 最终一句话架构定义

整个系统最终可以压缩成：

```text
LLM Compiler
→ 用有限 World IR vocabulary 决定世界里“有什么”

Region
→ 一个 Environment Archetype 的语义空间

Godot Backend
→ 把 Region 变成 polygon/profile，把 population 变成确定数量和坐标，把 semantic object 变成真实 OwenG asset

RegionProfile
→ 只决定环境与已有对象“长什么样”，不决定“有没有”

Region Transition
→ 让地形、地表、路径、生态外观、光照、气氛在空间中连续变化

Scene Diff / Transition
→ 让每次新的完整 IR 从旧世界平滑演化成新世界
```

最终边界固定为：

> **IR 决定 WHAT。Godot 决定 WHERE / HOW MANY / WHICH ASSET / HOW TO RENDER。RegionProfile 决定 HOW IT LOOKS。Scene Transition 决定 HOW IT CHANGES。**

这就是后续实现不再改变的主架构。
