# ArtLab Policy 参数变更记录

每项记录区分“观察、假设、验证”，避免把一次截图中的主观印象直接固化为生成规律。

## 2026-08-15 — v1 初始接入

观察：V1-A 的固定 terrain/dressing 常量能够生成完整世界，但森林边缘、建筑 clearing、
道路走廊、海岸表面和材质色板无法作为一组可追踪的实验参数进行复用。

假设：把 ArtLab 已验证参数作为 Backend-owned realization policy，并保持显式 World IR
优先，可以改善空间层次且不改变 Compiler/Runtime 契约、实例 identity 或确定性。

验证：原始 V1-A 21/21 测试通过；移植到 `to-V1-B@575b7bc` 后 30/30 测试通过；
Windows Godot 4.7.1 / RTX 5070 六机位渲染成功。相同机位与 seed 保存在
`screenshots/baseline_1372` 和 `screenshots/artlab_policy`。

## 2026-08-15 — A+B 待办收口

观察：完整 A+B 已提供 revision、Preview scheduler、boundary population blend、历史
Chunk preserve 和稳定 ChunkRoot，但没有扩展 World IR 四根契约。

假设：Policy 的版本/fallback、诊断、场景矩阵、远距离 streaming 和性能证据可以全部
作为内部工具与测试完成；biome/weather/新 surface channel 仍不应借机进入协议。

验证：由 `test_chunk_dependency_closure.gd`、`test_artlab_policy_determinism.gd`、
`test_artlab_scenario_matrix.gd`、`test_artlab_streaming_scale.gd`、视觉矩阵和 Windows
性能报告共同记录。最终实测数值写入 `docs/artlab_performance_baseline.md`。
