# WorldIR Godot V1 — Developer B Step 5 Completion Notes

> 基线：A/B merge commit `c891e0d`
> 状态：Step 5 自动化实现与 headless end-to-end 已完成；图形帧时间与最终肉眼观感仍需在可视运行环境人工验收。

## 1. Merge 后 Step 4 核对

真实 `ChunkManager` 继续保持：

- Prompt submit 时捕获并 pin transaction Chunk；
- Current transition 成功后才 commit global IR/revision；
- commit 后才向 PROVISIONAL 发布 latest target；
- Historical COMMITTED preserve；
- Preview failure 不 rollback global revision；
- stale entry 先 `ensure_latest`；
- Future 首次 materialization 使用 latest committed IR；
- Preview queue 以 Coord 为 key，queued revision latest-wins。

Step 5 没有重写以上状态模型。

## 2. FULL / LIGHT / SILENT

| Path | Mode | Runtime 行为 |
|---|---|---|
| Prompt transaction target | `FULL_REWRITE` | 原有 object-level SceneDiff、ripple、spatial stagger、grow/sink、move、replace crossfade |
| 可见 cardinal PROVISIONAL Preview | `LIGHT_REBASE` | 单个 group crossfade；无 ripple、无逐对象复杂 Tween；Candidate collision 立即 authoritative |
| diagonal/far/invisible Preview、entry barrier、Future/streaming materialization | `SILENT` | 直接 swap/mount，不进入 rewrite animation |

`SILENT_REBUILD` 只作为兼容输入保留，诊断中 canonicalize 为 `SILENT`。

## 3. Revision Boundary Environment Blend

`RevisionBoundaryBlend` 先生成纯数据 plan，再把 plan 应用于 Chunk-scoped Scene。

固定：

```text
TRANSITION_BAND_M = 16.0
```

当前实际处理：

- tree / bush / grass / plant / flower；
- dead tree / stump；
- rock / stone / shrub / reed / ground cover；
- IR Distribution、backend Decoration，以及上述类型的 Entity。

对 revision 不同的相邻 Chunk，按 shared edge 两侧 band 内同类实例数量计算 seam keep ratio。高密度一侧用 stable object id 产生确定性 rank，并随离边界距离使用 smoothstep 恢复到完整密度。这样不会为了视觉融合生成第二套 population，也不会修改 ResolvedChunk value data。

Blend 只写 Scene node 的 visual transparency/meta，并让显著淡出的 regenerable object collision 与画面保持一致；不会写：

```text
authority
source_ir_revision
target_ir_revision
resolved_chunk
terrain/network geometry
```

当前目标 Demo 的 IR0 → IR1 主要变化是树密度和房屋数量，因此 population band 是直接相关的 seam reconciliation。Surface/fog 的通用跨 revision parameter blending 没有在 V1 中扩展为新系统。

## 4. Geometry Ownership

以下继续完全由 A 的 `ChunkBoundaryConstraints` / `ChunkGenerator` 负责：

- terrain shared-edge heights / crack prevention；
- road exit position；
- road tangent；
- road width；
- road hard-cut prevention。

B 的 visual band 不修改 terrain mesh vertex、road spline 或 generation constraint。

## 5. Preview 性能路径

A 原有 `_preview_queue` 保留：

- Dictionary assignment coalesces queued work；
- queue 仍由 A 按距离排序；
- 每次最多取一个 Preview；
- LIGHT overlap 未完成时不启动第二个昂贵 Preview；
- SILENT work 不创建 rewrite Tween；
- entry barrier 使用 SILENT latest install，优先 correctness；
- SceneRuntime 诊断记录 Candidate scene current/peak count 与 mode counts。

Headless end-to-end 中：

```text
peak prepared Candidate scenes = 1
LIGHT complex Tween count = 1 group Tween
```

完整 C5 → C6 → IR1 → C7 → C8 headless 进程在当前容器的 wall time 约 19.5s；该数值包含多次 3×3 deterministic generation，不能等同于图形 frame time。CPU/memory/frame spike 的最终判断必须在图形运行和 profiler 中完成。

## 6. Main Scene / End-to-End

`scenes/main.tscn` 现在实际包含并使用真实 `ChunkManager`。`WorldCoordinator`：

1. 首次 Compiler result 初始化 revision 0 的真实 3×3 Chunk window；
2. 后续 Prompt 委托给 `CurrentChunkRevisionCoordinator`；
3. Current 使用 FULL；
4. commit 后真实 A queue 渐进处理 Preview；
5. Player movement 继续走 A 的 entry barrier / window lifecycle。

自动化完整场景位于：

```text
tests/test_step5_end_to_end.gd
```

覆盖：

```text
IR0 at C5
→ move C6
→ Prompt / IR1 FULL rewrite at C6
→ Historical C5 remains IR0
→ diagonal Preview SILENT
→ cardinal Preview LIGHT
→ stale C7 ensure latest before promotion
→ previously unmaterialized C8 first materializes at IR1
→ move into C8
```

## 7. 人工图形验收清单

运行 `scenes/main.tscn`，使用可用 HTTP Compiler 输入：

```text
树少一点，沿路增加一些房子。
```

需要人工确认：

- Current 局部变化没有 full flash；
- Preview LIGHT 不抢眼；
- 16m population band 在目标美术资产/相机距离下足以消除明显 160m 植被墙；
- Godot profiler 中没有不可接受的 frame/memory spike；
- terrain / road 视觉上与自动 edge tests 一致，没有 crack/hard cut。

这些观感项不能由 headless test 诚实替代。
