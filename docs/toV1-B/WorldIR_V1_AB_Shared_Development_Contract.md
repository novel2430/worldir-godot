# WorldIR Godot V1 — A/B 并发开发共同契约

> **状态**：V1 Parallel Development Baseline  
> **适用基线**：`godot-main_V0_85`  
> **适用对象**：A（Chunk / Streaming / Generation）与 B（IR Revision / Rebase / Transition）  
> **优先级**：若 A/B 个人开发文档与本文冲突，**以本文为准**。

---

# 1. 文档目的

V1 的并发开发不以“双方实现方式一致”为目标，而以以下三件事为目标：

1. 双方对系统语义使用同一套定义；
2. 双方只通过明确的数据结构与接口交互；
3. 双方可以独立实现内部细节，最终仍能无歧义整合。

因此本文主要定义：

```text
Shared Concepts
Shared Constants
Shared Data Contracts
Ownership Boundary
Required Interfaces
State Semantics
Determinism Invariants
Revision Semantics
Integration Rules
Shared Acceptance Tests
```

本文**不规定**：

```text
具体 class 数量
具体文件内部组织
具体 procedural noise 算法
具体 tween / shader 实现
具体测试框架组织
具体代码编写顺序
```

只要满足共同 contract，A/B 可以自由选择内部实现。

---

# 2. V1 的共同目标

V1 要在 V0.85 的 World IR 驱动世界基础上，实现：

> **玩家可以在由 160m × 160m Chunk 组成的连续世界中自然移动；当前 Chunk 与尚未成为历史的世界可以被最新 World IR 重写；已经成为历史的 Chunk 默认保持；未来尚未生成的 Chunk 永远使用最新 IR 生成。**

Compiler 与 World IR 本身保持 Chunk-Agnostic：

```text
Compiler
    不知道 chunk_id
    不知道 player_position
    不知道 streaming state
    不知道 3×3 active window
```

Compiler 仍然只处理：

```text
current_ir + prompt + runtime_context
        ↓
new_world_ir
```

Chunk 是纯 Godot Backend / Runtime 概念。

---

# 3. A/B 的一句话职责

## A — Chunk / Streaming / Deterministic Generation

A 负责：

> **给定 Chunk 坐标、World IR、IR Revision、World Seed 与必要边界条件，确定该 Chunk 应该是什么，并负责它何时被预生成、激活、休眠或卸载。**

## B — IR Revision / Rebase / Transition

B 负责：

> **新的 IR 到达后，决定哪些 Chunk 有权被重写、哪些必须保留，并把旧 ResolvedChunk → 新 ResolvedChunk 的变化安全地应用到玩家正在看到的 Scene。**

---

# 4. 固定空间常量

V1 第一版固定：

```text
CHUNK_SIZE_M = 160.0
ACTIVE_RADIUS = 1
```

因此：

```text
1 Runtime Chunk = 160m × 160m
Active Window = 3 × 3 Chunks
Visible / Managed Core Area = 480m × 480m
```

第一版不要引入动态 Chunk Size。

---

# 5. Chunk Coordinate 的唯一正式定义

对于世界平面位置：

```text
p = (x, z)
```

Chunk 坐标定义：

\[
C(p)=\left(\left\lfloor\frac{x}{160}\right\rfloor,\left\lfloor\frac{z}{160}\right\rfloor\right)
\]

必须只有一个共享实现，例如：

```text
scripts/chunk/chunk_math.gd
```

A/B 均不得复制实现另一套 `world_to_chunk()`。

至少共享：

```text
world_to_chunk(world_position) -> Vector2i
chunk_origin(coord) -> Vector2
chunk_bounds(coord) -> Rect2
is_in_active_window(coord, current_coord) -> bool
```

边界点的归属必须由 floor 规则唯一确定，不允许两边自行加入 epsilon 产生不同结果。

---

# 6. Current Chunk 的唯一来源

`current_chunk_coord` 由 A 根据玩家真实 World Position 计算。

B 不自行读取 Player Transform 再计算 Chunk。

A 在 Current Chunk 发生变化时提供事件，例如：

```text
current_chunk_changed(old_coord, new_coord)
```

系统中必须始终只有一个 Current Chunk 定义。

---

# 7. Chunk 有两个正交状态维度

这是 V1 最重要的共同定义之一。

## 7.1 Streaming State

Streaming State 回答：

> **这个 Chunk 当前在内存 / Scene Runtime 中加载到了什么程度？**

由 A 管理。

正式 vocabulary：

```text
UNLOADED
GEOMETRY_READY
ENVIRONMENT_READY
ACTIVE
DORMANT
```

语义：

### UNLOADED

没有可用 Scene 内容；可以只有 metadata / ChunkRecord。

### GEOMETRY_READY

至少已具备主要几何连续性所需内容，例如：

```text
terrain patch
required road geometry
water / major geometry（若有）
```

### ENVIRONMENT_READY

主要环境内容已经可显示，例如：

```text
trees
rocks
grass
surface appearance
non-critical dressing
```

### ACTIVE

玩家当前所在 Chunk；需要完整碰撞与当前交互能力。

### DORMANT

已经生成过但当前不在 Active Window 核心使用范围；第一版可以保留数据或 Scene，后续允许真正 eviction。

---

## 7.2 Authority State

Authority State 回答：

> **新的 IR 是否仍有权重写这个 Chunk？**

正式 vocabulary：

```text
PROVISIONAL
COMMITTED
```

### PROVISIONAL

Chunk 可以已经被完整绘制，但它仍只是为了视觉连续性提前 materialize 的未来世界。

新 IR 可以对其 rebase。

### COMMITTED

Chunk 已经成为玩家真实经历过的世界历史。

默认不被之后的新 IR 全量重写。

---

# 8. 必须接受的核心事实：Loaded != Committed

以下状态完全合法：

```text
streaming_state = ENVIRONMENT_READY
authority = PROVISIONAL
```

含义：

> 这个 Chunk 玩家已经能看到，但它还没有成为历史，因此新 IR 可以改写。

禁止使用以下错误规则：

```text
if loaded:
    immutable
```

Chunk 是否可被重写由 Authority / Current Chunk 决定，而不是由 loaded 状态决定。

---

# 9. COMMITTED 的第一版触发规则

V1 第一版固定：

> **玩家真正进入某个 Chunk 时，该 Chunk 成为 COMMITTED。**

因此 Current Chunk 必然是 COMMITTED。

例如：

```text
Player at (5,5)

Neighbors:
PROVISIONAL

(5,5):
COMMITTED + ACTIVE
```

玩家从 `(5,5)` 进入 `(5,6)`：

```text
(5,6): PROVISIONAL -> COMMITTED
```

未来可以增加：

```text
玩家交互 / Runtime Fact
→ 对应 Chunk 提前 COMMITTED
```

但这不是当前并发开发的强制需求，不应阻塞 V1 第一版。

---

# 10. IR Revision 的共同定义

Godot Runtime 内部维护：

```text
current_ir
current_ir_revision
```

第一次成功生成：

```text
IR0
revision = 0
```

下一次成功世界编辑：

```text
IR0 -> IR1
revision = 1
```

Revision 是纯 Godot Runtime metadata：

```text
不写入 World IR
不发送给 Compiler
不要求修改 Server API
```

---

# 11. 新 IR 对不同 Chunk 的正式统治规则

当：

```text
IR_r -> IR_(r+1)
```

必须遵守以下规则。

## 11.1 Current Chunk

```text
MUST REBASE
```

即使已经 COMMITTED，当前 Prompt 仍明确作用在玩家当前所在 Chunk。

## 11.2 PROVISIONAL Chunk

```text
MAY / SHOULD REBASE TO LATEST IR
```

如果没有立刻 rebuild，可以先标记 stale，但玩家进入之前必须更新到 latest revision。

## 11.3 Historical COMMITTED Chunk

```text
PRESERVE BY DEFAULT
```

不得因为新 IR 到来而全量重新生成。

## 11.4 Unmaterialized Chunk

```text
NO IMMEDIATE WORK
```

未来第一次生成时直接使用最新：

```text
current_ir
current_ir_revision
```

因此从语义上，它已经被最新 IR 统治，只是还不存在可 diff 的 Scene。

---

# 12. 正式可重写判断

共同语义等价于：

```gdscript
can_rebase(chunk, current_coord) =
    chunk.coord == current_coord
    or chunk.authority == PROVISIONAL
```

Historical COMMITTED 默认 false。

注意：

```text
Current Chunk 是 COMMITTED 的特殊可写例外。
```

---

# 13. `ChunkRecord` 共享数据契约

双方共同认识的最小 Chunk metadata：

```text
ChunkRecord
├── coord: Vector2i
├── streaming_state
├── authority
├── source_ir_revision: int
├── target_ir_revision: int
├── is_stale: bool
└── resolved_chunk: ResolvedChunk?
```

字段语义：

### `coord`

唯一空间身份。

### `streaming_state`

A 管理当前 lifecycle。

### `authority`

记录 `PROVISIONAL / COMMITTED`。

### `source_ir_revision`

当前 `resolved_chunk` 是基于哪个 IR Revision 生成的。

### `target_ir_revision`

B 希望该 Chunk 最终达到哪个 Revision。

### `is_stale`

当前生成结果是否落后于 target revision。

必须满足：

```text
is_stale == false
=> source_ir_revision == target_ir_revision
```

如果某实现选择不保存 `is_stale` 而由 revision 比较计算，也可以，但对外语义必须等价。

---

# 14. `ResolvedChunk` 是 A/B 唯一共享的世界生成结果

双方不共享 procedural generator 内部状态，也不共享 SceneTree live reference。

最小概念结构：

```text
ResolvedChunk
├── coord
├── bounds
├── revision
├── terrain
├── networks
├── entities
├── distributions
└── environment
```

要求：

```text
可以保存：
Vector2 / Vector3
Transform3D
PackedArray
Dictionary / Resource value data

不能保存：
Node
Node3D
MeshInstance3D live reference
RID runtime handle
SceneTree path 作为空间 truth
```

`ResolvedChunk` 应保持 V0.85 `ResolvedWorld` 的 value-data 思想。

---

# 15. A 必须对 B 提供的核心生成能力

逻辑接口固定为：

```text
GenerateChunk(
    coord,
    world_ir,
    ir_revision,
    world_seed,
    boundary_constraints
) -> ResolvedChunk
```

建议签名：

```gdscript
func generate_chunk(
    coord: Vector2i,
    world_ir: Dictionary,
    ir_revision: int,
    world_seed: int,
    boundary_constraints: ChunkBoundaryConstraints
) -> ResolvedChunk
```

内部如何复用 V0.85 `WorldBackend` / lowerers 由 A 自由决定。

但必须保证：

> B 不需要了解 RegionLowerer / TerrainResolver / DistributionLowerer 的内部实现，就能够请求一个指定 Revision 的 ResolvedChunk。

---

# 16. GenerateChunk 的确定性 Contract

对于固定输入：

\[
G(c,IR,r,S,B)
\]

必须满足：

\[
G(c,IR,r,S,B)=G(c,IR,r,S,B)
\]

即 Same Inputs → Same ResolvedChunk。

同时必须满足生成顺序独立：

```text
Generate(A), Generate(B)
```

与：

```text
Generate(B), Generate(A)
```

每个 Chunk 的最终结果一致。

禁止把世界实现成：

```text
Chunk_(n+1) = RandomContinuation(Chunk_n)
```

Chunk 不能成为依赖加载顺序的 Markov Chain。

---

# 17. Global Coordinate Principle

Procedural 世界函数必须尽量使用：

```text
global world coordinates
+
world seed
+
semantic identity
```

而不是：

```text
chunk-local random sequence
```

Terrain 概念：

\[
H(x,z)=F_H(x,z,WorldSeed,IR)
\]

Population 候选概念：

\[
u=Hash(WorldSeed,semantic\_type,global\_cell_x,global\_cell_z)
\]

目的是保证：

```text
unload -> reload
```

不会改变：

```text
terrain
roads
population placement
prototype selection
```

只要相关输入没有改变。

---

# 18. Boundary Constraints 共同语义

当新 Chunk 邻接已经 COMMITTED 的历史 Chunk 时，新世界不能为了服从新 IR 而破坏已经存在的几何连续性。

生成函数因此允许输入：

```text
ChunkBoundaryConstraints
```

V1 第一版至少应能够表达：

```text
Terrain:
- shared edge heights / equivalent continuous boundary data

Network:
- road exit position
- road exit tangent
- road width
```

后续可增加：

```text
water edge
surface weights
```

共同优先级：

\[
Committed\ Geometry\ Continuity > CurrentIR\ Local\ Freedom
\]

例如旧历史 Chunk 的 Road 已经从边界伸出，新 Chunk 不得在边界直接消失；可以在新 Chunk 内合理终止或转向。

---

# 19. Current IR “强统治” 的正式含义

V1 中：

> **Current IR 强约束 Current / PROVISIONAL / Future Chunk 的生成，但不意味着把整份 IR 每个对象复制进每个 Chunk。**

可以合理延续的语义包括：

```text
Region / biome character
Terrain character
Surface semantics
Distribution tendencies
Network continuation
Environment style
```

不能默认每 Chunk 复制的离散对象包括：

```text
church
lighthouse
research_lab
unique landmark
其它单例 Entity
```

具体 `IR -> ChunkGenerationPolicy` 如何内部实现属于 A 的自由，但外部结果必须遵守这一语义。

---

# 20. 3×3 Active Window 的正式语义

对于 Current Chunk `c`：

\[
|dx|\le1,\quad|dz|\le1
\]

构成 Active Window。

A 必须维护其可视/可用状态。

注意 Active Window 内 Authority 不固定。

可能：

```text
P P P
P C P
P P P
```

也可能玩家走过一些邻居后变成：

```text
P P P
H C P
H H P
```

其中：

```text
P = PROVISIONAL
C = Current COMMITTED
H = Historical COMMITTED
```

---

# 21. Stale Chunk 的正式语义

例如：

```text
source_ir_revision = 0
target_ir_revision = 1
authority = PROVISIONAL
```

则 Chunk 是 stale。

它可以暂时保持旧视觉，以支持 lazy rebuild。

但必须满足：

> **玩家正式进入 Chunk 之前，该 Chunk 必须已经更新至最新 target revision。**

因此 A 必须有等价于：

```text
ensure_latest(coord)
```

的能力。

B 决定 target revision；A 决定何时实际调度 rebuild，只要不违反玩家进入前必须 latest 的 contract。

---

# 22. Scene 与 Runtime ownership

## A 不负责

```text
IR rewrite tween
SceneDiff semantic planning
rewrite ripple
old/new object transition
Compiler transaction
```

## B 不负责

```text
terrain height generation
procedural population scatter
road continuation generation
active window calculation
streaming lifecycle scheduling
```

首次 Chunk materialization 与 IR rewrite 必须被视为两种不同场景：

```text
Initial / Streaming Materialization
    ResolvedChunk -> mount / instantiate

IR Revision Rewrite
    old ResolvedChunk
    -> new ResolvedChunk
    -> SceneDiff / Transition
```

底层 SceneRuntime 可以共享，但双方不要绕过各自职责直接 mutate 对方逻辑。

---

# 23. WorldCoordinator ownership

V1 中：

```text
world_coordinator.gd
```

Compiler transaction / IR revision 方向由 B 主改。

A 的 Streaming 不应把 Player movement lifecycle 大量塞入 WorldCoordinator。

A 的 ChunkManager 应独立管理：

```text
player movement
current chunk detection
active window
materialization lifecycle
```

WorldCoordinator 只在世界编辑事务中与 ChunkManager 协作。

---

# 24. ChunkManager ownership

`ChunkManager` 由 A 主改。

B 通过稳定接口使用，不应直接修改其内部 lifecycle 算法。

期望至少具备语义等价接口：

```text
get_current_chunk_coord()
get_record(coord)
get_active_records()
ensure_chunk(coord)
ensure_latest(coord)
request_rebuild(coord, ir, revision)
mark_stale(coord, target_revision)
```

实际命名可以调整，但能力必须存在且在整合前冻结。

---

# 25. IR Revision Transaction 必须保持 V0.85 的事务语义

Compiler 返回 IR1 不等于立即 commit。

必须仍然遵守：

```text
IR0 / Scene0
    ↓
Compile
    ↓
Candidate IR1
    ↓
Revision Plan
    ↓
Generate Candidate Current Chunk
    ↓
SceneDiff / Transition
    ↓
Success
    ↓
Commit current_ir + revision
```

失败时：

```text
current_ir 不推进
current_ir_revision 不推进
Current Chunk 保持旧版本
历史 Chunk 不变
```

PROVISIONAL Chunk 不允许因为一个最终失败的 candidate IR 被永久 commit 到未来版本。

---

# 26. Revision Boundary Transition

当 Historical COMMITTED Chunk 与新 Revision Chunk 邻接时：

```text
IR0 | IR1
```

必须避免明显的 population / surface seam。

第一版推荐：

```text
TRANSITION_BAND_M = 16.0
```

概念权重：

\[
w(d)=smoothstep(0,T,d)
\]

例如 density：

\[
\rho(d)=(1-w)\rho_{old}+w\rho_{new}
\]

共同边界：

```text
Geometry continuity
→ A / Boundary Constraints

Revision visual blending
→ B / Transition policy
```

具体 shader、scatter weight、动画表现由个人实现决定。

---

# 27. 文件 ownership 建议

## A 主 ownership

```text
scripts/chunk/
    chunk_math.gd
    chunk_record.gd
    chunk_manager.gd
    chunk_generator.gd
    chunk_boundary_constraints.gd

backend/
    与 global-coordinate generation
    terrain/network continuation
    deterministic population generation
    直接相关的修改
```

## B 主 ownership

```text
scripts/revision/
    ir_revision_manager.gd
    revision_plan.gd
    chunk_rebase_planner.gd

scripts/runtime/
    scene_diff.gd
    scene_transition.gd
    revision_boundary_transition.gd

scripts/app/
    world_coordinator.gd
```

## Shared — 修改前同步

```text
resolved_chunk.gd
scene_runtime.gd
world_state.gd
main.tscn
```

同一时段尽量只让一个分支主改 Shared 文件。

---

# 28. 不允许修改的外部 Contract

除非双方重新明确讨论，否则本次 V1 并发开发：

```text
不修改 World IR V2 Schema
不要求 Compiler 理解 Chunk
不增加 chunk_id 到 CompileRequest
不增加 player_position 到 Compiler Contract
不修改 Server 的基本 /v1/compile 语义
```

如果实现过程中发现必须改这些 contract，视为架构 blocker，应先停下同步，而不是任一方自行扩 schema。

---

# 29. 双方必须共同通过的自动测试性质

## T1 — Chunk Coordinate

典型正负坐标与边界位置必须得到一致结果。

## T2 — Same Input Same Output

```text
Generate(c, IR0, seed, B)
==
Generate(c, IR0, seed, B)
```

## T3 — Generation Order Independence

```text
Generate(A), Generate(B)
```

与：

```text
Generate(B), Generate(A)
```

最终 A/B 结果分别相同。

## T4 — Reload Determinism

```text
generate
unload / discard runtime scene
generate again
```

结果相同。

## T5 — Authority

```text
Current       -> rebase allowed
Provisional   -> rebase allowed
Historical    -> rebase denied by default
```

## T6 — Revision Routing

IR0 → IR1 后：

```text
Current      -> target IR1
Provisional  -> target IR1 / stale allowed temporarily
Historical   -> source revision unchanged
```

## T7 — Future Uses Latest

未生成 Chunk 在 IR0 → IR1 后首次 materialize，必须以 IR1 为 source revision。

## T8 — No Stale Entry

玩家进入 Chunk 前：

```text
source_ir_revision == target_ir_revision
```

必须成立。

## T9 — Failed Revision Does Not Commit

Compile / Generate / Transition 任一步失败：

```text
current_ir_revision 不增加
```

## T10 — Committed Boundary Continuity

邻接 Historical Chunk 的新 Chunk 不得在 shared edge 出现明显 terrain crack 或 road hard cut。

---

# 30. 最终共同 Integration Scenario

必须能够完整演示以下流程：

### Initial

```text
IR0
Player at (5,5)
3×3 Active Window materialized
```

### Move

玩家：

```text
(5,5) -> (5,6)
```

满足：

```text
(5,5) Historical COMMITTED IR0
(5,6) Current COMMITTED IR0
new north row PROVISIONAL IR0
```

### Prompt

玩家在 `(5,6)`：

```text
“树少一点，沿路增加一些房子。”
```

Compiler：

```text
IR0 -> IR1
```

满足：

```text
Current (5,6)
    -> IR1 rewrite with SceneDiff / Transition

PROVISIONAL neighbors
    -> IR1 or marked stale for IR1

Historical (5,5)
    -> remains IR0

Unmaterialized future
    -> no immediate Scene work
```

### Continue

玩家继续：

```text
(5,7) -> (5,8)
```

满足：

```text
newly materialized chunks source from IR1
```

并且整体：

```text
无明显 Terrain crack
Road 不在 Chunk 边界硬断
Population 不出现明显 160m 直线 seam
IR0 / IR1 historical revision boundary 有合理平滑处理
```

---

# 31. V1 A/B Constitution

如果只保留最重要的共同原则，就是：

1. **Chunk Size = 160m；Active Window = 3×3。**
2. **Streaming State 与 Authority State 正交。**
3. **Loaded != Committed。**
4. **Current + PROVISIONAL 可被最新 IR 重写；Historical COMMITTED 默认保留。**
5. **Future Chunk 不保存具体世界；第一次生成永远使用 latest Current IR。**
6. **GenerateChunk 必须 deterministic，且不得依赖 Chunk 生成顺序。**
7. **Committed 邻居的几何连续性优先于新 IR 的局部自由。**
8. **Compiler / World IR 不知道 Chunk。**
9. **A 生成世界；B 决定 IR 如何改写已经存在的世界。**
10. **双方通过 ChunkRecord / ResolvedChunk / GenerateChunk contract 整合，不通过共享内部状态整合。**

---

# 32. 一句话交接模型

```text
A:
IR + Coord + Seed + Boundary
        ↓
ResolvedChunk

B:
Old ResolvedChunk + New ResolvedChunk + Authority
        ↓
Revision / Diff / Transition / Commit
```

只要这个边界保持稳定，双方内部实现可以自由演进。
