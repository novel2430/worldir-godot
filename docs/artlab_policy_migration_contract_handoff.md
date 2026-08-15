# ArtLab Policy 移植完成与后续契约变更交接

日期：2026-08-15  
目标分支：`to-V1-B`  
V1-B 合并基线：`575b7bceccce8c5b660d235f877c86d39098f7a4`  
ArtLab Policy 移植提交：`b61b816`  
功能优先收尾提交：`f7ba1a7`

本文给接手同事回答三个问题：

1. ArtLab Policy 哪些经验已经完成移植；
2. 哪些能力不能继续塞进 Backend 内部实现，必须改变 World IR、Resolved 数据或
   A/B 跨 Chunk 协议；
3. 每项能力的目的、预期效果和建议的最小并入方式是什么。

本文是交接建议，不授权直接修改下述契约。当前 `to-V1-B` 的公开输入输出和 A/B
接口仍是基线；任何契约项都应先由相关负责人确认版本与兼容方案。

## 1. 已完成：不改契约的 ArtLab Policy 移植

当前实现已经把 ArtLab 的“参数化生成经验”变成 Godot Backend 自有的 Realization
Policy，而没有把 ArtLab 沙盒、固定布局或实验生命周期合入主项目。

| 范围 | 已完成效果 | 主要位置 |
|---|---|---|
| Policy 数据 | terrain、surface、dressing 参数集中配置；缺失、损坏、错误类型、未知格式回退；可输出 fingerprint | `data/configs/artlab_realization_policy.json`、`scripts/backend/realization_policy.gd` |
| Terrain | 起伏、聚落平整、道路/建筑地形影响、海岸形状与过渡由 Policy 驱动 | `scripts/backend/terrain_resolver.gd` |
| Surface | meadow、forest soil、settlement dirt、sand/wet sand、road/building dirt 沿用现有 RGBA + wetness 输出 | `scripts/resolved/resolved_terrain.gd`、`scripts/runtime/scene_runtime.gd` |
| Dressing | 森林边缘、cluster、道路走廊和按 prototype footprint 缩放的建筑 clearing；不改变显式 Distribution | `scripts/backend/forest_dresser.gd` |
| Chunk 语义 | 方向/ownership 裁掉目标后递归裁掉 placement、topology、density selector 依赖，避免悬空关系回退 Chunk 中心 | `scripts/chunk/chunk_generator.gd` |
| A+B 集成 | 保留 V1-B 的 revision、candidate、pin、preview、historical、transition 和稳定 ChunkRoot 语义 | `scripts/chunk/chunk_manager.gd`、`scripts/revision/` |
| 可维护性 | Policy JSON Schema、字段说明、变更日志、只读 dump、场景/视觉/streaming 测试骨架 | `docs/`、`tools/`、`tests/` |

当前优先级仍然是：

```text
显式 World IR 语义
  > 已解析 placement / prototype occupancy
  > Backend-owned ArtLab Realization Policy
```

已经明确保持不变的边界：

- World IR 仍只有 `regions`、`networks`、`entities`、`distributions` 四个 root；
- Compiler Server、Runtime Context、CompileResult 协议未改变；
- `WorldBackend`、`ChunkGenerator`、`ChunkManager`、`SceneRuntime` 公开方法签名未改变；
- Policy 不写回 World IR，不改变显式 Distribution 数量、arrangement、relation 或稳定 ID；
- Same Inputs 仍包含 seed、IR、Backend/Policy 版本和显式 generation inputs。

验证状态以 [开发备忘录](artlab_policy_development_memo_2026-08-15.txt) 为准。发布前关键
真实引擎测试已通过；完整场景矩阵、长距离 streaming、五场景图形验收和性能数据仍是
明确记录的后续验证，不应被误写成已完成。

## 2. 当前实现中最容易误判的两个“已有字段”

### 2.1 `environment` 目前不是正式能力

`ResolvedWorld` 当前确实有 `environment: Dictionary`，`WorldBackend.lower()` 被直接
调用时也会从输入 Dictionary 复制同名值。但正式 Compiler 路径中的
`ContractValidator.ROOT_KEYS` 严格限定四个 root，带 `environment` 的 World IR 会被
拒绝；`SceneRuntime` 也没有按该 Dictionary 驱动世界光照、天空、雾或降水。

因此它只是内部预留/兼容残留，不是已经完成的 World IR 或 Resolved Environment
协议。不要绕过验证器后宣称环境语义可用。

### 2.2 `spatial_payloads` 目前不是跨 Chunk 影响总线

`WorldState.spatial_payloads` 当前保存 Runtime Fact 的 Godot-local 空间证据，B 只把
本次 transaction 引用到的 payload 放进 `generation_overrides`，A 再把它交给当前
目标 Chunk。现行共享规范明确规定这些 overrides 是 transaction-local，不自动进入
未来 Chunk，也不广播给邻居。

因此它不能用来承载“本 Chunk 的研究站建筑应清理邻 Chunk 树木”或“道路/建筑地形
影响跨边界延续”这类持久结构影响。复用同一个 Dictionary 容器可以减少方法签名修改，
但改变传播范围仍然是 A/B 跨 Chunk 协议变更。

## 3. 契约变更总表

| 能力 | 目的与可见效果 | 必须改变 | 建议最小版本/方式 |
|---|---|---|---|
| `research_base` 等新场所类型 | Compiler 能忠实表达研究基地，Backend 选择正确 prototype/布局 | World Catalog；通常不必改 World IR 结构 | World Catalog V2 增加类型和 capability；保持四 root |
| `snow_forest` 等 biome | 同样是 forest，但使用雪地地表、植被和环境规律 | World IR Region 字段；可能带 Resolved surface/environment | World IR V3 给 Region 增加可选 `biome`，不要把 biome 塞进 `type` |
| weather / atmosphere / time of day | 整个世界具有稳定天空、太阳、雾和雨雪 | World IR root + ResolvedEnvironment + 世界级 runtime coordinator | World IR V3 增加可选语义化 `environment`；新增 typed ResolvedEnvironment |
| 新 surface channel | 表达 snow、rock、mud、burn 等 RGBA 四通道之外的连续场 | ResolvedTerrain、diff/signature、Runtime shader 输入 | 在保留旧字段的前提下增加可选 named channels V1 |
| 持久结构跨 Chunk 影响 | 边界建筑、道路或地标能在邻 Chunk 连续平整地形、清植被和改变地表 | A/B GenerateChunk 语义、ResolvedChunk influence 数据、ChunkManager 调度 | 保持方法签名，给 `generation_overrides` 增加版本化 influence payload，并由 A 管理 revision-scoped index |
| ArtLab 固定五 Chunk/HUD/mutation/evidence | 复现实验和收集对照证据 | 不应修改生产契约 | 独立 demo/tool 场景调用公开 API；不要并入 WorldCoordinator 正式生命周期 |

这些能力彼此独立，不应强制一次性全部升级：

- 只做研究基地：优先 World Catalog V2，不需要环境或新 surface；
- 只修跨边界 clearing：只改跨 Chunk influence 协议，不需要 World IR V3；
- 做完整雪林天气：需要 World IR V3 + ResolvedEnvironment，并可能需要 snow channel；
- 只增加 Backend 自动泥地细节：如果不承载新的用户语义，可只扩 ResolvedTerrain，
  不改 World IR。

## 4. World IR / World Catalog：建议最小修改

### 4.1 新场所类型：优先升级 World Catalog

`research_base` 表示场所的语义角色，适合作为新的 Region type；如果请求的是一个
独立地标建筑，也可作为 Entity type。它不要求第五种 Primitive 或新 root。

最小改动面：

1. World Catalog V2 增加 `research_base` 的合法 kind；
2. Compiler 的 catalog/prompt lowering 能产生该类型；
3. `ContractValidator` 类型表与 HTTP `/info` 的 `world_catalog_version` 同步升级；
4. PrototypeCatalog 提供至少一个可实现路径，否则返回 Backend capability error；
5. 增加 Region/Entity 两种语义归属的契约测试，避免同名类型含义不清。

不要为了省版本升级把研究基地伪装为 `village` 或 `district`。这会让 IR 通过，但丢失
用户明确语义，后续 Policy 只能靠名称猜测。

### 4.2 Biome：给 Region 增加可选语义，不复用 `type`

`snow_forest` 同时包含“场所角色 forest”和“生物群系 snow_forest”。建议保持：

```json
{
  "id": "north_forest",
  "type": "forest",
  "biome": "snow_forest",
  "placement": {"anchor": "north"}
}
```

这是建议中的 World IR V3 示例，当前 V2 会拒绝 `biome`。

最小改动面：

1. `Region` 增加可选 `biome`，缺失时保持当前 Policy 推导和画面；
2. biome 值由共享 Catalog/枚举管理，不允许任意 ArtLab profile 文件名穿透到 IR；
3. Compiler 只有在用户语义明确时输出 biome，不应默认给所有 Region 打标签；
4. Backend 将 biome 解析为内部 realization role，再由 Policy 决定数值；
5. World IR 版本建议升到 V3，因为当前验证器使用严格 exact keys，旧客户端会拒绝
   新字段。`/info.world_ir_version` 必须同步更新。

### 4.3 世界环境：只放后端无关语义

建议的可选 V3 root 示例：

```json
{
  "environment": {
    "time_of_day": "dusk",
    "weather": {"type": "snow", "intensity": "medium"},
    "atmosphere": {"visibility": "hazy"}
  },
  "regions": [],
  "networks": [],
  "entities": [],
  "distributions": []
}
```

World IR 不应直接包含 Godot 的 `fog_density`、太阳欧拉角、光照 energy 或 shader
uniform。这些数值属于 Backend Policy/Resolved 输出。World IR 只表达稳定语义，如
时间段、天气类型、强度和能见度。

最小改动面：

1. 与 `biome` 一起纳入一次 World IR V3 升级，避免连续多次握手变更；
2. 扩展 `ContractValidator`、Compiler request/result fixture 和文档；
3. `/info.world_ir_version` 从 `2` 升级，旧 server/client 通过版本不匹配明确失败；
4. V3 的 `environment` 和 `biome` 都保持 optional，使现有四-root 内容可以无损迁移；
5. 不支持的关键环境请求仍返回 `ir_gap`，不得静默近似。

## 5. Resolved 数据：建议最小修改

### 5.1 新增 typed `ResolvedEnvironment`

目的：把 World IR 的后端无关环境语义解析成 Godot 可执行的稳定值，使天空、太阳、
环境光、雾和降水有明确来源，也能参与 diff、transition 和 deterministic signature。

建议先采用兼容式增量：

1. 新增 `ResolvedEnvironment` Resource；
2. 在 `ResolvedWorld` 增加可选 `resolved_environment`，暂时保留旧
   `environment: Dictionary`，不要在同一提交直接改它的类型；
3. `WorldBackend` 只从已验证的 V3 environment 生成 typed value；
4. `ResolvedChunk.absorb_world()`、`deterministic_signature()`、`SceneDiff` 和 transition
   同步支持新值；
5. 增加一个世界级 EnvironmentCoordinator，在 ChunkRoot 之外只维护一个
   `WorldEnvironment`、主光源和降水系统；
6. Current Chunk/revision 决定 active environment，Preview/Historical Chunk 不各自
   实例化天空和太阳；
7. 经过一轮兼容期后再移除旧 Dictionary。

这样能避免每个 Chunk 一套光照产生接缝，也避免一次性破坏已有测试和内部调用者。

### 5.2 扩展 `ResolvedTerrain` 的 named surface channels

当前固定语义是：

```text
surface_masks.R = forest floor
surface_masks.G = settlement dirt
surface_masks.B = coast sand
surface_masks.A = road/building dirt
shore_wetness   = coast wetness
```

增加 snow、rock、mud、burn 等连续场时，不建议重新解释现有 RGBA，否则旧 shader、
截图基线和 SceneDiff 会在无版本信息时产生不同含义。

建议最小新增：

```gdscript
var surface_channels: Dictionary = {
    "snow": PackedFloat32Array(),
    "rock": PackedFloat32Array(),
}
```

要求：

- 每个存在的 channel 长度必须等于 `grid_size * grid_size`；
- channel 名称来自 Backend/Resolved schema，不接受任意 World IR 字符串；
- 缺失 channel 等价于全 0，旧 `surface_masks` 和 `shore_wetness` 保持原义；
- `ResolvedChunk.deterministic_signature()` 按 channel 名排序；
- `SceneDiff`、transition、edge/seam 测试比较新 channel；
- Runtime 可把 named channels 打包进额外 vertex attribute 或生成纹理，不能让
  SceneRuntime 重新解释 World IR；
- 相邻 Chunk 继续用全局坐标采样，边界值必须一致。

## 6. 跨 Chunk 协议：持久结构影响

### 6.1 要解决的问题

一个结构由 owner Chunk 保存稳定 identity，但它的 footprint/道路肩部/地形平整或
植被 clearing 可能越过 Chunk 边界。当前邻居只获得 terrain heights 和 road exits
边界约束，看不到完整结构影响，于是可能出现：

- 建筑跨边界一侧仍长树；
- 建筑 pad 或道路肩部在 seam 处突然终止；
- 先生成哪个 Chunk 会改变最终 dressing；
- revision 后 owner 更新了，邻居仍保留旧影响。

### 6.2 建议的最小协议形态

保持 `ChunkGenerator.generate_chunk(..., generation_overrides={})` 方法签名不变，在
共享 A/B 文档中正式增加一个版本化键，例如：

```text
generation_overrides.cross_chunk_influences
  format: worldir.chunk-influences.v1
  records: Array[ResolvedChunkInfluenceValue]
```

单条 record 至少包含：

```text
stable influence id
source object id / source Chunk coord / source IR revision
kind: structure_footprint | terrain_grade | surface | population_exclusion
world-space bounds and deterministic geometry/value parameters
affected Chunk coords or query bounds
content hash / format version
```

它是 Godot-local Resolved/GenerateChunk value data，不进入 World IR，也不发送给 Compiler。

### 6.3 A 侧最小实现顺序

1. 新增纯值 `ResolvedChunkInfluence`，禁止 Node、RID 或 Scene 引用；
2. `ResolvedChunk` 输出 `outgoing_influences`，来源仅是已解析 structure/network/prototype
   footprint，不从画面节点反推；
3. `ChunkManager` 按 `(revision, source_coord, influence_id)` 保存 revision-scoped index；
4. 只有 candidate 被正式 accept/commit 后才能发布 influence，失败 candidate 不得污染
   index；
5. 生成任一 Chunk 前，按其 bounds + policy halo 查询 influence，按稳定 key 排序后放入
   overrides；
6. influence hash 变化时，只调度受影响的 active 邻居进行 reconciliation，不扩大 B 的
   Current transaction 强失败域；
7. Historical Chunk 查询自身 source revision 的 index，不能自动混用 latest influence；
8. 同一 influence set 重复应用必须幂等，避免邻居之间无限互相 rebuild。

这里虽然复用了已有 Dictionary 参数，但必须更新
`docs/toV1-B/WorldIR_V1_AB_Shared_Development_Contract.md` 和
`docs/WorldIR_V1_A_Development_Norms.md`：现行规则把 overrides 定义成 transaction-local，
不更新文档就会出现双方对传播范围理解相反的问题。

### 6.4 必须证明的确定性与事务性质

- 同 IR/revision/seed/Policy fingerprint/influence set 的 Chunk signature 一致；
- 以中心优先、外围优先、逆序生成 3×3，reconciliation 收敛后的结果一致；
- owner candidate 失败或事务 abort 时，邻居完全不观察到 provisional influence；
- owner commit 后邻居失败不回滚 Current revision，保持可重试；
- unload/reload、Historical preserve、latest-before-entry 仍符合 V1-B 规则；
- 删除/移动结构会撤销旧 influence，并只重建真实相交的 Chunk；
- seam 的 terrain、surface channel、wetness 和 population exclusion 连续。

## 7. 不建议并入生产运行时的 ArtLab 内容

ArtLab 的固定五 Chunk 布局、mutation key、HUD、相机机位和证据采集生命周期是实验
工具，不是世界语义。若同事需要继续使用，建议：

- 放在独立 demo scene 或 `tools/`；
- 通过 `ChunkManager`、revision coordinator 和截图工具的公开入口驱动；
- 不修改正式 `WorldCoordinator` 的启动流程；
- 不把实验状态写入 World IR、Runtime Facts 或 ResolvedWorld；
- 生成的截图/metrics 保持为构建产物，不作为运行时输入。

## 8. 建议交付顺序

### 切片 A：研究基地语义

World Catalog V2 → Validator/Compiler → Prototype capability → fixtures/tests。

这是最小且独立的语义升级，不需要等待环境或跨 Chunk 协议。

### 切片 B：Biome 与世界环境

先冻结 World IR V3 schema → 增加兼容式 ResolvedEnvironment → 更新 Compiler `/info`
握手 → 接入世界级 EnvironmentCoordinator → 再开放真实 Compiler 输出。

不要先让 Compiler 输出新字段、再补 Godot 支持；严格 validator 会使中间状态不可用。

### 切片 C：Surface channels

先做 additive ResolvedTerrain channel 和旧 shader fallback → diff/signature/seam tests →
再让 biome/weather Policy 生成 snow/rock/mud 等 channel。

### 切片 D：跨 Chunk influence

先定义 value schema 和 revision lifecycle → A 侧 index/query → commit 后发布与邻居
reconciliation → 生成顺序/abort/historical 测试 → 最后接 building/road/landmark 影响。

## 9. 每个契约 PR 的最低交接清单

- 写明修改的是 World IR、World Catalog、Resolved 还是 A/B Chunk contract；
- 更新 `/info` 版本或内部 format version，禁止同版本字段换义；
- 给出旧输入的默认行为、旧客户端失败方式和回滚办法；
- 说明 Same Inputs 新增了哪些组成部分；
- Compiler、Validator、Backend、Resolved、Runtime、diff/transition 同步更新；
- candidate/abort 不能污染正式 WorldState、ChunkRecord 或 influence index；
- 增加正向、非法值、旧版本、顺序独立和序列化/签名测试；
- 真实 Godot 验证至少覆盖中心/边界 Chunk、revision、streaming reload 和视觉 seam；
- 未完成的性能或人工视觉证据明确标为待测，不用“已有工具”代替“已经通过”。

## 10. 一句话决策原则

如果能力只是改变“同一合法 World IR 在 Godot 中怎样长出来”，放进 Backend-owned
Policy；如果用户必须明确表达新的世界语义，升级 World IR/World Catalog；如果 Runtime
需要消费新的稳定生成结果，扩展 Resolved；如果一个 Chunk 的稳定结果会改变另一个
Chunk 的生成输入，就正式升级跨 Chunk 协议，而不是依靠可变全局状态或隐式广播。
