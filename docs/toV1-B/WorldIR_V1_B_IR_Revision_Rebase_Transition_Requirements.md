# WorldIR Godot V1 — B 开发需求：IR Revision / Rebase / Scene Transition

> **角色**：B  
> **基线**：`godot-main_V0_85`  
> **依赖契约**：`WorldIR_V1_AB_Shared_Development_Contract.md`  
> **目标**：让现有 Compiler → World Rewrite transaction 在 Chunk 世界中拥有明确的 IR Authority、Revision、Rebase 与视觉 Transition 语义。

---

# 1. 任务定义

B 的任务不是“管理 Chunk Streaming”，而是交付一个明确能力：

> **当 Compiler 返回新的完整 World IR 时，决定 Current / Provisional / Historical / Future Chunk 分别应该发生什么，并把玩家正在看到的 Current Chunk 从旧 ResolvedChunk 安全、渐进地变成新 ResolvedChunk。**

B 最终必须能回答：

```text
IR0 -> IR1 后：
- 当前 Chunk 为什么要改？
- 哪些 Preview Chunk 可以改？
- 哪些 Historical Chunk 不能改？
- 哪些 Chunk 只需要标 stale？
- 未来未生成 Chunk 如何自动使用 IR1？
- transaction 失败时如何 rollback？
- 玩家眼前如何看到 old -> new transition？
```

---

# 2. B 不负责什么

B 不负责：

```text
Chunk coordinate 计算
Player movement streaming
3×3 Active Window 枚举
Terrain height function
Road continuation function
Population deterministic scatter
Boundary geometry generation
Chunk unload / dormant scheduler
```

这些属于 A。

B 不应该自己调用底层：

```text
region_lowerer
distribution_lowerer
terrain_resolver
network procedural internals
```

B 请求新世界结果时，只走 A 的 `GenerateChunk()` contract。

---

# 3. B 必须维护 Current IR / IR Revision

B 负责：

```text
current_ir
current_ir_revision
```

初始成功生成：

```text
IR0
revision = 0
```

成功编辑：

```text
IR0 -> IR1
revision = 1
```

失败编辑：

```text
revision 不变化
```

Revision 仅属于 Godot Runtime，不进入 World IR / Compiler API。

---

# 4. B 必须把 IR Revision 做成 transaction

V0.85 已经有：

```text
Compile
-> Candidate
-> Lower
-> Transition
-> Commit
```

V1 必须保留这个精神。

正式流程：

```text
IR_r / Scene_r
    ↓
POST /v1/compile
    ↓
Candidate IR_(r+1)
    ↓
Build RevisionPlan
    ↓
Generate Candidate Current ResolvedChunk
    ↓
SceneDiff
    ↓
SceneTransition
    ↓
Success
    ↓
Commit current_ir + revision
```

任一步失败：

```text
current_ir 保持 IR_r
current_ir_revision 保持 r
Current Chunk source revision 保持 r
Historical Chunk 不变
```

不要收到 Compiler `status=ok` 就提前更新正式 Current IR。

---

# 5. Current Chunk 是 Prompt 的唯一默认落点

Current Chunk Coord 由 A 提供。

B 不自行算坐标。

当新 IR 到来：

```text
Current Chunk MUST REBASE
```

即使 Current Chunk 已经：

```text
authority = COMMITTED
```

也必须允许本次 Prompt 修改。

这是 Historical COMMITTED 默认 immutable 的唯一核心例外。

---

# 6. B 必须实现 Authority Policy

共同规则：

```text
Current Chunk
    -> rebase allowed

PROVISIONAL
    -> rebase allowed

Historical COMMITTED
    -> preserve by default
```

建议实现为纯函数 / policy：

```text
can_rebase(record, current_coord)
```

该逻辑应该可以完全脱离 SceneTree 做单元测试。

禁止把判断写成：

```text
if loaded
if visible
if streaming_state != UNLOADED
```

Streaming 与 Authority 是两个正交维度。

---

# 7. B 必须交付 `RevisionPlan`

收到 Candidate IR 后，建议先生成纯数据计划，而不是立即改 Scene。

最小逻辑结构：

```text
RevisionPlan
├── from_revision
├── to_revision
├── current_chunk
├── rebuild_now[]
├── rebuild_visible[]
├── mark_stale[]
├── preserve[]
└── future_policy
```

实际字段可以调整，但必须能明确表达以下五类：

```text
1. Current Chunk        -> REBUILD NOW
2. Visible Provisional  -> REBUILD / TRANSITION
3. Other Provisional    -> MARK STALE / LAZY
4. Historical Committed -> PRESERVE
5. Unmaterialized Future-> NO IMMEDIATE ACTION
```

RevisionPlan 必须可打印 / debug / 测试。

---

# 8. Current Chunk Rebase 的正式流程

假设：

```text
current_ir = IR0
current_revision = 0
current_chunk = C
old = ChunkRecord(C).resolved_chunk
```

Compiler 返回 IR1。

B 必须请求 A：

```text
new = GenerateChunk(
    C,
    IR1,
    revision=1,
    same_world_seed,
    relevant_boundary_constraints
)
```

然后：

```text
old ResolvedChunk
vs
new ResolvedChunk
```

进入 SceneDiff / SceneTransition。

成功后：

```text
record.resolved_chunk = new
record.source_ir_revision = 1
record.target_ir_revision = 1
record.is_stale = false
```

并 commit：

```text
current_ir = IR1
current_ir_revision = 1
```

---

# 9. B 必须复用而不是绕过 V0.85 SceneDiff

V0.85 已经具备 object-level diff / transition 基础。

B 应把它从：

```text
ResolvedWorld old/new
```

适配到：

```text
ResolvedChunk old/new
```

目标仍然是识别：

```text
unchanged
added
removed
moved
replaced
updated
```

如果 A 提供稳定 instance ID，则 B 必须利用稳定 ID，避免每次 Revision 把所有 population 判定为 remove + add。

---

# 10. Current Chunk 的视觉目标

Prompt 成功后，玩家不应该看到 full refresh。

至少应保持 V0.85 当前已有方向：

```text
Removed
-> fade / shrink / sink

Added
-> emerge / grow / fade in

Moved
-> interpolated movement

Replaced
-> old out / new in

Whole rewrite
-> optional rewrite ripple / spatial stagger
```

具体视觉参数可以自行调整。

验收重点不是某一种 Tween，而是：

> **Old Scene → New Scene 是可辨认的局部变化，不是整块 Chunk 瞬间闪烁刷新。**

---

# 11. PROVISIONAL Chunk Rebase

新 IR 到来时，所有 active / loaded PROVISIONAL Chunk 都仍属于可改写未来。

B 必须至少把它们：

```text
target_ir_revision = new_revision
```

然后允许两种策略：

### Near / Visible Provisional

```text
request rebuild soon
```

如果玩家明显能看到，可以做较轻 Transition。

### Far / Less-visible Provisional

```text
mark stale
lazy rebuild
```

B 不需要强制所有 3×3 同一帧重算。

但必须确保未来玩家进入之前已经 latest。

---

# 12. Historical COMMITTED Chunk Preservation

当：

```text
record.authority == COMMITTED
record.coord != current_chunk
```

则新 IR 默认：

```text
PRESERVE
```

B 不请求 A 对该 Chunk全量 regenerate。

这意味着世界保留 IR 历史：

```text
IR0 history
|
IR1 present/future
```

V1 不要求用户一句 Prompt 重写所有走过的世界。

---

# 13. Future Chunk 的语义

3×3 外尚未 materialize 的 Chunk：

```text
没有 ResolvedChunk
没有 Scene
```

IR Revision 时：

```text
不要创建它
不要预计算它
不要加入 diff
```

只需要成功 commit：

```text
current_ir = IR1
```

之后 A 第一次需要它时，自然：

```text
GenerateChunk(coord, IR1, revision=1, ...)
```

因此 B 不需要维护“所有未来 Chunk 的 revision 表”。

---

# 14. B 必须处理 Candidate Revision 与正式 Revision 的区别

在 Transition 成功之前：

```text
Candidate IR1
Candidate revision = current_revision + 1
```

不能直接视为正式 `current_ir_revision`。

建议区分：

```text
current_revision
candidate_revision
```

如果 Current Chunk transition 失败：

```text
candidate_revision 被丢弃
```

PROVISIONAL 的 target revision 也必须恢复 / 不永久推进。

实现方式可以是：

```text
RevisionPlan 在 commit 前不 mutate 正式 records
```

或保留 rollback snapshot。

实现自由，但最终状态必须事务一致。

---

# 15. B 与 A 的正式交互

B 只通过共享 contract 请求世界生成。

至少需要：

```text
A.get_current_chunk_coord()
A.get_record(coord)
A.get_active_records()
A.generate / request_rebuild(...)
A.mark_stale(...)
A.ensure_latest(...)
```

B 不读取 A 私有 RNG / Terrain cache / Road continuation state。

如果 B 为了完成 Revision 必须直接改 A 的 generator 内部状态，说明 contract 需要先共同调整。

---

# 16. B 必须实现 Stale Policy

对于：

```text
PROVISIONAL
source_revision < target_revision
```

B 可以标记：

```text
is_stale = true
```

但需要与 A 保证：

```text
进入前 ensure latest
```

B 应能够 debug 出：

```text
为什么这个 Chunk 还是 IR0？
目标是不是 IR1？
它是不是允许 lazy rebuild？
```

---

# 17. Revision Boundary Visual Transition

历史 IR0 Chunk 与新 IR1 Chunk 邻接时，不能有明显环境直线：

```text
Dense Forest | Sparse Forest
```

B 负责定义 revision blend policy。

第一版固定推荐：

```text
TRANSITION_BAND_M = 16.0
```

概念：

\[
w(d)=smoothstep(0,T,d)
\]

例如 density：

\[
\rho(d)=(1-w)\rho_{old}+w\rho_{new}
\]

适合处理：

```text
tree density
grass / rock population
surface appearance
fog
lighting
weather weight
```

不负责重新解决 Terrain crack / Road endpoint；这些由 A 的 Boundary Constraints 保证。

---

# 18. Revision Boundary 不是“修改历史 Chunk”

必须明确：

```text
IR0 Historical Chunk
```

仍然属于 IR0。

Transition Band 只是视觉 / population edge reconciliation。

不要为了 Blend：

```text
把 Historical Chunk source_ir_revision 改成 IR1
```

历史 ownership 不应因此丢失。

---

# 19. B 必须保持 Geometry / Environment 心智模型

如果新 IR 只改变：

```text
tree density
surface
lighting
fog
```

尽量不要要求 Current Chunk 所有 Terrain geometry 重建。

V1 可以逐步引入：

```text
geometry_signature
environment_signature
```

但不是必须一次完成复杂 hash 系统。

最低要求是：

> **SceneDiff 能利用 old/new ResolvedChunk 判断哪些内容真的变化，而不是默认 full refresh。**

如果 A 能提供 geometry/environment 分类，B 应优先利用。

---

# 20. B 对 `WorldCoordinator` 的改造要求

B 主 ownership：

```text
scripts/app/world_coordinator.gd
```

需要将 V0.85 单世界 transaction 扩展为 Chunk-aware revision transaction。

WorldCoordinator 应负责：

```text
调用 Compiler
持有 candidate IR
请求 Current Chunk candidate generation
运行 RevisionPlan
协调 SceneTransition
成功后 commit current IR/revision
失败 rollback
```

不要把 Player movement / Active Window 每帧更新塞入 Coordinator。

这些由 A 的 ChunkManager 自己负责。

---

# 21. B 对 `WorldState` 的最小需求

需要存在等价状态：

```text
current_ir
current_ir_revision
```

以及能够拿到：

```text
current_chunk_coord
```

Current Chunk Coord 来自 A。

如果 V0.85 `WorldState` 还保存整张 `ResolvedWorld`，B 可以逐步迁移，但不要强制 A/B 同时大改全部状态结构。

兼容过渡允许存在：

```text
legacy_resolved_world
+
chunk records
```

最终以 Chunk Runtime 为真即可。

---

# 22. B 对 Scene Runtime 的修改边界

B 可以扩展：

```text
scene_diff.gd
scene_transition.gd
revision_boundary_transition.gd
```

但对首次 mount / streaming materialization 的接口应尽量保持简单，不把 Revision animation 强塞进 A 的所有加载路径。

期望概念：

```text
mount_chunk(resolved_chunk)
```

与：

```text
transition_chunk(old_chunk, new_chunk, diff)
```

分离。

如果需要共同改 `scene_runtime.gd`，与 A 先固定接口再动。

---

# 23. Compiler Contract 不改

B 必须保持：

```text
current_ir + prompt + runtime_context
        ↓
/v1/compile
        ↓
new complete world_ir
```

不要加入：

```text
chunk_coord
player_xyz
active_window
source_ir_revision
```

到 Server request。

IR Revision / Current Chunk 解释全部发生在 Godot。

---

# 24. B 必须支持 Compile Failure / IR GAP

如果：

```text
status = ir_gap
```

或者 HTTP / lowering / generation / transition 失败：

```text
世界保持原 Revision
```

特别要求：

```text
不能 current_ir 已经 IR1
但 Current Chunk 还 IR0
```

也不能：

```text
Current Chunk rollback
但周围 Provisional 已永久 target IR1
```

transaction consistency 是硬性验收。

---

# 25. B Debug / 可观测性要求

至少可以输出：

```text
current_ir_revision
candidate_revision
current_chunk_coord
RevisionPlan
每个 Active Chunk:
    authority
    source_revision
    target_revision
    stale
    action in current plan
```

Prompt 后应能快速回答：

```text
为什么 C(4,6) 被重建？
为什么 C(5,5) 没变？
为什么 C(6,7) 只是 stale？
```

---

# 26. B 必须提供的自动测试

## B-T1 Authority Policy

```text
Current       -> true
Provisional   -> true
Historical    -> false
```

## B-T2 RevisionPlan Classification

给定混合 Chunk records，分类结果准确。

## B-T3 Current Rebase

IR0 → IR1 后 Current target revision 必须变为 1。

## B-T4 Historical Preserve

Historical source revision 不变化。

## B-T5 Provisional Stale

允许 source=0 / target=1 / stale=true。

## B-T6 Future Latest

Future 无立即 action；之后 A 收到的首次生成 IR 必须是 committed IR1。

## B-T7 Failed Compile

revision 不推进。

## B-T8 Failed Generate

revision 不推进。

## B-T9 Failed Transition

revision 不推进，Current Scene 保持 / 恢复旧状态。

## B-T10 Stable ID Diff

A 提供稳定 IDs 时，未变化实例不应全部被判 remove/add。

## B-T11 Current Is Exception

Current 即使 authority=COMMITTED 仍可以在当前 Prompt 中 rebase。

## B-T12 Historical Boundary Metadata

Revision blend 不得改变 Historical Chunk 的 source revision / authority。

---

# 27. B 独立开发时的 Fake A

为了真正并发，不等待 A 完成全部 streaming。

建议建立：

```text
FakeChunkGenerator
```

例如：

```text
IR0:
    trees = 10
    houses = 2

IR1:
    trees = 5
    houses = 6
```

固定返回稳定 IDs：

```text
tree:000 ... tree:009
```

IR1 删除后半部分、加入房屋。

用它独立完成：

```text
RevisionPlan
Authority
old/new ResolvedChunk diff
SceneTransition
transaction rollback
```

等 A 的真实 GenerateChunk 完成后替换 fake。

---

# 28. B 的人工验收场景

## Scene A — Current Rewrite

Current Chunk 使用 IR0：

```text
dense trees
few houses
```

Prompt 得到 IR1：

```text
fewer trees
more houses
```

验收：

```text
当前 Chunk 局部动画变化
没有 full Chunk 闪烁
current revision 成功后才变 1
```

## Scene B — Preview Rebase

Active Window 中多个 PROVISIONAL 已按 IR0 生成。

IR1 到达。

验收：

```text
visible Preview 可重建
far Preview 可 stale
它们没有因为“已经加载”而锁死
```

## Scene C — History Preserve

玩家已经经过一个 IR0 Chunk。

之后 Current IR 改为 IR1。

回头看：

```text
旧 Chunk 保持 IR0 主要状态
```

## Scene D — Future Uses IR1

IR1 commit 后继续前进到之前从未 materialize 的 Chunk。

验收：

```text
第一次出现就是 IR1 风格
```

## Scene E — Failure

故意让 fake generator / transition 返回失败。

验收：

```text
Current IR / revision / current scene 均保持旧状态
```

---

# 29. B 与 A 最终 Integration Scenario

整合时必须完整跑：

```text
IR0
Player (5,5)
    ↓ move
Player (5,6)
    ↓ prompt
IR0 -> IR1
```

B 应产生：

```text
(5,6) Current
    REBUILD NOW -> transition -> IR1

visible PROVISIONAL
    REBASE / target IR1

far PROVISIONAL
    STALE target IR1

(5,5) Historical
    PRESERVE IR0

future
    NO ACTION
```

随后玩家继续：

```text
(5,7)
(5,8)
```

B 必须观察到：

```text
新 Chunk source IR1
```

并与 A 联合保证：

```text
历史 / 新 Revision 边界没有严重视觉 seam
```

---

# 30. B 的实现自由

以下可以自行决定：

```text
RevisionManager / Planner class 拆法
RevisionPlan 数据结构具体字段
SceneDiff 内部比较算法
Transition tween 参数
rewrite ripple 表现
visible provisional 的更新节奏
rollback 是 snapshot 还是 delayed commit
revision boundary 用 shader 还是 population weights
```

但必须满足共同 contract 与验收性质。

---

# 31. B 的禁止项

未经重新对齐，不要：

```text
修改 World IR Schema
修改 Compiler 让它理解 Chunk
自己实现 Chunk coordinate
直接操作 A 的 RNG / terrain generator
把 Historical COMMITTED 全部跟随新 IR 重建
把 Loaded 当作 immutable
Prompt 成功前提前推进正式 Revision
为了视觉 blend 改写 Historical source revision
把所有 old/new population 当 full remove + full add（若稳定 ID 可用）
```

---

# 32. B 的 Done Definition

B 任务可以认为完成，当：

```text
[ ] current_ir / revision 语义明确
[ ] Current Chunk 来自 A 单一来源
[ ] Authority policy 有纯测试
[ ] RevisionPlan 可明确分类所有 Active Chunk
[ ] Current Chunk MUST rebase
[ ] PROVISIONAL 即使已画出仍可 rebase
[ ] Historical COMMITTED 默认 preserve
[ ] Future 不做立即工作，首次生成使用 latest IR
[ ] old/new ResolvedChunk 可进入 SceneDiff
[ ] Current Rewrite 不是 full refresh
[ ] stale / target revision 可正确管理
[ ] transaction 失败不推进 revision
[ ] revision boundary transition 不破坏历史 ownership
[ ] Compiler Contract 未增加 Chunk 字段
[ ] 可以完全通过 A 的公开 contract 完成整合
```

---

# 33. B 的一句话验收

> **新的 World IR 到达时，玩家当前所在 Chunk 会安全、渐进地被改写；已经预览但尚未成为历史的 Chunk 能跟随最新 IR；已经走过的历史默认保留；尚未生成的未来自然继承最新 IR，并且整个过程保持事务一致。**
