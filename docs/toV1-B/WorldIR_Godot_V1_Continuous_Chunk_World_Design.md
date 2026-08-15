# WorldIR Godot V1 — Continuous Chunk World 设计规范

> **状态**：V1 Architecture Baseline  
> **基线实现**：`godot-main_V0_85`  
> **目标**：在不改变 World IR V2 Schema、尽量不增加 LLM Compiler 复杂度的前提下，将当前 160m × 160m 的单世界实现升级为可持续前进、可被 Prompt 局部改写、具有历史与未来概念的连续 Chunk 世界。  
> **核心关键词**：`160m Runtime Chunk`、`3×3 Active Window`、`Current Chunk`、`PROVISIONAL / COMMITTED`、`IR Revision`、`Deterministic Generation`、`Scene Diff Transition`、`Boundary Continuity`。

---

# 1. V1 为什么存在

V0.85 已经证明了 WorldIR 的核心 backend 路径可以成立：

```text
User Prompt
    ↓
LLM Compiler
    ↓
World IR V2
    ↓
WorldBackend.lower()
    ↓
ResolvedWorld
    ↓
SceneRuntime / SceneDiff / SceneTransition
    ↓
Playable Godot World
```

当前 V0.85 中：

- `data/configs/backend.json` 的 `world_size_m = 160`；
- `WorldBackend` 可以把一份完整 World IR lower 成具体 Region、Network、Entity、Distribution、Terrain、Water、Decoration；
- `TerrainResolver` 已经生成统一的高度场与 surface mask；
- `SceneDiff` 已经支持对象级 add / remove / move / replace；
- `SceneTransition` 已经能把一次 IR 修改表现为有动画的世界重写；
- `WorldCoordinator` 已经遵守 Candidate → Lower → Transition → Commit 的事务流程。

V0.85 的主要限制不是 IR 表达能力，而是**整个运行世界仍然等价于一个固定 160m × 160m 的 ResolvedWorld**。

V1 要解决的问题是：

> 玩家不能只在一张固定地图中修改世界，而应该可以自然地持续向前走；世界在玩家前方持续出现；Prompt 仍然能够修改玩家眼前的世界，并改变尚未成为现实的未来世界。

V1 不把这个问题推回给 Compiler。

V1 的基本判断是：

> **Chunk Streaming 是 Godot Runtime / Backend 问题，而不是 World IR 语义问题。**

因此 V1 不要求 World IR 增加：

```text
chunk_id
chunk_coord
neighbor
streaming_state
world_offset
page_id
```

也不要求 Compiler 理解：

```text
玩家在哪个 Chunk
当前加载了几个 Chunk
哪个 Chunk 已经卸载
```

Compiler 继续只处理它已经处理得很好的东西：

```text
Current World IR
+
Runtime Context
+
New Prompt
↓
New World IR
```

---

# 2. V1 的真实玩家体验目标

V1 最终希望玩家获得以下体验。

## 2.1 玩家可以自然地一直往前走

世界不再有一个明显的 160m 边界。

玩家从当前区域向任意方向移动时：

```text
Terrain 继续
Road 继续
Forest / Coast / Town surface 继续
Trees / Rocks / Grass 继续
```

邻接 Chunk 的生成不应该让玩家看到：

```text
地形裂缝
道路突然断线
树林密度形成直线边界
Chunk 切换闪烁
整张地图重新加载
```

Chunk 是运行时管理单位，而不是玩家应该感知到的世界结构。

---

## 2.2 Prompt 首先改变玩家现在所在的地方

假设玩家当前站在森林中，说：

> 树少一点，道路附近多一些房子。

Compiler 仍然得到：

```text
IR0 + Prompt → IR1
```

Godot 收到 IR1 后，首先修改玩家所在的 `Current Chunk`：

```text
Current Chunk under IR0
        ↓
Generate / Resolve under IR1
        ↓
ResolvedChunk_old vs ResolvedChunk_new
        ↓
SceneDiff
        ↓
SceneTransition
```

玩家应该看到：

```text
rewrite ripple
↓
部分树缩小 / 下沉 / 淡出
↓
新房屋出现
↓
地表或环境需要时渐变
```

也就是说：

> **Prompt 的第一视觉落点永远是玩家所处的当前世界。**

---

## 2.3 Prompt 同时改变尚未生成的未来

IR1 Commit 后，IR1 不只是当前 Chunk 的一次 patch。

它成为：

> **新的 Current IR / Active Semantic Regime。**

之后尚未 materialize 的 Chunk，都按照 IR1 生成。

例如：

```text
过去             现在              未来

IR0   IR0   |    IR1    |    IR1   IR1   IR1 ...
 C3    C4         C5          C6    C7    C8
                   ↑
                 Player
```

玩家的 Prompt 因此具有一种非常直观的效果：

> 世界从玩家所在的位置开始，被重新定义；玩家继续向前走时，新世界延续最新语义。

---

## 2.4 世界应该有“历史”

玩家已经真正经历过的地方，默认不应该因为未来每一次 Prompt 而全部重新刷新。

例如：

```text
C0 → C1 → C2 → C3
```

玩家曾经在 C0/C1/C2 行走，之后在 C3 输入 Prompt，产生 IR1。

V1 默认：

```text
C0 / C1 / C2
→ 保留它们被玩家经历时的状态

C3
→ 直接响应 IR1

C4 / C5 / ...
→ 未来按照 IR1 生成
```

因此世界不是一张永远跟随 Current IR 全局刷新的地图，而是逐渐形成：

```text
过去 / History
现在 / Present
未来 / Future
```

---

# 3. V1 的核心空间单位：160m Runtime Chunk

V0.85 已经使用：

```json
"world_size_m": 160
```

V1 直接将它正式定义为：

```text
CHUNK_SIZE_M = 160.0
```

一个 Runtime Chunk 占地：

```text
160m × 160m
```

这是一个 Godot Backend / Runtime 概念，不进入 World IR。

---

# 4. Current Chunk

玩家所在 Chunk 由玩家世界坐标直接计算。

对于玩家 XZ 坐标：

\[
p=(x,z)
\]

Chunk 坐标定义为：

\[
\boxed{
C(p)=
\left(
\left\lfloor \frac{x}{S}\right\rfloor,
\left\lfloor \frac{z}{S}\right\rfloor
\right)
}
\]

其中：

\[
S=160m
\]

代码语义应保持为纯函数：

```text
world_to_chunk(world_position) -> Vector2i
chunk_origin(chunk_coord) -> Vector2
chunk_bounds(chunk_coord) -> Rect2
```

例如：

```text
Player world position = (850, 0, 910)

current_chunk = (5,5)
```

`Current Chunk` 有两层意义：

1. Streaming 上，玩家当前真正活动的 Chunk；
2. Semantic Editing 上，新 Prompt 默认直接改写的 Chunk。

---

# 5. 3×3 Active Window

V1 第一版固定：

```text
ACTIVE_RADIUS = 1
```

因此玩家 `(cx, cz)` 周围需要保持的 Chunk 是：

\[
|x-c_x|\le1,\quad |z-c_z|\le1
\]

也就是固定 3×3：

```text
      x-1       x        x+1

z+1   NW        N         NE
z     W       CURRENT      E
z-1   SW        S         SE
```

空间范围约为：

```text
480m × 480m
```

3×3 的意义不是“九份 World IR”。

它只是：

> 玩家周围需要被 materialize / preview 的 Runtime World Window。

---

# 6. Chunk 必须有两套状态，而不是一个 loaded 标志

V1 明确区分：

```text
Streaming State
```

与：

```text
Authority State
```

这是整个 V1 最重要的设计之一。

---

# 7. Streaming State

Streaming State 回答：

> 这个 Chunk 当前为了显示和游戏运行，已经加载到什么程度？

V1 第一版采用：

```text
UNLOADED
    ↓
GEOMETRY_READY
    ↓
ENVIRONMENT_READY
    ↓
ACTIVE
    ↓
DORMANT
```

## 7.1 UNLOADED

没有实际 Scene Node。

可以只存在 `ChunkRecord`，甚至完全不存在记录。

---

## 7.2 GEOMETRY_READY

至少具备：

```text
Terrain Patch
Road / Network Geometry
Water Geometry
必要的 Persistent / Major Structure geometry
```

这一状态的核心目标是：

> 玩家远处先看到连续世界轮廓，不必立即生成所有树木和装饰。

---

## 7.3 ENVIRONMENT_READY

额外具备：

```text
Surface
Trees
Grass
Rocks
Bushes
Decorations
Environment dressing
```

已经可以作为完整视觉邻居。

---

## 7.4 ACTIVE

玩家当前所在 Chunk。

应启用完整的：

```text
Collision
Gameplay interaction
Runtime fact production
最高需要的视觉完整度
```

---

## 7.5 DORMANT

玩家已经离开。

V1 第一版可以不真正从内存卸载，只停用昂贵逻辑；后续再升级为真正 eviction / unload。

因此：

> V1 的重点首先是正确 lifecycle，不是立刻实现生产级内存 Streaming。

---

# 8. Authority State：PROVISIONAL / COMMITTED

Streaming State 不能决定 Chunk 是否允许被新的 IR 改写。

因为会出现：

```text
某个邻居 Chunk 为了视觉已经 ENVIRONMENT_READY
```

但玩家从来没有真正进入它。

如果仅仅因为它“加载过”，就把它永久锁死，会导致预加载顺序决定世界历史，这是错误的。

因此 V1 新增独立的 Authority State。

---

## 8.1 PROVISIONAL

含义：

> 为了视觉和 Streaming 提前生成，但还没有成为玩家世界中的正式历史事实。

典型对象：

```text
Current Chunk 周围的八个 Preview Chunks
```

它们即使已经：

```text
Terrain generated
Trees generated
Road generated
```

仍然可以被新的 IR Revision rebase。

---

## 8.2 COMMITTED

含义：

> 玩家已经真正进入 / 操作过这个 Chunk，它已经成为世界历史。

V1 第一版最简单的 Commit 条件：

```text
Player enters chunk
→ COMMITTED
```

后续如果玩家在 Chunk 内产生 Runtime Fact，例如：

```text
砍树
放置物件
烧毁区域
```

也应立即使该 Chunk 成为 `COMMITTED`。

---

# 9. 最关键规则：Loaded != Committed

V1 正式规定：

\[
\boxed{
Loaded \neq HistoricalFact
}
\]

具体：

| Chunk 情况 | Streaming | Authority | 新 IR 是否可以重写 |
|---|---|---|---|
| 远方未知 | UNLOADED | 无 / PROVISIONAL | 是，未来直接按最新 IR 生成 |
| 3×3 Preview | GEOMETRY/ENVIRONMENT READY | PROVISIONAL | 是 |
| Current Chunk | ACTIVE | COMMITTED | 是，本次 Prompt 的明确落点 |
| 玩家过去经过的 Chunk | DORMANT / UNLOADED | COMMITTED | 默认否 |

因此真正决定可否 rebase 的规则是：

```text
can_rebase(chunk) =
    chunk == current_chunk
    OR chunk.authority == PROVISIONAL
```

而不是：

```text
can_rebase(chunk) = not chunk.loaded
```

---

# 10. IR Revision

V1 不修改 World IR schema，但 Godot Runtime 新增：

```text
current_ir_revision: int
```

例如：

```text
IR0 → revision 0
IR1 → revision 1
IR2 → revision 2
```

每个 Chunk 记录：

```text
source_ir_revision
```

表示它当前具体世界是由哪一版 IR 生成。

建议的 `ChunkRecord` 概念结构：

```text
ChunkRecord
├── coord: Vector2i
├── streaming_state
├── authority
├── source_ir_revision
├── target_ir_revision
├── is_stale
├── resolved_chunk
└── runtime_state
```

IR Revision 完全属于 Godot。

Compiler Server 不需要知道 revision number。

---

# 11. V1 中 Current IR 的新运行时含义

World IR 仍然是一份完整语义世界描述。

但在无限 Chunk Runtime 中，`Current IR` 的运行时含义调整为：

> **Current Chunk 的编辑基准 + 尚未成为历史的未来世界的最新生成规则。**

因此不再要求：

```text
Every Historical Chunk == Current IR
```

而是：

```text
Current Chunk
→ 按 Current IR

PROVISIONAL Chunks
→ 可 rebase 到 Current IR

Unmaterialized Future
→ 将来按 Current IR 生成

Historical COMMITTED Chunks
→ 可以保留旧 IR Revision
```

这使世界能够真正拥有历史。

---

# 12. Prompt Edit 的正式 V1 行为

假设：

```text
current_chunk = (5,6)
current_ir = IR0
current_ir_revision = 0
```

玩家输入 Prompt。

Compiler 流程保持不变：

```text
IR0
+
Runtime Context
+
Prompt
↓
Compiler Server
↓
IR1
```

Server 完全不需要知道 `(5,6)`。

Godot 收到 IR1 后：

## 12.1 Current Chunk

必须立即：

```text
Generate / Resolve current chunk using IR1
↓
old ResolvedChunk vs new ResolvedChunk
↓
SceneDiff
↓
SceneTransition
↓
Commit source_ir_revision = 1
```

这是玩家眼前的世界重写。

---

## 12.2 Loaded PROVISIONAL Chunks

全部将：

```text
target_ir_revision = 1
is_stale = true
```

对于玩家明显可见 / 靠近的 Chunk：

```text
尽快 re-resolve + transition
```

对于较远 Preview：

```text
可以 lazy rebuild
```

只要玩家真正靠近之前保证它已经达到 latest revision 即可。

---

## 12.3 Historical COMMITTED Chunks

默认保持原样。

例如：

```text
Chunk(5,5)
source_ir_revision = 0
COMMITTED
```

即使 Current IR 已经变成 IR1，也不自动刷新。

---

## 12.4 尚未生成的 Chunk

不需要做任何 Scene 工作。

只需更新：

```text
current_ir = IR1
current_ir_revision = 1
```

未来首次生成：

```text
GenerateChunk(coord, IR1, revision=1, ...)
```

因此语义上已经被 IR1 改写，但没有任何浪费性的后台 refresh。

---

# 13. 世界的时间模型

V1 可以用一句非常重要的话总结：

\[
\boxed{
Future \rightarrow Preview \rightarrow Present \rightarrow History
}
\]

对应：

```text
Unmaterialized
    ↓
PROVISIONAL
    ↓
Current Chunk
    ↓
COMMITTED Historical Chunk
```

IR Edit 的作用范围：

```text
Present
→ 必须修改

Preview
→ 可以并应该 rebase

Future
→ 自动继承最新 IR

History
→ 默认保存
```

这就是 V1 的世界时间语义。

---

# 14. 基于 IR 的 Chunk 生成函数

V1 不允许每个 Chunk 独立随意 `randomize()`。

Chunk 生成必须具有明确函数模型。

核心接口：

```text
GenerateChunk(
    coord,
    world_ir,
    ir_revision,
    world_seed,
    boundary_constraints
) -> ResolvedChunk
```

形式上：

\[
\boxed{
R_c=G(c,IR,r,S,B_c)
}
\]

其中：

- `c`：Chunk coordinate；
- `IR`：当前 World IR；
- `r`：IR revision，仅用于 provenance / debugging；
- `S`：World seed；
- `B_c`：来自已存在邻居的边界连续性约束；
- `R_c`：ResolvedChunk。

---

# 15. Determinism 是 V1 的核心 Invariant

V1 正式要求：

\[
\boxed{
G(c,IR,r,S,B)=\text{deterministic}
}
\]

即：

```text
Same Chunk Coord
+ Same IR
+ Same Seed
+ Same Boundary Constraints
+ Same Backend Version / Config
=
Same ResolvedChunk
```

并且：

```text
Generate A → Generate B
```

与：

```text
Generate B → Generate A
```

不应该改变最终结果。

因此禁止核心 world generation 依赖：

```text
生成顺序
上一 Chunk 的 mutable RNG state
Time.get_ticks_*
randomize()
Frame number
```

---

# 16. Chunk 不是一个 Markov Chain

V1 明确不采用：

\[
Chunk_{n+1}=Generate(Chunk_n)
\]

因为这样会导致：

```text
从东往西生成
```

和：

```text
从西往东生成
```

得到不同世界。

正确心智模型是：

\[
\boxed{
WorldAt(p)=F(p,IR,Seed,BoundaryContext)
}
\]

Chunk 只是把这个函数在某个 160m × 160m 的窗口内 materialize。

---

# 17. Terrain 的确定性模型

Terrain 应尽量从全局 world coordinate 求值。

不要：

```text
Chunk-local x/z
+
独立随机 seed
```

而要：

\[
H(x,z)=F_H(x,z,WorldSeed,EnvironmentPolicy)
\]

第一版可以继续沿用 V0.85 `TerrainResolver` 已有的 deterministic `sin/cos + seed phase` 结构，但输入必须是真实 global position。

例如概念上：

\[
H_{base}(x,z)
=
h_0
+A_1N(x/L_1,z/L_1)
+A_2N(x/L_2,z/L_2)
\]

Region / Environment 再影响：

```text
relief
surface
coast shaping
road flattening
building pad flattening
```

这样邻接 Chunk 的边缘实际上是在对同一个全球函数采样，避免 Terrain seam。

---

# 18. Population 的确定性模型

Trees / Rocks / Decorations 不应该：

```text
for chunk:
    randomize()
    spawn N objects
```

建议把世界平面划成小 spatial cells。

对于 cell：

\[
c=(i,j)
\]

通过稳定 hash：

\[
u=Hash(WorldSeed,type,i,j)
\]

决定：

```text
候选位置 jitter
是否存在
prototype variant
rotation
scale
```

例如：

\[
TreeExists(i,j)=[u<\rho_{tree}(p)]
\]

其中 `ρ_tree(p)` 由 Current IR 的 Distribution / Region continuation policy 决定。

这样：

```text
Unload Chunk
↓
Reload Chunk
```

同一个位置仍得到同一棵程序生成树。

---

# 19. IR 不应被机械复制到每个 Chunk

“Future Chunk 强受 Current IR 约束”不等于：

> 每一个 Chunk 都完整复制 IR 中所有对象。

V1 Backend 必须区分：

## 19.1 可延续语义

适合成为 Chunk generation policy：

```text
Region environmental character
Distribution density / arrangement
Terrain character
Surface character
Network continuation
Forest dressing
Coast character
```

例如：

```text
trees inside forest density=high
```

可以继续影响未来森林 Chunk。

---

## 19.2 离散语义对象

不能自动每 Chunk 重复：

```text
church
lighthouse
research_lab
specific graveyard
specific village center
```

它们应拥有稳定 identity，只在被实际 placement 的地方存在。

因此 V1 需要一个 Backend-local `ContinuationPolicy` / generation interpretation，而不是把 World IR JSON 原样复制九次。

---

# 20. Network / Road Continuity

Road 是视觉上最重要的连续性 anchor 之一。

如果历史邻居 Chunk 已经存在 Road exit：

```text
exit_position
exit_tangent
width
```

新 Chunk 必须把它作为边界约束。

例如新 IR 不再强调 Road，也不能在边界直接：

```text
──────────│
          ↑ 突然断掉
```

而应该：

```text
──────────╮
          ╰───╮
              ╰─ gradually terminate
```

因此生成优先级为：

\[
\boxed{
Committed\ Geometry\ Continuity
>
Local\ Procedural\ Freedom
}
\]

IR 仍然是强语义约束，但不能破坏已经存在世界的基本几何连续性。

---

# 21. Boundary Constraints

`B_c` 至少可以包含：

```text
Terrain edge heights
Terrain edge slope / normal hint
Road exit point
Road exit tangent
Road width
Water / shoreline continuation
Surface influence weights
```

第一版不需要构建通用 Constraint Solver。

只需要针对实际出现的 Terrain / Road / Surface 做明确规则。

---

# 22. 两类 Transition

V1 最终同时存在两种完全不同的 Transition。

## 22.1 Temporal Transition — 世界在玩家眼前被 Prompt 改写

发生在：

```text
Current Chunk
```

使用 V0.85 已经存在的：

```text
SceneDiff
+
SceneTransition
```

负责：

```text
add / remove / move / replace
rewrite ripple
object fade / grow / sink
```

回答：

> “神正在改写我眼前的世界”应该怎么看起来？

---

## 22.2 Spatial Transition — 不同 Revision / Environment 之间不能出现 Chunk seam

发生在：

```text
Historical IR0 Chunk
|
Current/Future IR1 Chunk
```

建议第一版：

```text
TRANSITION_BAND_M = 16m
```

Population 可使用：

\[
w(d)=smoothstep(0,T,d)
\]

\[
\rho(d)=(1-w)\rho_{old}+w\rho_{new}
\]

Surface / Ground 可以进行 influence blend。

Lighting / Fog 等环境参数也可渐变。

Terrain Geometry 优先通过 global deterministic field / boundary conditions 保证连续，而不是简单 crossfade 两张 Terrain。

---

# 23. Geometry 与 Environment 的边界

Owen 原型中很有价值的一条原则应被 V1 吸收：

> **Geometry 可以理解成世界的历史骨架；Environment 可以理解成世界当前状态。**

但 V1 不把它绝对化。

建议逐步形成：

```text
Geometry / Persistent Layer
├── terrain structural heights
├── road continuity
├── coastline structural geometry
└── committed major structure placement

Environment / Regenerable Layer
├── surface appearance
├── trees
├── grass
├── bushes
├── rocks
├── decorations
├── lighting
├── fog
└── weather
```

普通 Prompt 例如：

> 树少一点。

应尽量只触发 Environment Diff。

而不是重新生成整张 Terrain。

V0.85 当前 `TerrainResolver` 仍然会受到 forest mask、road、building 的影响，因此 V1 开发过程中需要逐渐把：

```text
Terrain Geometry
```

与：

```text
Terrain Surface / Environment
```

解耦。

但 V1 第一阶段不要求一次完成全部重构。

---

# 24. Chunk Manager 的职责

V1 新增核心 runtime subsystem：

```text
ChunkManager
```

概念职责：

```text
ChunkManager
├── chunk_size = 160
├── active_radius = 1
├── current_chunk_coord
├── current_ir
├── current_ir_revision
├── chunks
│
├── update_player_chunk()
├── ensure_active_window()
├── materialize_chunk()
├── promote_to_current()
├── commit_chunk()
├── apply_ir_revision()
├── rebase_provisional_chunks()
├── ensure_latest_revision()
└── evict_distant_chunks()
```

ChunkManager 不负责：

```text
理解自然语言
调用 LLM Planning
决定 World IR schema
具体画 Mesh
Scene object transition implementation
```

它负责的是：

> **哪块世界应该存在、哪一版 IR 应该统治它、它现在是不是历史。**

---

# 25. WorldCoordinator 在 V1 中的角色

V0.85 的 `WorldCoordinator` 继续保留事务责任。

但它不应该自己变成巨型 Streaming Manager。

推荐：

```text
WorldCoordinator
    ↓
Compiler Client
    ↓
IR1 Candidate
    ↓
ChunkManager.apply_ir_revision(IR1)
    ↓
Current Chunk candidate generation
    ↓
SceneDiff / Transition
    ↓
Success
    ↓
Commit WorldState + IR Revision
```

也就是说：

> Coordinator 负责事务；ChunkManager 负责空间时间状态。

---

# 26. V1 的完整运行流程

## 26.1 初次生成

```text
Prompt
↓
Compiler
↓
IR0
↓
current_ir = IR0
revision = 0
↓
Generate Current Chunk
↓
Materialize 3×3 Active Window
↓
Center = ACTIVE + COMMITTED
Neighbors = PROVISIONAL
```

---

## 26.2 玩家移动到邻居 Chunk

```text
Player crosses 160m boundary
↓
world_to_chunk(player.position)
↓
new current chunk
↓
previous current stays COMMITTED
↓
new current PROVISIONAL → COMMITTED / ACTIVE
↓
3×3 Active Window shifts
↓
new outer row materialized using Current IR
```

---

## 26.3 玩家输入 Prompt

```text
Current IR0
+
Prompt
+
Runtime Context
↓
Compiler
↓
IR1 Candidate
↓
Current Chunk re-resolve under IR1
↓
SceneDiff / Temporal Transition
↓
visible PROVISIONAL neighbors mark/rebase to IR1
↓
Commit
↓
current_ir = IR1
revision = 1
```

---

## 26.4 玩家继续前进

```text
Unknown Chunk enters Active Window
↓
GenerateChunk(coord, IR1, seed, boundary_constraints)
↓
PROVISIONAL preview
↓
Player enters
↓
COMMITTED history
```

如此持续循环。

---

# 27. V1 的非目标

为了防止 scope 失控，正式 V1 第一阶段不要求：

```text
LLM Compiler 理解 Chunk
World IR 增加 Chunk Schema
1 IR = 1 Chunk
Semantic Page stitching
真正生产级 async thread pool
完整内存预算器
LOD / HLOD
远程 Chunk persistence service
多人同步
无限语义新颖性
每走若干 Chunk 自动调用 LLM
复杂 biome simulation
通用 constraint solver
```

这些可以在 V1 之后根据真实需求继续扩展。

---

# 28. V1 最重要的 Invariants

以下规则应该进入代码注释和测试，而不是只留在设计文档。

## Invariant 1 — 160m Chunk

```text
CHUNK_SIZE_M = 160.0
```

V1 不允许 runtime 各处散落不同 Chunk size。

---

## Invariant 2 — Chunk Coordinate 是纯函数

\[
C(p)=floor(p/160)
\]

同一位置永远映射到同一 Chunk。

---

## Invariant 3 — Generation Order Independent

```text
Generate A then B
==
Generate B then A
```

---

## Invariant 4 — Reload Determinism

```text
Generate Chunk
→ Unload
→ Generate Again
```

在输入未变时应得到相同 ResolvedChunk。

---

## Invariant 5 — Loaded != Committed

Preview Chunk 可以已经完整显示，但仍然可被新 IR rebase。

---

## Invariant 6 — Current Chunk Always Receives New IR

只要 Compile transaction 成功，新 IR 必须首先改变玩家当前 Chunk。

---

## Invariant 7 — Future Uses Latest IR

尚未 materialize 的 Chunk 不需要 refresh；它们未来第一次生成时必须使用最新 `current_ir_revision`。

---

## Invariant 8 — Historical Chunk Is Preserved by Default

玩家已经 Commit 的旧 Chunk 不因普通 Prompt 自动全局刷新。

---

## Invariant 9 — Committed Boundary Continuity Wins

新 Chunk 不能为了完全服从新 IR 而制造明显 Terrain / Road 几何断裂。

---

## Invariant 10 — Compiler Remains Chunk-Agnostic

Compiler API 继续只接收：

```text
prompt
current_ir
runtime_context
```

V1 Chunk 信息不进入 Server contract。

---

# 29. V1 成功时应该看到什么

如果 V1 做对，比赛 Demo 中应该能出现这样的连续体验：

1. 玩家出生在 Compiler 根据 Prompt 生成的 160m 世界中；
2. 玩家向森林深处走，世界没有边界，Terrain / Road / Tree 自然继续；
3. 玩家跨过多个 160m Chunk，但看不到 Chunk seam；
4. 周围 3×3 Chunk 会提前存在，因此不会走到地图尽头才突然生成；
5. 玩家在某个新 Chunk 说“树少一点，道路旁增加房屋”；
6. 当前 Chunk 立即以 V0.85 的 Scene Diff 动画被改写；
7. 玩家前方已经 preview 的 Chunk 也逐渐 rebase 到新 IR；
8. 玩家继续向前时，新出现的世界天然延续“树少、房屋更多”的新规则；
9. 玩家回头时，曾经走过的旧世界仍然保留旧状态，形成可感知的世界历史；
10. 新旧历史之间没有生硬 160m 直线边界，而是通过 terrain continuity、surface blending、population transition 自然连接。

这就是 V1 真正的目标。

---

# 30. 一句话定义 WorldIR Godot V1

> **V1 将 V0.85 的单个 160m IR 驱动世界升级为一个以 160m Runtime Chunk 为单位、玩家周围维持 3×3 Active Window、区分 Preview 与 History、以最新 World IR 统治 Present/Future、并通过确定性生成与 Scene Transition 实现可持续行走和可持续改写的连续世界。**
