# WorldIR Godot V1 — Developer B 五阶段开发实施文档

> **角色**：Developer B  
> **基线**：`godot-main_V0_85`  
> **开发方向**：IR Revision / Rebase / Scene Transition  
> **依赖契约**：
>
> - `WorldIR_V1_AB_Shared_Development_Contract.md`
> - `WorldIR_V1_B_IR_Revision_Rebase_Transition_Requirements.md`
> - `WorldIR_V1_AB_Integration_Constraints_Addendum.md`
> - `WorldIR_Godot_V1_Continuous_Chunk_World_Design.md`
> - `WorldIR_Godot_Server_API_Contract_V0.md`
>
> **本文目标**：将 Developer B 的任务拆成最多五个可以独立开发、独立验收、逐步与 A 集成的阶段。重点不是规定具体 class 数量或代码写法，而是降低状态语义、事务边界、Shared File 与后续 merge 的歧义。

---

# 1. Developer B 的最终交付

B 的任务可以压缩成一句话：

> **当新的完整 World IR 到达 Godot 后，安全地决定哪些 Chunk 应该跟随新 Revision、哪些 Chunk 必须保留，并将本次 Prompt 所作用的 Chunk 从旧 ResolvedChunk 渐进地改写为新 ResolvedChunk。**

完整数据流最终应为：

```text
Player Prompt
    ↓
Capture Transaction Chunk
    ↓
Compiler
    ↓
Candidate IR
    ↓
RevisionPlan
    ↓
Generate Candidate ResolvedChunk
    ↓
SceneDiff
    ↓
SceneTransition
    ↓
Commit Revision
    ↓
Provisional Chunks Target Latest Revision
```

B 不负责：

```text
Chunk coordinate calculation
3×3 Active Window
Player movement streaming
Terrain deterministic generation
Road continuation
Population deterministic scatter
Chunk eviction
Streaming scheduler
```

这些属于 A。

---

# 2. B 开发过程统一心智模型

整个开发过程中始终保持三层状态：

```text
Layer 1 — Semantic / Design State

current_ir
current_ir_revision


Layer 2 — Chunk Resolution State

ChunkRecord
├── coord
├── streaming_state
├── authority
├── source_ir_revision
├── target_ir_revision
└── resolved_chunk


Layer 3 — Physical Scene State

ChunkRoot
└── Nodes / Mesh / Collision / Visual Runtime
```

正式原则：

```text
World IR
= Design Truth

ResolvedChunk
= Spatial Truth

SceneTree
= Presentation / Runtime State
```

SceneTree 不负责保存 Revision / Authority / Semantic Truth。

---

# 3. 五阶段整体路线

```text
STEP 1
Revision Kernel
纯数据状态机与 RevisionPlan
        ↓
STEP 2
Chunk-scoped Scene Infrastructure
把现有 SceneDiff / SceneTransition 从单世界改成指定 Chunk
        ↓
STEP 3
Current Chunk Revision Transaction
完成 Prompt → Candidate → Transition → Commit / Abort 闭环
        ↓
STEP 4
A Integration + Provisional Revision
接真实 ChunkManager / GenerateChunk / stale / ensure_latest
        ↓
STEP 5
Boundary Transition + Performance + End-to-End
完成视觉连续性、性能策略与最终 V1 Demo
```

前 3 Step 应尽量允许 B 在 **Fake A** 下独立完成。

真正依赖 A 的部分主要集中在 Step 4。

---

# STEP 1 — Revision Kernel

## 1.1 目标

先实现完全不依赖 SceneTree、Terrain、真实 Chunk Streaming 的 Revision 核心。

这一阶段需要解决：

```text
当前正式 Revision 是多少？
Candidate Revision 是多少？
本次 Prompt 到底作用在哪个 Chunk？
哪些 Chunk 可以被新 IR 重写？
哪些必须保留？
哪些 Preview 需要追最新 Revision？
Candidate 失败时正式状态是否完全不变？
```

这是整个 B 模块最重要的状态语义基础。

---

## 1.2 推荐新增模块

建议：

```text
scripts/revision/
├── revision_plan.gd
├── chunk_rebase_planner.gd
└── revision_transaction.gd
```

实际拆分方式可以自行调整。

重点是将：

```text
Revision Policy
```

与：

```text
Scene / Compiler / Streaming
```

分离。

---

## 1.3 WorldState 最小扩展

加入等价字段：

```text
current_ir
current_ir_revision
```

第一版：

```text
Initial committed world
→ revision = 0
```

之后：

```text
candidate_revision =
    current_ir_revision + 1
```

Revision 不进入 World IR。

Revision 不发送给 Compiler。

---

## 1.4 Transaction Chunk Capture

玩家提交 Prompt 时必须立即读取：

```text
transaction_chunk_coord =
    chunk_manager.get_current_chunk_coord()
```

此后整个 transaction 都使用这个坐标。

禁止：

```text
Compiler response 返回时
重新查询 current_chunk
再决定 Prompt 作用对象
```

因为玩家可能已经移动。

例如：

```text
Prompt submit:
Player at C5

Compiler processing...

Player moves:
C5 → C6

Compiler returns
```

本次 Prompt 仍然：

```text
Target = C5
```

不是 C6。

---

## 1.5 Authority Policy

必须实现可独立测试的纯逻辑：

```text
Transaction Target
→ REBASE ALLOWED

PROVISIONAL
→ REBASE ALLOWED

Historical COMMITTED
→ PRESERVE
```

注意：

```text
Transaction Target 即使 COMMITTED
仍然允许本次 Prompt 修改
```

它是 COMMITTED 的特殊可写例外。

禁止根据：

```text
loaded
visible
ACTIVE
ENVIRONMENT_READY
```

判断是否可以 rebase。

---

## 1.6 RevisionPlan

收到 Candidate IR 后，先产生纯数据：

```text
RevisionPlan
```

推荐至少表达：

```text
from_revision
candidate_revision
transaction_chunk_coord

must_rebase[]
target_latest[]
preserve[]
future_policy
```

逻辑语义：

```text
Transaction Target
→ MUST_REBASE

PROVISIONAL
→ TARGET_LATEST

Historical COMMITTED
→ PRESERVE

Unmaterialized Future
→ NO IMMEDIATE ACTION
```

---

## 1.7 Candidate Isolation

Candidate Revision 在正式 commit 前：

```text
不能修改 current_ir
不能修改 current_ir_revision
不能永久修改正式 ChunkRecord.target_revision
不能污染 Historical
不能提前让 Preview 变成 candidate revision
```

Candidate 只能存在于：

```text
RevisionTransaction
RevisionPlan
Candidate IR
Candidate ResolvedChunk
Candidate Scene
```

---

## 1.8 is_stale 规则

推荐：

```text
is_stale =
    source_ir_revision != target_ir_revision
```

而不是第三个独立 mutable state。

这样可以避免：

```text
source=1
target=2
is_stale=false
```

这种非法组合。

---

## 1.9 Step 1 自动测试

至少实现：

### T1 — Authority Policy

```text
Transaction Target COMMITTED
→ allowed

PROVISIONAL
→ allowed

Historical COMMITTED
→ denied
```

### T2 — Prompt Target Capture

```text
submit at C5
player later moves C6
→ transaction target remains C5
```

### T3 — RevisionPlan Classification

输入：

```text
Current
Historical
Provisional
```

分类结果准确。

### T4 — Candidate Isolation

Candidate transaction abort：

```text
current revision unchanged
official ChunkRecords unchanged
```

### T5 — Current Exception

Current / transaction target 即使是：

```text
COMMITTED
```

仍然进入：

```text
MUST_REBASE
```

---

## 1.10 Step 1 Done Definition

```text
[ ] current_ir_revision 已进入正式状态模型
[ ] transaction_chunk_coord 在 Prompt submit 时捕获
[ ] Authority Policy 是纯逻辑
[ ] RevisionPlan 是纯数据
[ ] Candidate Revision 不污染正式状态
[ ] Historical COMMITTED 默认 preserve
[ ] Future 不需要创建记录
[ ] 所有规则可脱离 SceneTree 测试
```

---

# STEP 2 — Chunk-scoped Scene Infrastructure

## 2.1 目标

将 V0.85 已经存在的：

```text
SceneDiff
SceneTransition
SceneRuntime
```

从：

```text
一个全局 GeneratedWorld
```

适配成：

```text
指定 ChunkRoot
```

这一阶段仍然可以使用 Fake A。

不要在这一阶段处理真实 Streaming。

---

# 2.2 保留现有 SceneDiff 思想

现有 Diff 能力继续保留：

```text
unchanged
added
removed
moved
replaced
updated
```

核心接口变成：

```text
old ResolvedChunk
+
new ResolvedChunk
↓
SceneDiff
```

SceneDiff 不应该：

```text
查询 Player
读取 ChunkManager
寻找 Current Chunk
读取 RevisionPlan
遍历 SceneTree 猜语义
```

它保持纯 old/new spatial data comparison。

---

# 2.3 ResolvedChunk 设计原则

不要重新设计一套与现有 `ResolvedWorld` 完全不同的数据模型。

推荐：

```text
ResolvedChunk
≈
Chunk-scoped ResolvedWorld
```

保持现有概念：

```text
terrain
regions
networks
entities
distributions
environment / decorations
```

新增：

```text
coord
bounds
revision
```

这样可以最大程度复用：

```text
SceneDiff
SceneTransition
Scene builders
```

---

# 2.4 Stable Identity

这是本阶段的硬要求。

例如：

```text
IR0:
tree A
tree B
tree C
tree D

IR1:
tree A
tree B
house X
```

Diff 应得到：

```text
A/B unchanged
C/D removed
X added
```

禁止变成：

```text
A/B/C/D removed
A/B/X added
```

---

## 2.5 Identity Contract

Revision 不属于 identity。

禁止：

```text
tree:r0:001
tree:r1:001
```

推荐全局 Runtime Identity：

```text
ChunkCoord
+
LocalResolvedID
```

例如：

```text
C5 / church
C5 / trees:cell_42_73
```

Distribution 长期推荐基于：

```text
semantic distribution id
+
stable deterministic spatial candidate
```

而不是只使用顺序编号。

---

# 2.6 SceneRuntime Chunk API

应把当前单世界假设改成显式 Chunk Root。

推荐概念：

```text
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

实际函数名可以调整。

但必须消除：

```text
SceneRuntime 永远自动寻找
WorldRoot/GeneratedWorld
```

这种全局假设。

---

# 2.7 Transition Mode

建议现在就预留：

```text
FULL_REWRITE
LIGHT_REBASE
SILENT
```

Step 2 只需要确保接口支持，不必马上全部实现复杂视觉。

---

# 2.8 Fake Chunk Scene 测试

建立：

```text
C5 Root
C6 Root
```

对 C5 执行：

```text
old → new transition
```

要求：

```text
C5 正常变化
C6 完全不受影响
```

这是 Chunk-scoped Scene 最核心验收。

---

# 2.9 Step 2 自动测试

### T1 — Chunk Isolation

Transition C5：

```text
C6 nodes unchanged
```

### T2 — Stable Diff

Stable ID 对象不被误判 remove/add。

### T3 — Local Add / Remove

只修改指定 Chunk。

### T4 — Move

同 ID transform 改变：

```text
→ moved
```

不是：

```text
remove + add
```

### T5 — Replace

同 identity 但 prototype/type 发生替换：

```text
→ replaced
```

---

# 2.10 Step 2 Done Definition

```text
[ ] SceneRuntime 不再假定单一 GeneratedWorld
[ ] SceneDiff 可以比较 ResolvedChunk
[ ] SceneTransition 可以作用于指定 ChunkRoot
[ ] 两个 Chunk 同时存在时互不污染
[ ] Stable ID 可避免全量 remove/add
[ ] ResolvedChunk 尽量兼容现有 ResolvedWorld
```

---

# STEP 3 — Current Chunk Revision Transaction

## 3.1 目标

完成 B 最核心的真正闭环：

> **Prompt → Candidate IR → Candidate Current Chunk → Diff → Transition → Commit / Abort**

到 Step 3 完成时，即使 A 尚未完成真实 Chunk Streaming，B 也必须能够使用 Fake A 独立演示整个 Revision Transaction。

---

# 3.2 Transaction State Machine

正式采用：

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

# 3.3 CAPTURE

Prompt submit：

```text
capture transaction_chunk_coord
capture base_revision
pin transaction chunk
```

如果使用 Fake A，也模拟：

```text
pin/unpin
```

语义。

---

# 3.4 COMPILE

继续使用现有 Server Contract：

```text
prompt
current_ir
runtime_context
```

Server 返回：

```text
candidate_ir
runtime_bindings
runtime_fact_ops
```

Chunk / Revision 不发送给 Compiler。

---

# 3.5 PREPARE

PREPARE 中完成所有可能正常失败的操作：

```text
Validate Compile Result
↓
candidate_revision = current_revision + 1
↓
Create Candidate Runtime Facts
↓
Build RevisionPlan
↓
Collect Boundary Constraints
↓
Generate Candidate Transaction Chunk
↓
Build Candidate Scene
↓
Calculate SceneDiff
↓
Validate Transition Resources
```

PREPARE 任一步失败：

```text
ABORT
```

要求：

```text
current_ir unchanged
revision unchanged
scene unchanged
official ChunkRecords unchanged
```

---

# 3.6 GenerateChunk 新 Contract

B 通过 A contract 请求：

```text
GenerateChunk(
    coord,
    world_ir,
    revision,
    seed,
    boundary_constraints,
    generation_overrides
)
```

新增：

```text
generation_overrides
```

默认空。

---

# 3.7 Generation Overrides

用于承载 transaction-local：

```text
runtime_bindings
spatial_payload references
lowering overrides
```

重要规则：

```text
不进入 World IR
不持久化
不传播给 Future
不自动广播到所有 Preview Chunk
```

---

# 3.8 Runtime Binding Scope

如果 Runtime Binding：

```text
graveyard
↔
clearing_01
```

而 clearing 实际位于 C5：

```text
Binding
→ only passed to C5 generation
```

不能：

```text
C6/C7/C8
全部使用 clearing_01
```

第一版如果 Runtime Fact 明确属于本次 transaction target，可直接限定：

```text
bindings only used by transaction_chunk_coord
```

---

# 3.9 APPLY

只有 PREPARE 全部成功后才能开始。

执行：

```text
old transaction Chunk Scene
↓
SceneDiff
↓
SceneTransition
↓
new Chunk Scene
```

原则：

> **APPLY 开始之后，不应该再依赖正常业务失败路径。**

例如以下错误应在 PREPARE 阶段发现：

```text
prototype missing
candidate generation failure
mesh build failure
invalid diff
missing required payload
```

不要优先实现复杂：

```text
transition 进行到 60%
↓
reverse all animation
```

---

# 3.10 COMMIT

Current Chunk transition 成功后：

```text
current_ir = candidate_ir
current_ir_revision = candidate_revision
runtime_facts = candidate_runtime_facts
```

Transaction target：

```text
resolved_chunk = candidate
source_revision = candidate_revision
target_revision = candidate_revision
```

随后才允许：

```text
PROVISIONAL.target_revision = latest
```

---

# 3.11 Pin / Unpin

Transaction 开始：

```text
pin(transaction_chunk_coord)
```

Transaction 完成或 abort：

```text
unpin(transaction_chunk_coord)
```

玩家可以在 transaction 过程中移动。

例如：

```text
Prompt at C5
↓
Player moves C6
```

合法状态：

```text
Current = C6
Transaction Target = C5
```

C5 仍完成 Prompt transaction。

---

# 3.12 Fake A

为了不等待 A：

```text
FakeChunkManager
FakeChunkGenerator
```

至少支持：

```text
get_current_chunk_coord()
get_record()
get_active_records()
pin_chunk()
unpin_chunk()
generate_chunk()
```

Fake IR 示例：

```text
IR0
trees = 10
houses = 2

IR1
trees = 5
houses = 6
```

并提供稳定 IDs。

---

# 3.13 Step 3 Failure Tests

必须人为制造：

```text
Compile failure
IR GAP
Generate failure
Candidate scene build failure
```

全部要求：

```text
No Revision Commit
No Current IR Commit
No Fact Commit
No official record mutation
Old Scene remains
```

---

# 3.14 Step 3 Milestone

这是 B 的第一个真正大型 Milestone。

必须能独立演示：

```text
Player at C5
IR0
↓
Prompt
↓
Compiler/Fake Compiler returns IR1
↓
Candidate C5 generated
↓
tree remove animation
house add animation
↓
Transition success
↓
revision 0 → 1
```

同时：

```text
故意让 generation fail
```

结果：

```text
revision still 0
scene still IR0
```

---

# 3.15 Step 3 Done Definition

```text
[ ] Prompt submit 锁定 Transaction Chunk
[ ] Chunk transaction 期间可 pin
[ ] Candidate IR 不提前 commit
[ ] Runtime Binding 正确进入 generation overrides
[ ] Candidate ResolvedChunk 可建立
[ ] Current Chunk old/new 进入 SceneDiff
[ ] Current Transition 不是 full refresh
[ ] 成功后才推进 revision
[ ] PREPARE failure 完全 abort
[ ] Fake A 下完整闭环成立
```

---

# STEP 4 — A Integration + Provisional Revision

## 4.1 目标

将 Step 1–3 的 Fake A 换成真实：

```text
ChunkManager
GenerateChunk
ChunkRecord
```

并让：

```text
Present
Preview
History
Future
```

四种世界时间状态真正工作起来。

---

# 4.2 A 最小依赖接口

B 只依赖语义等价接口：

```text
get_current_chunk_coord()

get_record(coord)

get_active_records()

pin_chunk(coord)
unpin_chunk(coord)

generate_chunk(...)

set_target_revision(coord, revision)

request_rebuild(coord, revision)

ensure_latest(coord)
```

B 不读取 A 的：

```text
terrain cache
RNG
streaming queue
private chunk dictionary
road generator state
```

---

# 4.3 Commit 后处理 PROVISIONAL

IR1 正式 commit 后：

```text
for each active PROVISIONAL:
    target_revision = 1
```

然后允许：

```text
Visible / Near
→ request rebuild

Far
→ remain stale
```

B 决定：

```text
应该追哪个 Revision
```

A 决定：

```text
什么时候实际算
```

---

# 4.4 Eventually Consistent Preview

重要心智模型：

```text
Current
→ Strong / Synchronous

Preview
→ Eventually Consistent

Historical
→ Preserved
```

因此 IR1 commit 后允许：

```text
Preview:
source=0
target=1
```

暂时存在。

---

# 4.5 Preview Failure Isolation

如果：

```text
IR1 已经成功 commit
```

之后某 Preview Chunk rebuild 失败：

```text
不能 rollback IR1
```

而是：

```text
Chunk remains stale
log failure
retry later
```

Current Transaction Failure 与 Preview Failure 是两个不同 Failure Domain。

---

# 4.6 Revision Coalescing

例如：

```text
Chunk C7
source = 0
```

IR1：

```text
target = 1
```

还没 rebuild。

IR2 又成功：

```text
target = 2
```

C7 直接：

```text
GenerateChunk(IR2)
```

禁止：

```text
IR0 → IR1 → IR2
```

逐版 replay。

Preview 只追：

```text
LATEST TARGET
```

---

# 4.7 Latest-Wins Queue

如果：

```text
C7 queued for IR1
```

但尚未开始 generation 时：

```text
IR2 commit
```

应允许：

```text
old IR1 queued task superseded
```

最终只生成 IR2。

具体 scheduler 属于 A。

B 只更新：

```text
target revision
```

---

# 4.8 Player Entry Barrier

当玩家即将进入：

```text
source_revision != target_revision
```

的 Chunk：

```text
ensure_latest(coord)
```

必须完成后才能：

```text
promote to Current / gameplay authoritative
```

禁止：

```text
Player enters stale Chunk
↓
之后再慢慢刷新
```

---

# 4.9 Historical Preserve

例如：

```text
C5 COMMITTED IR0
Current IR = IR2
```

普通 Prompt 不得让：

```text
C5 → IR2
```

Historical：

```text
source revision stays IR0
```

即使之后离开 / reload，也不能因为 Current IR 已经变成 IR2 就自动用 IR2 重新生成。

---

# 4.10 Step 4 Integration Scenario

初始：

```text
P P P
H C P
H H P
```

所有 World IR = IR0。

玩家在 Current 输入 Prompt：

```text
IR0 → IR1
```

必须得到：

```text
Current
→ source=1
→ target=1

PROVISIONAL
→ target=1
→ some rebuilt
→ some stale

Historical
→ source remains 0
```

之后：

```text
IR1 → IR2
```

仍 stale 的 Preview：

```text
target directly → 2
```

玩家进入 Preview 前：

```text
ensure_latest()
```

最终：

```text
source=2
target=2
```

再 promotion。

---

# 4.11 Step 4 Done Definition

```text
[ ] Fake A 已替换为真实 A contract
[ ] Current transaction 与真实 GenerateChunk 整合
[ ] pin/unpin 工作
[ ] PROVISIONAL commit 后 target latest
[ ] Preview 可以 stale
[ ] Preview failure 不 rollback global revision
[ ] Revision coalescing 正确
[ ] Historical preserve
[ ] Player Entry Barrier 工作
[ ] Future 第一次生成使用 latest committed IR
```

---

# STEP 5 — Boundary Transition + Performance + End-to-End

## 5.1 目标

最后解决：

```text
视觉连续性
Preview 更新成本
Revision 边界
完整比赛 Demo
```

这一阶段不是再重写核心状态模型。

而是让已经正确的系统：

> **看起来连续、跑起来稳定。**

---

# 5.2 三类 Scene Update

正式区分：

## FULL_REWRITE

用于：

```text
Transaction Target / Present
```

可包含：

```text
rewrite ripple
spatial stagger
grow
sink
move tween
replace crossfade
```

---

## LIGHT_REBASE

用于：

```text
明显可见的 PROVISIONAL Chunk
```

推荐：

```text
短 fade
group crossfade
environment transition
```

避免几百 Node 同时复杂 Tween。

---

## SILENT

用于：

```text
Far Preview
Future materialization
Invisible rebuild
```

直接 mount / swap。

---

# 5.3 Performance Critical Path

一次 Prompt 的同步路径固定为：

```text
Compiler
↓
Transaction Target Generation
↓
Candidate Scene
↓
Current Transition
↓
Commit
```

不把：

```text
整个 3×3 Preview Rebuild
```

放进同步路径。

---

# 5.4 Preview Rebuild Strategy

正式：

```text
Current
→ synchronous

Preview
→ deferred

Future
→ on demand
```

第一版可以非常保守：

```text
max_provisional_rebuilds_in_flight = 1
```

具体值可由 A 调整。

正确性优先于并行度。

---

# 5.5 不允许的性能优化

不得为了性能破坏：

```text
determinism
stable identity
revision semantics
```

禁止：

```text
frame time 影响 procedural result
thread finishing order 改变 placement
chunk generation order 改变 world
revision queue 改变 identity
```

---

# 5.6 Revision Boundary Transition

当：

```text
Historical IR0
|
Current / Future IR1
```

邻接时，B 负责视觉环境边界。

第一版推荐：

```text
TRANSITION_BAND_M = 16.0
```

主要处理：

```text
tree density
grass density
rocks
surface appearance
fog
lighting
environment weights
```

---

# 5.7 不属于 B 的 Boundary 问题

以下仍由 A：

```text
Terrain edge crack
Road hard cut
Road endpoint
Road tangent
Road width continuity
Terrain boundary height
```

B 不实现通用几何 Constraint Solver。

---

# 5.8 Boundary Blend 不改变历史 Ownership

例如：

```text
Historical C5 = IR0
Current C6 = IR1
```

即使 visual band 横跨边界：

```text
C5.source_revision
```

仍然是：

```text
IR0
```

不得为了视觉 blend：

```text
把 C5 标成 IR1
```

---

# 5.9 最终 End-to-End Scenario

必须完整演示：

## Initial

```text
IR0
Player at C5
3×3 Active Window
```

Current：

```text
ACTIVE + COMMITTED
```

邻居：

```text
PROVISIONAL
```

---

## Move

玩家：

```text
C5 → C6
```

结果：

```text
C5 = Historical COMMITTED IR0
C6 = Current COMMITTED IR0
new preview row = PROVISIONAL IR0
```

---

## Prompt

玩家在 C6：

```text
“树少一点，沿路增加一些房子。”
```

Compiler：

```text
IR0 → IR1
```

---

## Current Rewrite

C6：

```text
Generate candidate IR1
↓
SceneDiff
↓
FULL_REWRITE
↓
Commit revision=1
```

玩家看到：

```text
部分树消失
新房屋出现
非 full flash
```

---

## Preview Rebase

周围 PROVISIONAL：

```text
target_revision = 1
```

Visible：

```text
LIGHT_REBASE
```

Far：

```text
stale / deferred
```

Historical C5：

```text
remains IR0
```

---

## Continue

玩家继续：

```text
C6 → C7 → C8
```

要求：

```text
stale C7 before entry → ensure latest

new C8 first materialization → latest IR1
```

---

## Boundary

回头看：

```text
IR0 history
|
IR1 present/future
```

要求：

```text
无严重 environment straight seam
无 terrain crack
Road 不硬断
```

其中 terrain / road geometry continuity 与 A 联合验收。

---

# 5.10 最终性能验收

至少检查：

```text
[ ] Prompt 不会同步 rebuild 整个 3×3
[ ] Current rewrite 时不会所有 Preview 同时完整 Tween
[ ] Preview rebuild 可以逐个进行
[ ] Repeated revisions 可以 coalesce
[ ] Candidate scene 生命周期明确
[ ] Old/New Scene 的短暂双份内存只发生在必要 Chunk
```

---

# 5.11 Step 5 Done Definition

```text
[ ] FULL / LIGHT / SILENT 三种路径存在
[ ] Current 是唯一同步强事务
[ ] Preview deferred
[ ] Future on-demand
[ ] Revision Boundary Environment Blend 工作
[ ] Historical ownership 未被 blend 修改
[ ] 无明显同步 3×3 重建 spike
[ ] 完整 Integration Scenario 可以演示
```

---

# 4. 五阶段之间的依赖关系

```text
STEP 1
Revision Policy / Transaction State
        │
        │ 不依赖 A
        ▼
STEP 2
Chunk Scene Infrastructure
        │
        │ 不依赖真实 A
        ▼
STEP 3
Current Transaction
        │
        │ Fake A 即可
        ▼
════════════════════════════
第一个 B Major Milestone
════════════════════════════
        │
        │ 开始依赖 A
        ▼
STEP 4
A Integration / Provisional
        │
        ▼
STEP 5
Visual / Performance / Final Demo
```

---

# 5. B 的第一个 Major Milestone

在 A 尚未完成真实 Chunk Streaming 时，B 应该已经可以独立展示：

```text
IR0
Current Chunk = C5

Prompt submit
↓
capture C5
↓
Fake Compiler / Real Compiler
↓
IR1
↓
Fake GenerateChunk(C5, IR1)
↓
old/new SceneDiff
↓
SceneTransition
↓
Commit
↓
revision = 1
```

并且：

```text
Compile failure
Generate failure
Candidate build failure
```

都会：

```text
保持 IR0
保持 revision 0
保持旧 Scene
```

做到这里以后：

> **A 的真实 GenerateChunk 应该只是替换 Fake A，而不应该迫使 B 重写 Revision Transaction。**

---

# 6. B 开发中的五条强制原则

## Principle 1

```text
IR is Design Truth.
ResolvedChunk is Spatial Truth.
SceneTree is Presentation State.
```

---

## Principle 2

```text
Prompt targets the Chunk captured at submission time.
```

不随着玩家移动漂移。

---

## Principle 3

```text
PREPARE may fail.
APPLY should be effectively no-fail.
COMMIT happens after Current transition.
```

---

## Principle 4

```text
Current = synchronous
Preview = eventually consistent
Historical = preserved
Future = latest on first generation
```

---

## Principle 5

```text
Stable identity survives revisions.
Revision number is never part of object identity.
```

---

# 7. B 不应在五阶段中引入的 Scope

本次不要顺便实现：

```text
Compiler understands Chunk
World IR adds chunk_id
Prompt sends player xyz to Server
production-grade async worker pool
multi-threaded universal scheduler
full historical persistence database
general rollback animation system
general cross-chunk constraint solver
LOD / HLOD
semantic paging
automatic LLM generation per chunk
complex biome simulation
```

这些均不是当前 B V1 的完成条件。

---

# 8. 最终开发顺序速查

```text
STEP 1 — Revision Kernel
解决：
Revision / Authority / Transaction Target / Candidate Isolation

STEP 2 — Chunk-scoped Scene
解决：
ResolvedChunk / Stable ID / SceneDiff / ChunkRoot Transition

STEP 3 — Current Transaction
解决：
Compile / Generate / Diff / Transition / Commit / Abort / Binding

STEP 4 — A Integration
解决：
Provisional / Stale / Coalescing / ensure_latest / Historical

STEP 5 — Final World Behavior
解决：
FULL-LIGHT-SILENT / Boundary Blend / Performance / Demo
```

---

# 9. B Done Definition

Developer B 的 V1 工作最终完成，当：

```text
[ ] Prompt 提交时锁定 Transaction Chunk
[ ] Current IR / Revision 有明确正式状态
[ ] Candidate Revision 不提前污染正式世界
[ ] Current Chunk 即使 COMMITTED 仍可响应本次 Prompt
[ ] Historical COMMITTED 默认保持
[ ] PROVISIONAL 可以追 latest revision
[ ] Preview 支持 stale 与 revision coalescing
[ ] Future 不需要提前 refresh
[ ] Runtime Binding 只作为 transaction-local lowering override
[ ] old/new ResolvedChunk 可以稳定 SceneDiff
[ ] Stable ID 避免无意义 full remove/add
[ ] SceneTransition 可以只作用指定 Chunk
[ ] Current Revision Transaction 成功后才 Commit
[ ] PREPARE Failure 不修改正式世界
[ ] Preview Failure 不回滚已成功 Revision
[ ] Player 不会正式进入 stale Chunk
[ ] Current / Preview / Future 使用不同视觉成本
[ ] Revision Boundary 不修改 Historical ownership
[ ] 完整 IR0 → Move → IR1 → Continue Scenario 可运行
```

---

# 10. 一句话定义 B 的开发路线

> **先把“世界什么时候算变了”做正确，再把“哪一块 Scene 在变”做正确，然后完成 Current Chunk 的强事务，最后才扩展到 Preview / History / Future 与视觉连续性。**

这五个阶段的核心目的不是把工作平均切成五份，而是确保每一步都建立在前一步已经固定的心智模型上，从而让 Developer B 可以独立推进，同时把最终与 A merge 时需要共同重构的范围压到最小。