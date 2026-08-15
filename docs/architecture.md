# WorldIR Godot Backend V0 架构设计

> **状态**：Godot Backend V0 Architecture Baseline  
> **目标**：将 World IR V2 稳定 lower 成可玩的 Godot 3D 世界，并为后续 Server 接入、Runtime Fact、世界编辑与 Scene Transition 保留清晰边界。  
> **核心前提**：LLM Compiler Server 的实现当前可以不存在，但 Server API Contract 固定；Godot 侧必须能够通过 Fake Compiler / JSON Fixture 独立开发与测试。

---

# 1. Godot 在 WorldIR 系统中的角色

Godot 不是单纯 Renderer。

Godot V0 同时承担三类职责：

```text
1. World IR Backend
   World IR → Godot 中具体的空间世界

2. Game Runtime
   持有真实 Node、Mesh、Collision、Player、Interaction

3. State Coordinator
   管理 Current IR / Runtime Facts / Actual Scene 的一致性
```

整体架构：

```text
                 User Prompt
                     │
                     ▼
            Compiler Client
            Fake / HTTP Server
                     │
                 World IR
                     │
                     ▼
              World State
                     │
                     ▼
            Godot World Backend
                     │
                     ▼
              Resolved World
                     │
                     ▼
              Scene Runtime
                     │
                     ▼
              Playable World
```

核心原则：

> **Server 决定世界“应该变成什么”；Godot Backend 决定这些语义“具体在哪里”；Scene Runtime 决定这些具体结果“如何成为 Godot Node”；World Coordinator 保证整个变化是一次安全事务。**

---

# 2. Godot V0 的六个核心模块

V0 先固定为六个大模块，不继续过早细分。

```text
1. Compiler Client
2. World State
3. Prototype / Asset System
4. Godot World Backend
5. Resolved World
6. Scene Runtime
```

另外再由一个：

```text
World Coordinator
```

负责把它们串起来。

---

# 3. Compiler Client

Compiler Client 是 Godot 与 LLM Compiler Server Contract 的唯一边界。

概念结构：

```text
CompilerClient
├── FakeCompilerClient
└── HttpCompilerClient
```

统一输入：

```text
Prompt
Current World IR
Runtime Context
```

统一输出：

```text
CompileResult
├── world_ir
├── runtime_bindings
├── runtime_fact_ops
└── status
```

Server V0 Contract 固定为：

```text
GET  /health
GET  /info
POST /v1/compile
```

## 3.1 当前开发阶段

当前不假设真实 Server 已经可用。

因此 Godot 可以先使用：

```text
FakeCompilerClient
        ↓
读取 JSON Fixture
        ↓
返回标准 CompileResult
```

例如：

```text
data/fixtures/
├── coastal_town_initial.json
├── add_church.json
├── clearing_to_graveyard.json
└── restore_forest.json
```

未来 Server 完成后：

```text
FakeCompilerClient
        ↓
替换为
        ↓
HttpCompilerClient
```

World Backend、Scene Runtime、Prototype 系统均不需要修改。

---

# 4. World State

Godot 自己维护当前世界的逻辑状态。

```text
WorldState
├── current_ir
├── runtime_facts
└── spatial_payloads
```

## 4.1 Current World IR

表示当前世界的设计语义。

例如：

```text
forest west
road south → north
church north near road
houses along road
```

它不保存：

```text
x / y / z
Transform3D
Mesh
CollisionShape
NodePath
```

---

## 4.2 Runtime Facts

表示玩家实际游玩后造成的重要改变。

例如：

```text
clearing_01
kind = marked_area
mark = cleared
inside forest
anchor east
count = 23 trees
```

Runtime Context V1 当前支持：

```text
added_object
removed_object
object_state
marked_area
```

---

## 4.3 Spatial Payload

Runtime Fact 只有语义位置。

Godot 必须另外保存真实空间数据：

```text
clearing_01
│
├── Semantic View
│   └── 发给 Compiler
│
└── Spatial Payload
    ├── polygon
    ├── AABB
    ├── center
    ├── affected instance IDs
    └── Transform 等
```

这些真实空间信息：

```text
不发送给 Server
```

Server 如果返回：

```text
runtime_fact_id = clearing_01
```

Godot 再利用 ID 找回真实 Spatial Payload。

---

# 5. Prototype / Asset System

World IR 只知道：

```text
type = tree
type = house
type = church
```

具体使用哪个 Godot 素材属于 Backend。

V0 决定：

> **Godot Backend 不直接消费原始 GLB，而是统一使用 TSCN Prototype。**

---

# 6. GLB 与 TSCN 的关系

例如下载：

```text
tree_01.glb
```

它是原始 3D 美术素材。

在 Godot 中包装：

```text
tree_01.tscn
```

例如：

```text
TreePrototype
├── Model
│   └── tree_01.glb
└── Collision
    └── CollisionShape3D
```

房屋：

```text
HousePrototype
├── Model
│   └── house_01.glb
└── Collision
```

教堂：

```text
ChurchPrototype
├── Model
│   └── church_01.glb
└── Collision
```

以后还可以继续添加：

```text
interaction
lights
animations
doors
effects
```

但不需要改变 World Backend 接口。

---

# 7. Prototype Metadata

Prototype 还需要提供少量布局信息。

例如：

```text
prototype_id
semantic_type
placement footprint / radius
clearance
```

可以理解成：

```text
tree_01
→ tree_01.tscn
→ radius = 1.2m

house_01
→ house_01.tscn
→ footprint = 8m × 10m

church_01
→ church_01.tscn
→ footprint = 15m × 25m
```

这里的 metadata 是 WorldIR Godot Backend 自己的配置概念，不是某种特殊的 3D 文件格式。

V0 可以把 metadata 直接挂在 TSCN 根节点脚本上，避免同时维护独立 JSON。

---

# 8. Prototype Catalog

Prototype Catalog 负责：

```text
Semantic Type
      ↓
可用 Prototype
```

例如：

```text
tree
→ tree_01.tscn
→ tree_02.tscn

house
→ house_01.tscn
→ house_02.tscn

church
→ church_01.tscn
```

Backend 的依赖方向：

```text
World IR
type = church
      ↓
Prototype Catalog
      ↓
church_01
      ↓
读取 footprint
      ↓
Placement Solver
```

重要原则：

> **Placement Solver 不猜素材尺寸。先选择 Prototype，再依据真实 Prototype 的空间 metadata 做 placement。**

---

# 9. 不同 Primitive 的实际生成方式

四种 World IR Primitive 在 Godot 中不是同一种生成方式。

---

## 9.1 Region

例如：

```text
forest west
coast east
```

不是：

```text
forest.glb
```

而是：

```text
World IR Region
        ↓
生成空间 Polygon
        ↓
Ground / Material / Surface
```

例如：

```text
forest
→ west polygon
→ forest ground material
```

Region 的核心 resolved representation 是：

```text
Polygon
```

---

## 9.2 Network

例如：

```text
road south → north
```

道路长度与形状取决于 World IR，不适合用一个固定长度的 road.glb。

因此：

```text
World IR Network
        ↓
生成 Curve / center line
        ↓
设置 width
        ↓
程序生成 Road Mesh
        ↓
Road Material
```

V0 可理解为：

```text
Road =
procedural geometry
+
material
```

Network 的核心 resolved representation 是：

```text
Curve + width
```

---

## 9.3 Entity

例如：

```text
church north near road
```

流程：

```text
type = church
↓
Prototype Catalog
↓
church_01.tscn
↓
读取 footprint
↓
计算合法位置
↓
Resolved Transform
```

Entity 的核心 resolved representation 是：

```text
Prototype + Transform
```

---

## 9.4 Distribution

例如：

```text
houses along road count 12
trees inside forest density high
```

本质仍然是 Prototype，但重复实例化。

```text
house prototype
× 12
```

或者：

```text
tree prototype
× N
```

每个 instance 都需要一个确定的：

```text
prototype
transform
instance id
```

---

# 10. Godot World Backend

这是 V0 最核心的模块。

输入：

```text
BackendInput
├── World IR
├── Prototype Catalog
├── Seed
├── Runtime Bindings
└── Spatial Payloads
```

输出：

```text
Resolved World
```

推荐 lowering 顺序：

```text
1. Resolve World Frame
2. Resolve Regions
3. Resolve Networks
4. Resolve Prototype Choices
5. Resolve Entities
6. Resolve Distributions
7. Validate Resolved World
```

原因：

```text
Region
→ 提供空间 Domain

Network
→ 提供 Curve

Entity / Distribution
→ 经常依赖 Region / Network
```

例如：

```text
forest
↓
先得到 polygon

road
↓
再得到 curve

church near road
↓
才能真正 placement

houses along road
↓
才能沿最终 curve 分布
```

---

# 11. Placement Solver

V0 不实现万能 Constraint Solver。

只实现 World IR V2 当前需要的几个明确 operator：

```text
resolve_anchor()
resolve_inside()
resolve_near()
resolve_far_from()
resolve_along()
resolve_direction_of()
```

典型 Entity Placement：

```text
church:
anchor north
near road
```

可以：

```text
north 区域生成候选点
↓
计算到 road 的距离
↓
根据 church prototype footprint 检查 overlap
↓
选择满足约束的 candidate
```

---

# 12. Spatial Occupancy

空间占用来源必须与具体生成方式一致。

| 对象 | 空间占用来源 |
|---|---|
| Church | TSCN Prototype footprint |
| House | TSCN Prototype footprint |
| Tree | TSCN Prototype radius / footprint |
| Road | Curve + width |
| Path | Curve + width |
| Forest | Region polygon |
| Coast | Region polygon |

因此：

> 不存在一个“所有 World Object 都自己估算 footprint”的统一规则。

---

# 13. Resolved World

Godot Resolved World 是：

> **World IR 在 Godot Backend 中已经完成空间解算后的数据蓝图。**

它已经不是 Semantic IR，但也还不是 SceneTree。

```text
World IR
“church north near road”
        ↓
Godot Backend
        ↓
Resolved World
“church_01 at Transform X”
        ↓
Scene Runtime
        ↓
Node3D
```

---

# 14. Resolved World 最小结构

概念结构：

```text
ResolvedWorld
├── seed
├── world_bounds
│
├── regions[]
│   ├── id
│   ├── semantic_type
│   ├── polygon
│   └── surface_prototype
│
├── networks[]
│   ├── id
│   ├── semantic_type
│   ├── curve_points
│   ├── width
│   └── material / prototype
│
├── entities[]
│   ├── id
│   ├── semantic_type
│   ├── prototype_id
│   └── transform
│
└── distributions[]
    ├── id
    ├── semantic_type
    └── instances[]
        ├── id
        ├── prototype_id
        └── transform
```

例如：

```text
forest
→ polygon = [...]

main_road
→ curve = [...]
→ width = 6

church
→ prototype = church_01
→ transform = ...

houses
→ houses:000 → house_01 → transform
→ houses:001 → house_02 → transform
→ ...
```

---

# 15. Resolved World 的边界

Resolved World 可以保存：

```text
Vector2
Vector3
Transform3D
AABB
PackedVector2Array
```

但不要保存 live Godot Runtime Object：

```text
Node
Node3D
MeshInstance3D
CollisionObject3D
RID
```

原则：

> **Godot value data 可以出现，live SceneTree reference 不出现。**

---

# 16. Resolved World 的四条核心 Invariant

## Invariant 1

```text
ResolvedWorld 不包含 live Node reference。
```

## Invariant 2

```text
Same IR
+ Same Runtime Input
+ Same Seed
+ Same Backend Config
+ Same Prototype Catalog Version
→ Same Resolved World
```

## Invariant 3

```text
每一个 World IR Object
都能够追踪到对应的 Resolved Object。
```

## Invariant 4

```text
所有 semantic placement
必须在 Backend 阶段完成。

Scene Runtime 不重新解释：
near / inside / along / direction_of
```

---

# 17. Scene Runtime

Scene Runtime 负责：

```text
Resolved World
        ↓
真实 Godot Scene
```

它不理解 World IR semantic relation。

它只负责：

```text
Spawn
Delete
Move
Update
Transition
```

例如：

```text
ResolvedEntity:
prototype = church_01
transform = X
```

Scene Runtime：

```text
load church_01.tscn
↓
instantiate()
↓
设置 transform
↓
add_child()
```

---

## 17.1 Road

```text
ResolvedNetwork
↓
RoadBuilder
↓
Curve
↓
程序生成 mesh
↓
material
↓
collision
```

---

## 17.2 Region

```text
ResolvedRegion
↓
ground / surface renderer
```

---

## 17.3 Distribution

```text
ResolvedDistribution
↓
instantiate prototype × N
```

一句话：

> **Backend 算，Runtime 生。**

---

# 18. Scene Tree 建议

真实运行时大概：

```text
Main
│
├── WorldRoot
│   ├── Regions
│   ├── Networks
│   ├── Entities
│   └── Distributions
│
├── Player
│
├── UI
│   └── PromptPanel
│
└── WorldCoordinator
```

生成以后：

```text
WorldRoot
│
├── Regions
│   ├── ForestGround
│   └── CoastGround
│
├── Networks
│   └── MainRoad
│
├── Entities
│   └── Church
│
└── Distributions
    ├── Houses
    │   ├── House000
    │   ├── House001
    │   └── ...
    │
    └── Trees
        ├── Tree000
        ├── Tree001
        └── ...
```

---

# 19. Gameplay → Runtime Fact

这是与 World IR → Scene 相反的数据流。

例如玩家砍树：

```text
Tree Node
↓
Gameplay Event
↓
RuntimeFactManager
↓
聚合
↓
clearing_01
```

同时：

```text
SpatialPayloadStore

clearing_01
→ polygon
→ center
→ affected tree IDs
```

下一次玩家说：

```text
“把我刚刚砍出来的地方变成墓地。”
```

Godot 发：

```text
Current IR
+
clearing_01 Semantic Fact
+
Prompt
```

Server 返回：

```text
New World IR
+
Runtime Binding:
graveyard ↔ clearing_01
```

Godot：

```text
runtime_fact_id = clearing_01
↓
找回 Spatial Payload
↓
graveyard lower 到真实 clearing polygon
```

Binding 被消费之后可以从 Backend lowering 过程消失，不需要写回 World IR。

---

# 20. Transaction / Commit

一次 World Compile 不应收到 HTTP 200 就直接修改正式状态。

推荐：

```text
IR0 / Facts0 / Scene0
        ↓
Compile
        ↓
Candidate IR1
Bindings
Fact Ops
        ↓
Candidate Runtime Facts
        ↓
World Backend
        ↓
ResolvedWorld1
        ↓
Scene Transition
        ↓
成功
        ↓
COMMIT
```

最后：

```text
Current IR = IR1
Runtime Facts = Candidate Facts
Scene = Scene1
```

任意一步失败：

```text
保持 IR0 / Facts0 / Scene0
```

因此可以由：

```text
WorldCoordinator
```

统一负责事务边界。

---

# 21. World Coordinator

World Coordinator 是总流程协调器。

它负责：

```text
什么时候 compile
什么时候 lower
什么时候 transition
什么时候 commit
什么时候 rollback
```

但不负责：

```text
怎么摆房子
怎么生成 Road Mesh
怎么实例化 church
```

典型调用链：

```text
PromptPanel
↓
WorldCoordinator
↓
CompilerClient
↓
WorldBackend
↓
ResolvedWorld
↓
SceneRuntime
↓
WorldState.commit()
```

---

# 22. 理想 Repo 结构

V0 推荐 repo 大致：

```text
worldir-godot/
│
├── project.godot
│
├── README.md
│
├── docs/
│   ├── architecture.md
│   ├── compiler_contract.md
│   └── backend_contract.md
│
├── assets/
│   ├── raw/
│   │   ├── tree_01.glb
│   │   ├── house_01.glb
│   │   └── church_01.glb
│   │
│   └── prototypes/
│       ├── tree_01.tscn
│       ├── house_01.tscn
│       └── church_01.tscn
│
├── scenes/
│   ├── main.tscn
│   ├── world.tscn
│   ├── player.tscn
│   └── ui/
│       └── prompt_panel.tscn
│
├── scripts/
│   ├── app/
│   │   ├── world_coordinator.gd
│   │   └── world_state.gd
│   │
│   ├── compiler/
│   │   ├── compiler_client.gd
│   │   ├── fake_compiler_client.gd
│   │   └── http_compiler_client.gd
│   │
│   ├── backend/
│   │   ├── world_backend.gd
│   │   ├── region_lowerer.gd
│   │   ├── network_lowerer.gd
│   │   ├── entity_lowerer.gd
│   │   ├── distribution_lowerer.gd
│   │   └── placement_solver.gd
│   │
│   ├── resolved/
│   │   ├── resolved_world.gd
│   │   ├── resolved_region.gd
│   │   ├── resolved_network.gd
│   │   ├── resolved_entity.gd
│   │   └── resolved_distribution.gd
│   │
│   ├── prototype/
│   │   ├── world_prototype.gd
│   │   └── prototype_catalog.gd
│   │
│   ├── runtime/
│   │   ├── scene_runtime.gd
│   │   ├── road_builder.gd
│   │   ├── scene_diff.gd
│   │   └── transition_manager.gd
│   │
│   └── interaction/
│       ├── runtime_fact_manager.gd
│       └── spatial_payload_store.gd
│
├── data/
│   ├── fixtures/
│   │   ├── coastal_town_initial.json
│   │   ├── add_church.json
│   │   └── clearing_to_graveyard.json
│   │
│   └── configs/
│
└── tests/
```

具体文件名可以调整。

真正需要固定的是模块职责边界。

---

# 23. Repo 的简单心智模型

```text
scenes/
→ 游戏本身

assets/
→ GLB 与 TSCN Prototype

compiler/
→ Server Contract / Fake Server

backend/
→ World IR 怎么变成具体空间

resolved/
→ Backend 算完的世界蓝图

prototype/
→ 有哪些素材、素材怎么布局

runtime/
→ 蓝图如何变成 Node / Mesh / Collision

interaction/
→ 玩家行为如何产生 Runtime Facts

app/
→ 把整个流程串起来
```

---

# 24. 对 Coding Agent 的边界设计

架构的一个重要目标是：

> **让代码模块边界与 Coding Agent Task 边界尽量一致。**

例如：

### Task

```text
实现 houses along road
```

主要修改：

```text
backend/distribution_lowerer.gd
backend/placement_solver.gd
tests/
```

---

### Task

```text
给 house 加 Collision
```

主要修改：

```text
assets/prototypes/buildings/house_01.tscn
```

---

### Task

```text
实现 curved road mesh
```

主要修改：

```text
runtime/road_builder.gd
```

---

### Task

```text
接入真实 Server
```

主要修改：

```text
compiler/http_compiler_client.gd
```

---

### Task

```text
实现世界生成动画
```

主要修改：

```text
runtime/transition_manager.gd
```

这种结构能避免 Coding Agent 一次任务同时修改：

```text
IR
HTTP
Placement
Scene
Collision
UI
```

导致系统边界失控。

---

# 25. Coding Agent 建议强制遵守的规则

## Rule 1

```text
Backend 不直接 mutate SceneTree。
```

## Rule 2

```text
SceneRuntime 不解析 World IR semantic relation。
```

## Rule 3

```text
Compiler Client 不负责 lowering / assets / transition。
```

## Rule 4

```text
Placement Solver 不猜 Prototype 尺寸。
```

## Rule 5

```text
所有 Entity / Distribution 的素材先 resolve 成 TSCN Prototype，再 placement。
```

## Rule 6

```text
Runtime Spatial Payload 不发送给 Compiler Server。
```

## Rule 7

```text
Server Response 先成为 Candidate，Scene 成功后才 Commit。
```

## Rule 8

```text
Same Inputs + Same Seed + Same Backend/Prototype Config
应尽量得到 Same Resolved World。
```

---

# 26. V0 完整数据流

## 26.1 First World

```text
User Prompt
    ↓
WorldCoordinator
    ↓
CompilerClient
    ↓
CompileResult
    ↓
World IR
    ↓
Godot World Backend
    ↓
Resolved World
    ↓
Scene Runtime
    ↓
Playable Scene
    ↓
Commit Current IR
```

---

## 26.2 Edit World

```text
Current IR
+
Runtime Facts
+
User Prompt
        ↓
CompilerClient
        ↓
New World IR
+
Bindings
+
Fact Ops
        ↓
Candidate World State
        ↓
Godot World Backend
        ↓
Resolved World Candidate
        ↓
Scene Diff / Transition
        ↓
Success
        ↓
Commit
```

---

## 26.3 Gameplay Runtime Fact

```text
Player Interaction
        ↓
Actual Scene Change
        ↓
RuntimeFactManager
        ↓
Semantic Runtime Fact
+
Spatial Payload
        ↓
WorldState
```

下一次 Prompt 时：

```text
Semantic Runtime Fact
→ 发 Server

Spatial Payload
→ 留 Godot
```

---

# 27. 一个完整示例

World IR：

```text
forest west
coast east
road south → north
church north near road
houses along road count 12
trees inside forest density high
```

Backend：

```text
forest
→ west polygon

coast
→ east polygon

road
→ south→north Curve
→ width

church
→ church_01.tscn
→ footprint
→ north + near road
→ Transform

houses
→ house prototypes
→ along road
→ 12 transforms

trees
→ tree prototypes
→ inside forest polygon
→ N transforms
```

得到：

```text
ResolvedWorld
```

例如：

```text
forest
→ polygon [...]

main_road
→ curve [...]
→ width 6

church
→ prototype church_01
→ Transform3D(...)

houses
→ houses:000
→ houses:001
→ ...
→ houses:011

trees
→ trees:000
→ ...
```

Scene Runtime：

```text
ResolvedWorld
↓
instantiate TSCN
generate road mesh
generate region surface
set transforms
add collision
↓
Playable World
```

---

# 28. V0 暂时不做

为了保持 V0 可实现，暂时不需要：

```text
复杂 Terrain Solver
NavMesh-aware placement
通用 Constraint Optimization
复杂建筑程序生成
Interior Generation
Chunk Streaming
Runtime LLM Loop
Server Session State
WebSocket Streaming
精确跨 Backend 坐标一致
复杂 asset style planner
复杂自动 footprint inference pipeline
```

当前重点：

```text
Region
Network
Entity
Distribution
+
TSCN Prototype
+
Resolved World
+
Playable Scene
```

---

# 29. V0 最重要的架构结论

整个 Godot Backend 可以压缩成：

```text
Compiler Client
→ 拿 World IR

Prototype Catalog
→ 告诉 Backend 有哪些真实素材，以及素材布局尺寸

World Backend
→ 算区域、道路、Prototype 与所有对象位置

Resolved World
→ 保存具体世界蓝图

Scene Runtime
→ 把蓝图真正变成 Godot Node

World State
→ 保存 Current IR 与 Runtime Facts

World Coordinator
→ 管理整个 Compile → Lower → Transition → Commit 事务
```

最终核心边界：

> **World IR 是语义世界。**  
> **Resolved World 是 Godot 的空间蓝图。**  
> **SceneTree 是实际运行中的世界。**

以及：

> **Backend 算，Runtime 生，Coordinator 提交。**

这三层保持分离，就是 Godot V0 最重要的架构约束。
