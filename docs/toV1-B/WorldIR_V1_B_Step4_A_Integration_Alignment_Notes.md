# WorldIR Godot V1 — Developer B Step 4 A/B Integration Alignment Notes

> **记录日期**：2026-08-15  
> **来源**：Developer B Step 3 — Current Chunk Revision Transaction  
> **状态**：待 A/B 在 Step 4 开始前冻结具体 API 形状  
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

目前没有架构语义 blocker，但真实 A 接入前仍需冻结三个具体接口。

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
4. ChunkRoot 本身由 A 管理，B 只修改其 GeneratedChunk 内容。
```

Step 3 Fake A 当前工作名：

```gdscript
get_chunk_root(coord)
```

该名称不是最终强制名称。

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

A/B 需要在以下两种方式中冻结一种：

```text
Option 1 — A 内部收集（推荐）

B request_generate_chunk(...)
A 根据 coord 与正式邻居记录自行收集 Boundary Constraints


Option 2 — A 暴露只读查询

B 调用 A.get_boundary_constraints(coord)
再原样传回 A.generate_chunk(...)
```

无论采用哪种方式，都必须保持：

```text
Boundary constraint ownership = A
B 不读取 terrain cache / road state / neighbor private records
B 不自行推导 Terrain edge / Road exit
```

Step 3 Fake A 当前工作名：

```gdscript
get_boundary_constraints(coord)
```

Fake 第一版返回空 Dictionary；它只用于保持 GenerateChunk 参数形状。

---

# 4. Alignment Point C — Successful Candidate Install

Candidate Current Chunk 完成 Transition 后，需要由 A 执行正式 ChunkRecord 安装。

需要冻结语义等价 API：

```gdscript
install_revision(
    coord,
    candidate_resolved_chunk,
    candidate_revision
)
```

或者：

```gdscript
commit_generated_chunk(...)
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
2. APPLY 成功后才调用 install；
3. install 必须是经过 PREPARE 后 effectively no-fail 的同步操作；
4. install 不得隐式触发 3×3 Preview rebuild；
5. A 仍是 resolved_chunk / source revision 的唯一正式写方。
```

Step 3 Fake A 当前工作名：

```gdscript
install_revision(coord, resolved_chunk, revision)
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
generate_chunk(..., generation_overrides={})
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
[ ] ChunkRoot 使用直接 Node3D 还是稳定 ChunkHandle
[ ] Boundary Constraints 由 GenerateChunk 内部收集，还是通过只读 API 获取
[ ] Candidate install 的最终方法名与参数
[ ] Candidate install 的 no-fail / validation 责任边界
[ ] ResolvedChunk install 后由谁发出 record/revision changed signal（若需要）
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

> **Step 4 不需要重新设计 Revision Transaction；只需要让真实 A 提供稳定 Chunk handle、A-owned Boundary Constraints，以及 APPLY 成功后的 no-fail Candidate install。**
