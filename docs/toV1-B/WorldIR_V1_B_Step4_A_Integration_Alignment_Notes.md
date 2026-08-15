# WorldIR Godot V1 — Developer B Step 4 A/B Integration Alignment Notes

> **记录日期**：2026-08-15  
> **来源**：Developer B Step 3 — Current Chunk Revision Transaction  
> **状态**：已按 A commit `1372c87` 与 B checkpoint `b410d8f` 完成接口冻结和集成
> **优先级**：本文只记录尚未冻结的 integration seam，不修改或覆盖现有 Shared Contract / Integration Addendum。

---

# 1. 当前结论

Developer B Step 3 已在 Fake A 下完成：

```text
Prompt
→ Capture / Pin Transaction Chunk
→ Compile
→ PREPARE Candidate ResolvedChunk + Candidate Scene + SceneDiff
→ APPLY Chunk-scoped SceneTransition
→ COMMIT WorldState + Target Chunk Record
→ Unpin
```

现有共同文档已经确定以下语义：

```text
A owns:
Space + Chunk lifecycle + ChunkRecord mutation + GenerateChunk

B owns:
Revision decision + transaction + Scene rewrite + commit timing
```

目前三个接口已经冻结并完成真实 A 接入，没有遗留架构语义 blocker。

---

# 2. Alignment Point A — Stable ChunkRoot / Chunk Handle

B 的 SceneRuntime 已要求显式作用于指定 ChunkRoot：

```gdscript
mount_chunk(chunk_root, resolved_chunk)
transition_chunk(chunk_root, old_resolved_chunk, new_resolved_chunk, mode)
remove_chunk(chunk_root)
```

因此 A 需要提供语义等价能力：

```text
get_chunk_root(coord)

或：

get_chunk_handle(coord)
→ handle 可稳定解析出该 Chunk 的 Scene Root
```

必须满足：

```text
1. Transaction pin 期间 handle / root 不失效；
2. C5 transition 不得搜索或修改 C4/C6；
3. B 只把 root/handle 传给 SceneRuntime，不读取 A 的 SceneTree 内部布局；
4. ChunkRoot 本身由 A 管理，B 只修改其 `GeneratedWorld` 内容。
```

真实 A 已冻结为：

```gdscript
get_chunk_root(coord)
```

返回稳定 `Node3D` ChunkRoot；transaction pin 期间不会被 eviction。

---

# 3. Alignment Point B — Boundary Constraints 的获取责任

正式 GenerateChunk contract 包含：

```gdscript
generate_chunk(
    coord,
    world_ir,
    ir_revision,
    world_seed,
    boundary_constraints,
    generation_overrides={}
)
```

但当前共同文档尚未冻结 B 如何取得 `boundary_constraints`。

A/B 已采用以下方式：

```text
Option 1 — A 内部收集（已采用）

B request_generate_chunk(...)
A 根据 coord 与正式邻居记录自行收集 Boundary Constraints


同时保留只读诊断查询：

B 可调用 A.get_boundary_constraints(coord) 查看 value-data copy，
但 Candidate generation 直接调用 A.generate_candidate(...)，由 A 内部收集正式邻居约束。
```

无论采用哪种方式，都必须保持：

```text
Boundary constraint ownership = A
B 不读取 terrain cache / road state / neighbor private records
B 不自行推导 Terrain edge / Road exit
```

真实 A 方法：

```gdscript
generate_candidate(coord, world_ir, revision, generation_overrides={})
get_boundary_constraints(coord) # read-only diagnostic copy
```

`ChunkGenerator.generate_chunk(...)` 仍保留完整 seed / constraints 输入，但 B 不直接读取 A 的生成内部状态。

---

# 4. Alignment Point C — Successful Candidate Install

Candidate Current Chunk 完成 Transition 后，需要由 A 执行正式 ChunkRecord 安装。

真实 A 已冻结 API：

```gdscript
install_resolved_candidate(
    coord,
    candidate_resolved_chunk,
    source_ir_revision,
    target_ir_revision
) -> bool
```

该操作必须一次性保证：

```text
record.resolved_chunk = candidate_resolved_chunk
record.source_ir_revision = candidate_revision
record.target_ir_revision = candidate_revision
derived is_stale = false
```

并且不得修改：

```text
record.coord
record.streaming_state
record.authority
其它 Historical / PROVISIONAL records
```

事务要求：

```text
1. PREPARE 阶段只验证 Candidate 可安装，不修改正式 record；
2. APPLY 成功并 commit WorldState 后，依次调用 `set_generation_context`、Current target 更新和 install；
3. PREPARE 必须验证 source/target 未变化及 Candidate provenance，使 install 成为 effectively no-fail 的同步操作；
4. install 不得隐式触发 3×3 Preview rebuild；
5. A 仍是 resolved_chunk / source revision 的唯一正式写方。
```

实际调用顺序：

```gdscript
world_state.commit_revision(...)
chunk_manager.set_generation_context(candidate_ir, candidate_revision)
chunk_manager.set_target_revision(coord, candidate_revision)
chunk_manager.install_resolved_candidate(
    coord,
    candidate,
    source_revision_at_prepare,
    candidate_revision
)
```

---

# 5. 已经冻结、不需要重新讨论的接口

以下能力已经由 Shared Contract / Integration Addendum 明确：

```text
get_current_chunk_coord()
get_record(coord)
get_active_records()
pin_chunk(coord)
unpin_chunk(coord)
generate_candidate(..., generation_overrides={})
set_generation_context(world_ir, revision)
```

Generation Overrides 继续保持：

```text
只传给 transaction_chunk_coord
不进入 World IR
不持久化到 ChunkRecord
不传播到 Preview / Future
只携带本次 runtime_bindings 与相关 spatial payloads
```

---

# 6. Step 4 开始前需要冻结的最小决定

```text
[x] ChunkRoot 使用直接稳定 Node3D
[x] Boundary Constraints 由 `generate_candidate` 内部收集
[x] Candidate install 使用 `install_resolved_candidate(coord, candidate, source, target)`
[x] PREPARE 验证 provenance，install 返回 bool 并在 COMMIT 路径断言成功
[x] A 在安装后发出 `chunk_record_changed`
```

这些决定只影响 Fake A → Real A 的 adapter，不应改变：

```text
RevisionPlan
Prompt target capture
Candidate isolation
PREPARE / APPLY / COMMIT 状态机
SceneDiff
SceneTransition
World IR / Compiler Contract
```

---

# 7. Step 4 Integration Acceptance

真实 A 替换 Fake A 后，必须继续通过：

```text
1. Prompt at C5, move to C6, response still rewrites C5;
2. C5 remains pinned until commit / abort;
3. Candidate generation receives C5 boundary constraints and transaction-local overrides;
4. PREPARE failure leaves official C5 record unchanged;
5. Transition success installs candidate into C5 only;
6. C5 source_revision == target_revision == candidate_revision;
7. C6 and other Preview records are not synchronously rebuilt by the Current transaction;
8. unpin always occurs on success and abort.
```

---

# 8. 一句话对齐结论

> **Step 4 保留原 Revision Transaction；真实 A 通过稳定 ChunkRoot、内部 Boundary Constraints、版本化 generation context 与 provenance-checked Candidate install 接入。**
