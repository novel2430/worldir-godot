# WorldIR Godot V1 — A 侧开发规范索引

> 状态：A 分支实现与 A/B 集成的规范入口
> 分支：`codex/v1-a-chunk-streaming-generation`

## 1. 适用文档与解释顺序

A 侧开发必须同时遵守以下文档：

1. `WorldIR_V1_AB_Shared_Development_Contract.md`：A/B 共同基础契约。
2. `WorldIR Godot V1 — A-B Integration Constraints Addendum.md`：共同契约的集成收紧项。
3. `WorldIR_V1_A_Chunk_Streaming_Generation_Requirements.md`：A 侧功能需求。
4. 仓库 `docs/` 下现有架构、Backend、Compiler 与 World IR 文档。

发生歧义时，优先遵守共同契约；补充件仅在其明确收紧共同契约时优先于 A 侧需求。补充件不改变 Compiler Server 请求/响应契约。

## 2. A 侧职责

A 负责：

- Chunk 坐标、3×3 Active Window、生命周期、authority 与 stale 状态。
- `Coord + IR + Revision + Seed + Boundary + Overrides` 到 `ResolvedChunk` 的确定性生成。
- Terrain/road 边界连续性、稳定运行时 identity、进入 Chunk 前的 latest barrier。
- PROVISIONAL Chunk 的 deferred、latest-wins 重建调度。
- Chunk-scoped mount、unmount 和隔离的场景根节点。

A 不负责：

- Candidate IR 是否提交、RevisionPlan、SceneDiff 与动画策略。
- 修改 Historical Chunk 的语义或用 latest IR 隐式重建历史。
- 把 runtime bindings 写入 World IR 或广播到其他 Chunk。

## 3. 冻结的公开能力

`ChunkManager` 必须提供语义等价能力：

```gdscript
get_current_chunk_coord()
get_record(coord)
get_active_records()
pin_chunk(coord)
unpin_chunk(coord)
set_target_revision(coord, revision)
generate_candidate(coord, ir, revision, generation_overrides={})
request_rebuild(coord, revision)
ensure_latest(coord)
```

`ChunkGenerator` 必须提供：

```gdscript
generate_chunk(
    coord,
    ir,
    revision,
    seed,
    boundary_constraints = null,
    generation_overrides = {}
) -> ResolvedChunk
```

`SceneRuntime` 的 Chunk 路径必须显式接收稳定 Chunk root/handle，并区分首次 materialization、revision transition 与移除。它不得假设世界只有一个 `WorldRoot/GeneratedWorld`。

Developer B Step 4 冻结使用以下 A 侧接口：

```gdscript
get_chunk_root(coord: Vector2i) -> Node3D
get_boundary_constraints(coord: Vector2i) -> Dictionary
install_resolved_candidate(
    coord: Vector2i,
    resolved_chunk: ResolvedChunk,
    source_ir_revision: int,
    target_ir_revision: int
) -> bool
```

`get_chunk_root` 不触发生成；`get_boundary_constraints` 返回 value-data copy；`install_resolved_candidate` 仅在 source/target/candidate revision 仍匹配时安装，否则拒绝 stale/superseded candidate。

## 4. 事务与记录不变量

- Prompt 提交时由 B 捕获 transaction Chunk；后续玩家移动不得改变该目标。
- A 的 `pin_chunk` 防止 transaction Chunk 在事务结束前被 eviction；pin 不改变 current/authority。
- Candidate generation 是纯 PREPARE：不得修改正式 `ChunkRecord`、current IR、current revision 或其他 PROVISIONAL target。
- 只有 B 完成 APPLY 并 COMMIT 后，才通过 A API 更新 target revision、接受目标 candidate 并调度 preview rebuild。
- `is_stale` 只能由 `source_ir_revision != target_ir_revision` 推导。
- Preview 失败不回滚已提交 revision；该 Chunk 保持 stale，等待重试。
- 队列中的旧 revision 必须可被更新的 target 覆盖；默认最多渐进处理一个 preview rebuild。
- 玩家进入 Chunk 前必须 `ensure_latest` 成功，禁止 stale Chunk 先成为 Current。

## 5. Generation Overrides

`generation_overrides` 是本次 generation 的只读、transaction-local 输入，可包含：

```text
runtime_bindings
spatial_payloads
transaction-local hints
```

它不得：

- 写回 World IR、WorldState 或 generator 全局可变状态；
- 自动成为未来 Chunk 的生成输入；
- 传播到不拥有/不相交该 binding 的 Chunk。V1 最保守实现只向 transaction target 传递。

Overrides 为空时维持原确定性契约；非空时 overrides 也是 Same Inputs 的组成部分。

### 5.1 Chunk-local 语义闭包

`ChunkGenerator` 可以按方向 anchor 或离散对象 ownership 从某个 Chunk 的内部
IR 副本中裁掉不属于该 Chunk 的对象，但裁剪结果必须保持语义依赖闭包：如果
一个对象通过 placement relation、Network topology 或 Distribution density
selector 引用了已被 Chunk-local 规则裁掉的对象，则该依赖对象也必须递归裁掉，
直到不再出现新的依赖项。

这一步发生在进入 `WorldBackend` 之前，不得修改原始 World IR，也不得通过放宽
Region arbitration 或吞掉 Backend/Contract 错误来替代。只有明确因 Chunk-local
方向或 ownership 被裁掉的 target 才进入闭包；原始 IR 中未知或非法的 target
仍必须由既有验证路径报告失败。

## 6. Identity 与确定性

- Revision 永远不是对象 identity 的组成部分。
- Global runtime ID 由 `ChunkCoord + LocalResolvedID` 构成。
- Distribution identity 应基于稳定空间候选/cell；密度变化后，未被语义删除的实例应尽量保留 ID 与 Transform。
- Chunk 生成结果不得依赖生成顺序、帧时间、线程完成顺序或未版本化 mutable state。

## 7. Streaming 与性能基线

- Revision 同步 critical path 只生成 transaction target Chunk。
- PROVISIONAL rebuild 必须 deferred；B 只表达 target，不负责 scheduler。
- Future Chunk 按需使用 latest committed IR，未 materialize 的无限空间不创建记录。
- Historical Chunk 默认 preserve；reload 不得隐式使用 latest IR。
- 禁止一次 revision 在提交前同步生成完整 3×3，或同帧全量重建所有 preview。

## 8. 必须覆盖的集成验收

A 分支至少覆盖：transaction pin、candidate 不污染记录、override scope、稳定实例 identity、revision coalescing、preview failure isolation、no-stale entry、historical preservation 和 chunk-scoped scene mutation。跨 B 的 prompt capture/transition 测试在合并集成时执行。

## 9. ArtLab Realization Policy

ArtLab 的参数实验只允许进入 Backend-owned realization policy。它不得新增
World IR 字段、改变 Compiler/Runtime Context 契约、覆盖显式 Distribution
语义，或绕过本文件定义的 Revision、candidate、pin、stale 与 Chunk-scoped
事务。具体策略与未迁移边界见 `docs/artlab_realization_policy.md`。
