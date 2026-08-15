# WorldIR Godot V1 — A/B Integration Constraints Addendum

> **状态**：V1 Parallel Development Integration Addendum  
> **适用基线**：`godot-main_V0_85`  
> **适用对象**：A（Chunk / Streaming / Generation）与 B（IR Revision / Rebase / Transition）  
> **依赖文档**：
>
> - `WorldIR_V1_AB_Shared_Development_Contract.md`
> - `WorldIR_Godot_V1_Continuous_Chunk_World_Design.md`
> - `WorldIR_V1_B_IR_Revision_Rebase_Transition_Requirements.md`
> - `WorldIR_Godot_Server_API_Contract_V0.md`
>
> **本文目的**：补齐并发开发开始前仍存在歧义、容易导致后续 merge 冲突的接口、状态 ownership、事务边界与性能约束。
>
> 若本文与 A/B Shared Contract 冲突，除明确标记为“补充 / 收紧”的部分外，仍以 Shared Contract 为准。本文主要针对 Shared Contract 尚未完全定义的 integration seam。

---

# 1. 本补充件解决什么问题

现有共同契约已经确定：

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

并明确：

```text
A 负责：
Chunk / Streaming / Deterministic Generation

B 负责：
IR Revision / Rebase / Transition
```



但真正并发实现时还有几个必须提前冻结的问题：

```text
1. Prompt 发出后玩家移动，哪个 Chunk 才是这次 Prompt 的目标？
2. Candidate Revision 在 commit 前能不能修改正式 ChunkRecord？
3. Runtime Binding / Spatial Payload 如何进入 GenerateChunk？
4. source_revision / target_revision / authority 等字段究竟谁写？
5. ResolvedChunk ID 如何保证 SceneDiff 不退化成 full remove + add？
6. IR Revision 是否可以一次同步重建 3×3？
7. Current Chunk 与 Preview Chunk 是否使用同一种 Scene Transition？
8. A/B 都可能需要修改 SceneRuntime，接口到底怎么冻结？
9. Stale Chunk 遇到连续 IR1 → IR2 → IR3 时如何处理？
10. Preview rebuild 失败是否应该导致整个 Revision rollback？
```

本文正式固定这些问题。

---

# 2. 三层状态模型必须保持

A/B 后续讨论与代码中统一采用：

```text
① Semantic / Design State
   current_ir
   current_ir_revision

              ↓

② Chunk Resolution State
   ChunkRecord
   ├── coord
   ├── streaming_state
   ├── authority
   ├── source_ir_revision
   ├── target_ir_revision
   └── resolved_chunk

              ↓

③ Physical Scene State
   ChunkRoot
   └── Godot Nodes / Mesh / Collision
```

正式原则：

> **World IR 是 Design Truth。**  
> **ResolvedChunk 是 Spatial Truth。**  
> **SceneTree 是 Presentation / Runtime State。**

不得通过读取 SceneTree 反推出正式：

```text
IR Revision
Authority
Semantic ownership
Chunk provenance
```

这一模型延续 V0 中：

```text
World IR
→ Resolved World
→ Scene Runtime
```

的三层架构，只是 V1 将 Resolved World 进一步拆成 Chunk。

---

# 3. Prompt Transaction Target 必须在提交时捕获

这是新增的强制约束。

当玩家提交 Prompt 时，B 从 A 读取一次：

```text
transaction_chunk_coord =
    A.get_current_chunk_coord()
```

之后整个 Compiler transaction 中：

```text
transaction_chunk_coord
```

保持不变。

即使 Compiler 请求期间：

```text
玩家继续移动
current_chunk_coord 改变
Active Window 改变
```

本次 Prompt 仍作用于：

```text
transaction_chunk_coord
```

而不是 Compiler Response 回来时新的 Current Chunk。

---

## 3.1 原因

Compiler 请求可能持续数秒。

如果使用：

```text
response 到达时的 current_chunk
```

则同一句 Prompt 的空间作用对象会依赖：

```text
网络延迟
LLM latency
玩家移动速度
```

这是不可接受的非确定行为。

---

# 4. Transaction Target 在事务期间必须被 Pin

A 必须提供等价能力：

```gdscript
pin_chunk(coord)
unpin_chunk(coord)
```

实际 API 名称可以不同。

语义：

```text
被某个 Revision Transaction 使用的 Chunk
在事务结束前
不得 eviction / destroy / lose authoritative ChunkRecord
```

允许：

```text
ACTIVE → DORMANT
```

但不能因为离开 Active Window 就把 transaction target 的必要数据销毁。

---

## 4.1 Pin 不等于 Current

玩家可以：

```text
提交 Prompt at C5
↓
移动到 C6
```

此时：

```text
Current Chunk = C6
Transaction Target = C5
```

完全合法。

C5 应继续完成本次 revision transaction。

---

# 5. Candidate Revision 不得提前污染正式 ChunkRecord

这是 B/A merge 时必须共同遵守的最重要事务规则之一。

假设：

```text
current_revision = 3
candidate_revision = 4
```

在 Current Chunk Transition 成功之前：

```text
不得把正式 ChunkRecord.target_ir_revision 永久改成 4
不得把正式 current_ir 改成 IR4
不得把正式 current_ir_revision 改成 4
不得把正式 PROVISIONAL Chunk 标成 revision 4 的长期 stale
```

Candidate Revision 必须存在于：

```text
RevisionPlan
Candidate ResolvedChunk
Candidate Scene
temporary data
```

而不是提前进入正式 Runtime State。

这延续现有 Server Contract 的核心原则：

```text
Server response
≠
immediate commit
```



---

# 6. Revision 正式 Commit Point

正式 commit 条件：

```text
Candidate IR valid
AND
Candidate Current ResolvedChunk generated
AND
Candidate Scene build succeeds
AND
SceneDiff prepared
AND
Current Chunk Transition completes successfully
```

之后才能执行：

```text
current_ir = candidate_ir
current_ir_revision = candidate_revision
```

并更新正式 Chunk records。

---

# 7. PREPARE / APPLY / COMMIT 三阶段

A/B 后续代码与 debug 统一采用以下 transaction 心智模型：

```text
STABLE
  ↓
CAPTURE
  ↓
COMPILE
  ↓
PREPARE
  ↓
APPLY
  ↓
COMMIT
  ↓
STABLE
```

---

## 7.1 PREPARE

允许失败。

包括：

```text
Compile Result validation
Candidate Runtime Facts
RevisionPlan
Boundary Constraint collection
Generate candidate Current Chunk
Build Candidate Scene
Calculate SceneDiff
Validate required resources
```

PREPARE 失败：

```text
正式状态完全不变
```

---

## 7.2 APPLY

执行：

```text
Old Current Chunk Scene
→
New Current Chunk Scene
```

的视觉 transition。

设计原则：

> **所有合理可预知的失败都应该在 APPLY 前发生。**

不要设计成：

```text
动画播放到 60%
↓
发生正常业务错误
↓
要求复杂 reverse rollback
```

---

## 7.3 COMMIT

Transition 完成后：

```text
Current IR
Revision
Runtime Facts
Chunk source/target revision
```

一次性推进。

---

# 8. Current Transaction 与 Preview Rebuild 是两个 Failure Domain

正式规定：

## 8.1 Transaction Critical Path

只有：

```text
transaction target Chunk
```

属于 Revision Commit 的强事务路径。

它失败：

```text
整个 candidate revision 不 commit
```

---

## 8.2 Post-Commit Preview Rebuild

Revision 已成功 commit 后：

```text
PROVISIONAL Chunk rebuild
```

属于 eventually-consistent background work。

如果某 Preview Chunk 重建失败：

```text
Current IR 不 rollback
current_ir_revision 不 rollback
已成功 Current Chunk 不 rollback
该 Chunk 继续保持 stale
可以 retry / log
```

不得因为：

```text
一个 Preview Chunk rebuild failure
```

把已经完成的 IR Revision 全局退回旧版本。

---

# 9. Revision Commit 后才更新 PROVISIONAL Target Revision

正式推荐顺序：

```text
IR3
↓
Candidate IR4
↓
只准备 Transaction Target Chunk
↓
Current transition success
↓
Commit revision = 4
↓
此时才：
    PROVISIONAL.target_revision = 4
```

这样可以避免 Candidate Revision 最终失败时，还需要大量 rollback Preview metadata。

---

# 10. Stale 的唯一判断来源

建议不把：

```text
is_stale
```

作为独立可写状态。

正式语义：

```text
is_stale =
    source_ir_revision != target_ir_revision
```

如果为了兼容已有 `ChunkRecord` 仍保留字段，则它只能是：

```text
derived / synchronized field
```

不得存在：

```text
source = 2
target = 3
is_stale = false
```

这类状态。

Shared Contract 已允许 `is_stale` 由 revision comparison 计算。

---

# 11. Revision Coalescing

如果某 PROVISIONAL Chunk：

```text
source_revision = 0
```

依次经历：

```text
IR1 commit
IR2 commit
IR3 commit
```

但始终没有实际 rebuild，则：

```text
target_revision
0 → 1 → 2 → 3
```

最终只需要：

```text
GenerateChunk(... IR3 ...)
```

禁止强制：

```text
IR0 → IR1 → IR2 → IR3
```

逐版 materialize。

因此：

> **PROVISIONAL Chunk 只追求 Latest Target Revision，不追求 Revision Replay。**

---

# 12. GenerateChunk Contract 补充：Generation Overrides

现有 Shared Contract：

```text
GenerateChunk(
    coord,
    world_ir,
    ir_revision,
    world_seed,
    boundary_constraints
) -> ResolvedChunk
```



需要增加一个可选、默认空的 transaction-local 参数：

```text
generation_overrides
```

推荐概念签名：

```gdscript
func generate_chunk(
    coord: Vector2i,
    world_ir: Dictionary,
    ir_revision: int,
    world_seed: int,
    boundary_constraints: ChunkBoundaryConstraints,
    generation_overrides = {}
) -> ResolvedChunk
```

---

# 13. Generation Overrides 的正式语义

第一版至少用于承载：

```text
runtime_bindings
runtime spatial payload references
transaction-local lowering hints
```

概念结构：

```text
GenerationOverrides
├── runtime_bindings
└── spatial_payloads
```

实际类型可以由实现决定。

---

# 14. 为什么 GenerateChunk 必须支持 Overrides

Compiler Server API 已明确支持：

```text
runtime_bindings
```

例如：

```text
graveyard
↔
clearing_01
```

要求 Backend 利用 Godot 本地保存的真实 spatial payload 完成 placement。

Runtime Binding：

```text
是一次性 lowering hint
不进入 World IR
消费后消失
```



因此如果 `GenerateChunk()` 完全只接收：

```text
World IR
```

则无法完整实现现有 Compiler Contract。

---

# 15. Generation Overrides 不进入 Deterministic Global World State

Generation Overrides：

```text
不是 World IR
不是 Chunk metadata
不是 Future generation policy
不是持久化 revision state
```

只属于当前 transaction 的 lowering context。

因此：

```text
默认 = empty
```

绝大部分普通 Preview / Future generation：

```text
GenerateChunk(... generation_overrides = {})
```

---

# 16. Runtime Binding 的 Chunk Scope

Runtime Binding 不允许被无条件广播到所有 Chunk。

规则：

> **Binding 只能在其真实 Spatial Payload 所属 / 相交的 Chunk 中被消费。**

第一版如果 Runtime Fact 明确只发生在 transaction target Chunk，则可以简化为：

```text
bindings only passed to transaction_chunk_coord
```

未来如果一个 spatial payload 跨多个 Chunk，再由 Godot Backend 明确拆分或查询 intersection。

禁止：

```text
IR1 arrives
↓
所有 3×3 Chunk
都消费同一个 runtime binding
```

---

# 17. ChunkRecord 字段 Ownership

为了避免 A/B 同时直接 mutate 同一个 record，正式固定：

| 字段 | Ownership | 说明 |
|---|---|---|
| `coord` | A | 创建后 immutable |
| `streaming_state` | A | Streaming lifecycle 唯一写方 |
| `authority` | A | Player entry / runtime history promotion 由 A 写 |
| `resolved_chunk` | A | A 在 materialize / successful install 后替换 |
| `source_ir_revision` | A | 与实际 installed `resolved_chunk` 同步 |
| `target_ir_revision` | B 决策，A API 执行 | B 不直接摸 A 私有数据结构 |
| `is_stale` | Derived | 不建议独立写 |
| `current_ir` | B / WorldState | A 只读取 |
| `current_ir_revision` | B / WorldState | A 只读取 |

---

# 18. “B 决策，A API 执行”的含义

B 生成：

```text
RevisionPlan
```

例如：

```text
C5 MUST_REBASE
C6 TARGET_REVISION 4
C7 PRESERVE
```

但 B 不应：

```gdscript
chunk_manager._chunks[C6].target_ir_revision = 4
```

而应调用类似：

```text
A.set_target_revision(C6, 4)
A.mark_target_latest(C6, 4)
A.request_rebuild(C6, ...)
```

这样 A 保持：

```text
ChunkRecord lifecycle ownership
```

B 保持：

```text
Revision policy ownership
```

---

# 19. Authority State 只由 A 改

B 可以读取：

```text
PROVISIONAL
COMMITTED
```

并用它生成 RevisionPlan。

但 B 不应在 Prompt transaction 中自行：

```text
PROVISIONAL → COMMITTED
```

COMMITTED 的基础触发仍然是：

```text
Player enters Chunk
```

由 A 的 player/chunk lifecycle 处理。

Current Chunk 对 Revision 可写只是 policy exception：

```text
COMMITTED + transaction target
→ rebase allowed
```

而不是修改 authority。

---

# 20. ResolvedChunk 必须保持 Value Data

ResolvedChunk：

```text
不能保存 live Node
不能保存 Node3D
不能保存 RID
不能保存 live MeshInstance reference
```

保持：

```text
Vector
Transform
PackedArray
Dictionary
Resource-like value data
```

这一点继续遵循现有 ResolvedWorld contract。

---

# 21. ResolvedChunk 与现有 ResolvedWorld 的兼容原则

为了降低 merge 风险：

> **不要为了 Chunk V1 完全重新设计一套与 ResolvedWorld 无关的数据格式。**

推荐：

```text
ResolvedChunk
≈
现有 ResolvedWorld 的 chunk-scoped 版本
```

至少保持：

```text
regions
networks
entities
distributions
terrain
water / environment
```

的内部 value-data 思维尽可能一致。

增加：

```text
coord
bounds
revision
```

即可。

这样现有：

```text
SceneDiff
SceneTransition
SceneRuntime builders
```

更容易复用。

---

# 22. Stable Identity Contract

这是 A 对 B 最重要的生成质量 contract 之一。

对于相同世界中逻辑上仍然存在的对象：

```text
IR0 → IR1
```

如果对象没有被真正删除 / 替换，它的 resolved identity 应尽量保持稳定。

否则：

```text
SceneDiff
```

会退化为：

```text
remove everything
+
add everything
```

B 文档已经明确要求 Stable ID Diff。

---

# 23. Identity 不得包含 Revision

禁止：

```text
tree:r0:001
tree:r1:001
```

这种 ID。

因为 Revision 改变不代表对象 identity 改变。

---

# 24. Runtime Global Identity

推荐逻辑：

```text
GlobalRuntimeObjectID =
    ChunkCoord
    +
    LocalResolvedID
```

例如：

```text
chunk(5,6) / church

chunk(5,6) / trees:cell_42_73
```

---

# 25. Distribution Instance Identity

长期推荐基于稳定空间候选：

```text
distribution semantic id
+
global spatial cell / deterministic candidate id
```

例如：

```text
trees:cell_42_73
trees:cell_43_73
```

而不是只依赖：

```text
trees:000
trees:001
```

因为 density 变化、排序变化后：

```text
index based ID
```

很容易导致大量 identity shift。

A 可以自由选择具体 hash / cell 算法，但必须满足：

> **未被语义修改、仍然存在的实例应尽量保持 ID 与 Transform 稳定。**

---

# 26. GenerateChunk 仍必须保持 Determinism

Generation Overrides 为空时，原 contract 不变：

```text
Same:
coord
IR
revision
seed
boundary constraints
backend config

→ Same ResolvedChunk
```

并保持 generation order independence。

Overrides 非空时：

```text
Same Overrides
```

也应纳入 Same Inputs 的定义。

---

# 27. Revision Critical Path 只允许一个 Chunk

第一版性能 contract：

> **一次 Prompt Revision 的同步 critical path 只强制生成 transaction target Chunk。**

即：

```text
Compile
↓
Generate Transaction Target
↓
Build Candidate
↓
Diff / Transition
↓
Commit
```

不要在 Revision Commit 前同步：

```text
Generate 3×3
```

---

# 28. PROVISIONAL Rebuild 必须 Deferred

Revision 成功后：

```text
PROVISIONAL
target_revision = latest
```

然后交给 A 的调度器渐进 rebuild。

第一版推荐：

```text
max_provisional_rebuilds_in_flight = 1
```

不是强制具体数字，但禁止默认：

```text
8 个 Preview Chunk 同帧全量 rebuild
```

原因是现有 Scene Runtime generation 包括：

```text
Terrain Mesh
Terrain Collision
Road
Entity
Distribution
Decoration
```

并且 candidate transition 阶段 old/new scene 可能短暂同时存在。

因此 Preview rebuild 必须避免制造明显 CPU / memory spike。

---

# 29. B 不负责 Preview Scheduler

B 只表达：

```text
target_revision
priority class / semantic urgency（若需要）
```

A 决定：

```text
什么时候实际 rebuild
一次算几个
怎么排队
什么时候 mount
```

RevisionPlan 不应演变成：

```text
Streaming Scheduler
```

---

# 30. Preview Rebuild 必须支持 Latest-Wins

如果某 Chunk rebuild IR1 正在排队：

```text
target = 1
```

但在真正开始前 IR2 commit：

```text
target = 2
```

旧的 IR1 pending work 应允许：

```text
cancel / supersede / skip
```

不应该强制先算 IR1。

如果已经开始 generation，可以允许完成后立即判 stale，但第一版优先考虑：

```text
queued work latest-wins
```

---

# 31. Player Entry Barrier

Shared Contract 已规定：

> 玩家正式进入 Chunk 前必须 latest。

A 必须提供等价于：

```text
ensure_latest(coord)
```

的 barrier。

当玩家准备从：

```text
C5 → C6
```

而：

```text
C6.source_revision != C6.target_revision
```

必须在 C6 成为正式 Current / gameplay-authoritative Chunk 前完成 latest generation。

具体可以：

```text
提前高优先 rebuild
短暂阻止 promotion
或其它实现
```

但不得让：

```text
stale Chunk 先变 Current
之后再慢慢修
```

---

# 32. Current / Preview / Future 三类 Scene 路径必须分离

正式建议 Scene Runtime 暴露三种语义不同的路径：

```text
mount_chunk(...)
transition_chunk(...)
unmount / deactivate_chunk(...)
```

其中：

## Initial / Streaming Materialization

```text
ResolvedChunk
→ mount_chunk
```

不属于 IR Rewrite。

## Revision Rewrite

```text
old ResolvedChunk
+
new ResolvedChunk
→ transition_chunk
```

属于 B。

Shared Contract 已明确要求首次 materialization 与 rewrite 分离。

---

# 33. Current 与 Preview Transition 不要求相同视觉成本

正式允许：

## Transaction Target

```text
FULL_REWRITE_TRANSITION
```

可以包含：

```text
rewrite ripple
spatial stagger
grow
sink
move tween
crossfade
```

## Visible PROVISIONAL

```text
LIGHT_REBASE_TRANSITION
```

例如：

```text
short fade
group crossfade
environment blend
```

## Far / Non-visible PROVISIONAL

允许：

```text
SILENT_REBUILD
```

不得把：

```text
Current 的完整 Tween
```

强制套给全部 Preview Chunk。

---

# 34. SceneRuntime Shared Interface Freeze

`scene_runtime.gd` 是 A/B 可能共同触碰的高风险 Shared 文件。

正式冻结方向：

```gdscript
mount_chunk(
    chunk_root,
    resolved_chunk
)

transition_chunk(
    chunk_root,
    old_resolved_chunk,
    new_resolved_chunk,
    transition_mode
)

remove_chunk(
    chunk_root
)
```

实际命名可以在实现前一次性确定。

关键约束：

> **SceneRuntime 不再自行假设世界永远只有一个 `WorldRoot/GeneratedWorld`。**

Chunk Root 必须显式传入或由稳定 Chunk handle 指定。

---

# 35. SceneDiff 不负责寻找 Chunk

SceneDiff 应继续是：

```text
ResolvedChunk old
vs
ResolvedChunk new
→ Diff data
```

不要让 SceneDiff：

```text
搜索 SceneTree
判断 player current chunk
读取 ChunkManager
```

保持其纯数据比较性质。

---

# 36. SceneTransition 不负责 Revision Policy

SceneTransition 只负责：

```text
这个 Diff 怎么动画
```

它不判断：

```text
Historical 能不能重写
Provisional 是否 stale
Current Revision 是多少
```

这些属于 B Revision layer。

---

# 37. Boundary Constraints 与 Revision Transition 严格分工

Shared Contract 已定义：

```text
Geometry continuity
→ A / Boundary Constraints

Revision visual blending
→ B / Transition policy
```



因此：

## A

负责至少：

```text
Terrain shared edge
Road exit
Road tangent
Road width
```

## B

负责：

```text
tree density blend
grass / rock population blend
surface visual blend
fog / lighting / environment transition
```

---

# 38. B 不会修改 Historical Geometry

B 的 Revision Boundary Transition：

```text
不改变 Historical.authority
不改变 Historical.source_revision
不把 Historical regenerate 成 latest IR
```

Transition Band 只是视觉 reconcile。

这一点必须保持。

---

# 39. A 不得隐式根据 Latest IR 修改 Historical Chunk

即使 A 的 generator / ChunkManager 可以访问：

```text
current_ir
```

也不能在：

```text
Historical COMMITTED Chunk reload
```

时自动用 latest IR 重新生成。

Historical reload 必须使用它自己的：

```text
source revision 对应世界状态 / persisted resolved data
```

或者其它能够保持历史的机制。

第一版如果 Historical Chunk 暂不真正 eviction，可以避免完整 persistence 问题。

---

# 40. Future Chunk 不需要 Revision Record

未 materialize 的 Chunk：

```text
不要求建立无限 ChunkRecord
不要求 target revision table
```

第一次进入 generation 时直接使用：

```text
latest committed current_ir
latest committed current_ir_revision
```

这一点保持 Shared Contract 原定义。

---

# 41. Compiler Contract 不因本补充件改变

仍然保持：

```text
prompt
current_ir
runtime_context
```

请求。

不发送：

```text
chunk_coord
player_xyz
active_window
revision number
```

Server 继续返回完整：

```text
world_ir
runtime_bindings
runtime_fact_ops
```

Chunk 与 Revision 是纯 Godot Runtime 解释。

---

# 42. A/B Shared File Ownership

为了降低 merge 冲突：

## A 主改

```text
scripts/chunk/
scripts/backend/ 与 deterministic generation 直接相关部分
```

## B 主改

```text
scripts/revision/
scripts/app/world_coordinator.gd
scripts/runtime/scene_diff.gd
scripts/runtime/scene_transition.gd
```

## 高风险 Shared

```text
scripts/runtime/scene_runtime.gd
scripts/resolved/*
scripts/app/world_state.gd
main.tscn
```

---

# 43. Shared 文件修改规则

对于高风险 Shared 文件：

> **先冻结接口，再各自实现。**

特别是：

```text
ResolvedChunk shape
SceneRuntime chunk APIs
ChunkManager revision APIs
WorldState revision fields
```

一旦双方开始编码后，不应在自己分支无通知地：

```text
改函数参数
改 return shape
改字段语义
重命名共享 enum
```

---

# 44. A 必须向 B 暴露的最小接口

整合前至少要有语义等价能力：

```text
get_current_chunk_coord()

get_record(coord)

get_active_records()

pin_chunk(coord)
unpin_chunk(coord)

generate_chunk(
    coord,
    ir,
    revision,
    seed,
    boundary_constraints,
    generation_overrides={}
)

set_target_revision(coord, revision)

request_rebuild(coord, revision)

ensure_latest(coord)
```

具体命名可以由 A 决定一次，但能力不能缺失。

---

# 45. B 不应依赖 A 的内部细节

B 不读取：

```text
private chunk dictionary layout
terrain cache
RNG
population cell cache
road continuation mutable state
streaming queue internals
```

B 只通过公开 contract 请求结果和状态。

---

# 46. A 不应依赖 B 的 Revision 内部实现

A 不需要知道：

```text
RevisionPlan class 怎么拆
SceneDiff 如何计算
Transition tween 参数
Compiler transaction state machine 内部结构
```

A 只需要遵守：

```text
正式 revision state
target revision request
GenerateChunk input
```

---

# 47. Revision Debug Log 共同格式建议

每次 Prompt transaction 至少能打印：

```text
Revision:
    from_revision
    candidate_revision
    transaction_chunk_coord

Plan:
    MUST_REBASE
    TARGET_LATEST
    PRESERVE

Result:
    PREPARE_OK / FAILED
    APPLY_OK / FAILED
    COMMIT / ABORT
```

每个 Active Chunk 至少可查询：

```text
coord
streaming_state
authority
source_revision
target_revision
stale
```

这样 merge 后可以直接判断问题属于：

```text
Streaming
Generation
Revision Routing
Scene Transition
```

哪一层。

---

# 48. 新增 Integration Tests

除现有 Shared Tests 外，追加：

## I-T1 Prompt Target Capture

```text
submit prompt at C5
move to C6 before response
```

结果：

```text
transaction applies to C5
```

---

## I-T2 Transaction Pin

Transaction target 离开 Active Window：

```text
不得在 transaction 完成前 eviction
```

---

## I-T3 Candidate Does Not Pollute Records

Candidate revision 失败：

```text
current revision unchanged
PROVISIONAL target revisions unchanged
```

---

## I-T4 Runtime Binding Scope

绑定属于 C5：

```text
C5 generation receives binding
C6/C7 generation does not
```

---

## I-T5 Stable Instance Identity

IR0 → IR1 只降低 tree density：

```text
保留下来的 tree IDs 尽可能稳定
```

不得全部变成 remove + add。

---

## I-T6 Revision Coalescing

```text
source=0
target=1
未 rebuild
IR2 commit
```

结果：

```text
target=2
只需要生成 IR2
```

---

## I-T7 Preview Failure Isolation

IR1 已 commit。

某 Preview rebuild 失败：

```text
current revision stays IR1
Preview remains stale
```

---

## I-T8 No Stale Entry

玩家进入 stale Chunk 前：

```text
ensure_latest
```

完成。

---

## I-T9 Historical Reload Preservation

Historical IR0 Chunk 即使 Current IR=IR2：

```text
不得自动使用 IR2 regenerate
```

---

## I-T10 Chunk-Scoped Scene Transition

C5 transition：

```text
不得意外 mutate C4/C6 Scene roots
```

---

# 49. 性能 Baseline

V1 第一版不追求生产级 streaming optimization，但需要保证：

```text
一次 Prompt
不会因为 3×3 rebase
产生明显同步 CPU spike
```

因此正式 baseline：

```text
Current transaction
→ synchronous / critical

Preview rebase
→ deferred

Future
→ on-demand
```

Preview scheduler 第一版允许非常保守。

正确性优先于 aggressive concurrency。

---

# 50. 不允许的性能“优化”

A/B 都不要为了性能提前破坏确定性：

禁止：

```text
基于 frame time 改随机结果
因为线程完成顺序改变世界
因为 Chunk 生成顺序改变道路 / population
为节省重算而使用未版本化 mutable generator state
```

最终仍必须保持：

```text
Same Inputs
→ Same ResolvedChunk
```



---

# 51. 五条 Integration Constitution

如果最终只保留本文五条约束，就是：

1. **Prompt 作用于提交瞬间捕获的 Transaction Chunk，不随玩家移动漂移。**
2. **Candidate Revision 在 Current Transition 成功前不得污染正式 WorldState / ChunkRecord。**
3. **Runtime Binding 通过 transaction-local Generation Overrides 进入 GenerateChunk，不进入 World IR，也不广播到所有 Chunk。**
4. **Stable Instance Identity 必须跨 Revision 尽量保持；Revision 永远不是对象 identity 的一部分。**
5. **Current Revision 是同步事务；Preview 是 eventually consistent；Historical 默认 preserve。**

---

# 52. A/B 最终数据流

```text
Player submits Prompt
        ↓
B captures transaction_chunk_coord from A
        ↓
A pins transaction chunk
        ↓
Compiler
        ↓
Candidate IR / Bindings / Fact Ops
        ↓
B builds RevisionPlan
        ↓
A GenerateChunk(
    transaction_coord,
    candidate_ir,
    candidate_revision,
    seed,
    boundary_constraints,
    generation_overrides
)
        ↓
Candidate ResolvedChunk
        ↓
B SceneDiff / SceneTransition
        ↓
SUCCESS
        ↓
B commits IR + Revision
        ↓
B requests:
PROVISIONAL.target_revision = latest
        ↓
A deferred rebuild scheduler
        ↓
Preview gradually catches up
        ↓
A unpins transaction chunk
```

失败：

```text
Compile / Candidate Generation / Prepare / Current Transition failure
        ↓
NO COMMIT
        ↓
Official revision unchanged
Official ChunkRecords unchanged
Historical unchanged
        ↓
unpin
```

---

# 53. 最终职责边界

## A

回答：

> **给定 Coord + IR + Revision + Seed + Boundary + Overrides，这块世界确定是什么；以及它什么时候被 materialize、rebuild、进入、休眠。**

## B

回答：

> **新的 IR 是否被接受；它作用于哪块世界；哪些 Chunk 应追随最新 revision；哪些必须保留；以及 Current Chunk 如何从旧世界安全变成新世界。**

---

# 54. 一句话交接

```text
A owns:
Space + Lifecycle + Generation

B owns:
Meaning of Revision + Transaction + Rewrite
```

双方只通过：

```text
ChunkRecord contract
ResolvedChunk
GenerateChunk
ChunkManager public APIs
SceneRuntime chunk APIs
```

连接。

不要通过：

```text
互相读取内部状态
互相修改 private data
依赖 SceneTree 猜语义
```

完成整合。