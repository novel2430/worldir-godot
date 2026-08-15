# ArtLab Policy 视觉验收

验收使用固定 seed `1337`、固定相机和同一 Policy fingerprint。原始六机位基线位于
`screenshots/baseline_1372`，首次 Policy 对照位于 `screenshots/artlab_policy`，多场景
矩阵由 `tools/capture_artlab_matrix.gd` 生成到 `screenshots/artlab_matrix`。

## 场景覆盖

- coastal town：forest + east coast + north/south road + church + houses + trees；
- clearing/graveyard：forest + coast + graveyard + tombstones；
- restored forest：高密度恢复森林；
- inland village：无 coast 的 forest/village/road/building 组合；
- southern coast：不同方向 coast mask + dependent hamlet。

## 检查项

- [ ] Chunk seam：相邻 terrain height、surface mask、shore wetness 无裂缝或跳变；
- [ ] 道路净距：树木不侵入硬净距，灌木/草的外走廊没有笔直密度墙；
- [ ] 建筑入口：小屋、住宅和 church footprint 周围不穿插，clearing 随尺寸扩大；
- [ ] 海岸水线：沙地、湿沙、岸线和水下坡度连续，不出现反向海洋；
- [ ] 森林边缘：边缘层次可读但不形成规则圆环，内部仍保留疏密变化；
- [ ] 重复图案：cluster 不出现明显等距网格或同模型连续重复；
- [ ] 漂浮/穿插：Entity、Distribution 和 Decoration 均贴合 terrain，collision 与画面一致；
- [ ] Revision seam：V1-B 16m population band 不修改 terrain/network geometry 或历史 ownership。

数值正确性由 terrain/coast/forest/scenario/streaming 测试负责；此清单只记录真实图形
运行中仍必须人工确认的观感项。完成一次渲染验收后，应在本文件附上 engine、GPU、
renderer、Policy fingerprint 和矩阵 metrics，再勾选对应条目。
