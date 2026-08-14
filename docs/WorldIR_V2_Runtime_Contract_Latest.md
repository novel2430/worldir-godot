# WorldIR V2 + Runtime Contract V1 — 最新实现规范

> **状态**：Current Implementation Baseline  
> **用途**：LLM Compiler Server 与 Godot Backend 共同遵守的实现级 Contract。  
> **目标**：把 World IR、Runtime Context、Compile Request / Result 的字段、枚举、引用规则与边界一次写清，尽量消除实现歧义。
>
> **规范优先级**：若旧设计文档、示例与本文件冲突，以当前机器可验证定义为准：
>
> 1. `config/world_ir_v2.json`
> 2. `config/world_ir_v2_semantics.md`
> 3. Server V0 的 `runtime_context_v1.schema.json`
> 4. Server V0 的 `compile_request_v1.schema.json`
> 5. Server V0 的 `compile_result_v1.schema.json`
>
> 本文是上述内容的合并实现参考，不扩展新的 World IR 语义。

---

# 1. 最重要的边界

当前系统存在三种不同的数据契约，不要混在一起：

```text
World IR V2
= 世界“语义上是什么”

Runtime Context V1
= 玩家在 Godot Runtime 中留下了什么持久事实

Compile Result V1
= Server 告诉 Godot：下一版 IR 是什么，以及本次 lowering 如何利用 / 清除 Runtime Fact
```

因此：

```text
World IR ≠ Save Game
Runtime Fact ≠ World IR Object
Runtime Binding ≠ World IR Relation
Godot Transform ≠ World IR Placement
```

World IR **不得**包含：

```text
x / y / z
rotation
scale
Transform3D
NodePath
Mesh path
TSCN path
GLB path
3DGS path
collision shape
animation
material
runtime instance id
```

这些属于 Godot Backend / Runtime。

---

# 2. World IR V2 Root

一份合法 World IR V2 的 root **必须且只能**包含四个 collection：

```json
{
  "regions": [],
  "networks": [],
  "entities": [],
  "distributions": []
}
```

规则：

- 四个 root field 全部必填；
- 每个 field 必须是 array；
- 不允许额外 root field；
- 四种 collection 内所有 `id` **全局唯一**，不是只在各 collection 内唯一；
- 当前机器 Validator 只要求 `id` 为 string；实现约定应使用稳定、非空、可读 ID；
- 引用字段引用的是这个全局 ID namespace。

---

# 3. Primitive 总览

| Primitive | Root | 用途 | `type` |
|---|---|---|---|
| Region | `regions[]` | 有空间范围的场所 / 环境 / 聚落 / 功能区域 | 开放 string |
| Network | `networks[]` | road / path 等连接结构 | **固定 enum：`road \| path`** |
| Entity | `entities[]` | 单个重要对象 / 建筑 / 地标 | 开放 string |
| Distribution | `distributions[]` | 大量同类型重复对象 | 开放 string |

注意：

```text
forest / coast / village / graveyard
church / lighthouse / bridge
house / tree / tombstone
```

这些只是常见 semantic type，不是当前 World IR 的全局 enum。

Backend 是否真的有对应素材，是 **Backend capability** 问题，不是 World IR structural validity 问题。

---

# 4. Region

## 4.1 Schema

```json
{
  "id": "forest",
  "type": "forest",
  "placement": {
    "anchor": "west",
    "relations": []
  }
}
```

### 必填

```text
id: string
type: string
```

### 可选

```text
placement: Placement
```

不允许其他字段。

## 4.2 Region vs Entity

优先判断对象在世界中的**空间角色**，不是物理大小。

```text
一个可以容纳 / 组织其他对象的地方
→ Region

一个离散建筑 / 地标 / 结构
→ Entity
```

例如：

```text
“小村庄” → Region
“小教堂” → Entity
“墓地作为一个区域，里面有墓碑” → graveyard Region + tombstone Distribution
```

---

# 5. Entity

## 5.1 Schema

```json
{
  "id": "church",
  "type": "church",
  "placement": {
    "anchor": "north",
    "relations": [
      {
        "type": "near",
        "target": "main_road"
      }
    ]
  }
}
```

### 必填

```text
id: string
type: string
```

### 可选

```text
placement: Placement
```

不允许其他字段。

---

# 6. Network

## 6.1 Schema

```json
{
  "id": "main_road",
  "type": "road",
  "topology": {
    "from": "south",
    "to": "north",
    "via": ["village"]
  },
  "placement": {
    "relations": []
  }
}
```

### 必填

```text
id: string
type: "road" | "path"
topology: Topology
```

### 可选

```text
placement: Placement
```

不允许其他字段。

## 6.2 Network Type Set

```text
road
path
```

这是当前 Network 唯一合法 `type` set。

---

# 7. Topology

Topology 只用于回答：

> **Network 怎么连接？**

不是 generic placement。

## 7.1 Schema

```json
{
  "from": "south",
  "to": "north",
  "via": ["church"]
}
```

### 必填

```text
from: anchor OR existing World IR id
to:   anchor OR existing World IR id
```

### 可选

```text
via: array<string>
```

其中 `via[]` 中每个 string 都必须引用已存在的 World IR `id`。

## 7.2 `from` / `to` 合法值

两种：

```text
A. World anchor
B. 已存在 World IR Object id
```

例如：

```json
{
  "from": "south",
  "to": "church"
}
```

是合法的，只要 `church` 是现有 ID。

---

# 8. Placement

所有四种 Primitive 都可以拥有：

```json
{
  "anchor": "...",
  "relations": []
}
```

`anchor` 与 `relations` 都是可选的。

当前机器 schema 允许空对象：

```json
"placement": {}
```

但实现中如果没有任何 placement semantic，**建议直接省略 `placement`**，不要无意义制造空字段。

## 8.1 Anchor Set

`placement.anchor` 只能是：

```text
north
south
east
west
center
northwest
northeast
southwest
southeast
whole
```

## 8.2 Anchor 语义

`anchor` 永远是：

> **相对于整个 World Frame 的绝对粗粒度方向。**

例如：

```text
“森林在西边”
→ anchor = west

“北边靠近道路有一座教堂”
→ anchor = north
→ near main_road
```

不能错误编码成：

```text
direction_of(main_road, north)
```

因为那表示“教堂在道路北边”，不是“教堂位于世界北边”。

---

# 9. Placement Relation Set

当前合法 Relation **只有五种**：

```text
inside
near
far_from
along
direction_of
```

不能发明：

```text
between
on
behind
in_front_of
adjacent
contains
within_50m
...
```

如果它们是用户请求中的关键语义，应走 IR GAP。

---

# 10. `inside`

```json
{
  "type": "inside",
  "target": "forest"
}
```

### 必填字段

```text
type = "inside"
target: existing World IR id
```

### Source Primitive

```text
Region
Network
Entity
Distribution
```

### Target Primitive

```text
Region only
```

因此：

```text
church inside village       ✓
trees inside forest         ✓
path inside town            ✓
house inside church Entity  ✗
```

---

# 11. `near`

```json
{
  "type": "near",
  "target": "church"
}
```

### Source

四种 Primitive 均可。

### Target

四种 Primitive 均可。

### Semantic

- 定性接近；
- 具体距离由 Backend 定义；
- semantic relation 为 symmetric。

因此：

```text
A near B
```

语义上等价于 B near A，但 IR 不要求重复存两条 edge。

---

# 12. `far_from`

```json
{
  "type": "far_from",
  "target": "church"
}
```

### Source / Target

四种 Primitive 均可。

### Semantic

- 定性明显分离；
- 数值阈值由 Backend 定义；
- symmetric semantic relation。

特别注意：

```text
missing near ≠ far_from
missing far_from ≠ near
```

缺少 relation 只表示：**未指定。**

---

# 13. `along`

```json
{
  "type": "along",
  "target": "main_road"
}
```

### Allowed Source

```text
Entity
Distribution
```

### Allowed Target

```text
Network only
```

例如：

```text
houses along road       ✓
lamps along path        ✓
forest Region along road ✗
```

---

# 14. `direction_of`

```json
{
  "type": "direction_of",
  "target": "forest",
  "direction": "south"
}
```

### Source / Target

四种 Primitive 均可。

### Direction Set

```text
north
south
east
west
northwest
northeast
southwest
southeast
```

注意：这里**没有 `center` 和 `whole`**。

### Semantic

表示：

> source 位于 target 的某个定性方向。

不是 World Frame anchor。

---

# 15. Distribution

## 15.1 Schema

```json
{
  "id": "trees",
  "type": "tree",
  "placement": {
    "relations": [
      {
        "type": "inside",
        "target": "forest"
      }
    ]
  },
  "population": {
    "amount": {
      "mode": "density",
      "value": "high"
    },
    "arrangement": {
      "type": "random"
    }
  }
}
```

### 必填

```text
id: string
type: string
```

### 可选

```text
placement: Placement
population: Population
```

不允许其他字段。

---

# 16. Population

Population 当前最多有三个相互区分的 semantic axis：

```json
{
  "amount": {},
  "arrangement": {},
  "density_profile": {}
}
```

三者全部可选。

它们回答：

```text
amount
→ 总体多少

arrangement
→ 实例彼此怎么排列

density_profile
→ 密度如何随空间变化
```

---

# 17. Amount

`amount` 是 tagged union，只允许两种 mode。

## 17.1 Count

```json
{
  "mode": "count",
  "value": 12
}
```

规则：

```text
mode = "count"
value = 非负整数
```

因此：

```text
0   ✓
12  ✓
-1  ✗
1.5 ✗
true ✗
```

## 17.2 Density

```json
{
  "mode": "density",
  "value": "high"
}
```

Density Set：

```text
low
medium
high
```

这里表示：

> 当前 Distribution placement domain 上的 uniform / global qualitative density。

---

# 18. Arrangement

```json
{
  "type": "clustered"
}
```

Arrangement Set：

```text
uniform
random
clustered
```

语义：

```text
uniform
→ 近似均匀间距，不代表严格 grid

random
→ 不规则随机，没有明显聚团

clustered
→ 局部成簇，簇之间相对稀疏
```

缺少 arrangement：

```text
= unspecified
≠ uniform
```

---

# 19. Density Profile

V2 当前唯一合法 profile：

```text
gradient
```

## 19.1 Schema

```json
{
  "type": "gradient",
  "from": {
    "selector": {
      "type": "near",
      "target": "main_road"
    },
    "density": "low"
  },
  "to": {
    "selector": {
      "type": "anchor",
      "value": "west"
    },
    "density": "high"
  }
}
```

### 必填

```text
type = "gradient"
from: GradientEndpoint
to: GradientEndpoint
```

---

# 20. Gradient Endpoint

```json
{
  "selector": {},
  "density": "low"
}
```

### Density Set

```text
low
medium
high
```

### Selector

必须是当前四种 SpatialSelector 之一。

---

# 21. SpatialSelector Set

当前只有：

```text
anchor
near
far_from
direction_of
```

注意：

> SpatialSelector 是 density profile 的“空间取样位置”，不是 Placement Relation。

---

# 22. Selector: `anchor`

```json
{
  "type": "anchor",
  "value": "west"
}
```

`value` 使用完整 Anchor Set：

```text
north
south
east
west
center
northwest
northeast
southwest
southeast
whole
```

关键语义：

> selector anchor 在**当前 Distribution placement domain 内**解析。

例如：

```text
trees inside forest
+
selector anchor=west
```

表示：

> forest 限制出的树木生成区域中的 world-west 一侧。

不是 forest 外面的西侧。

---

# 23. Selector: `near`

```json
{
  "type": "near",
  "target": "main_road"
}
```

`target` 必须引用现有 World IR ID。

---

# 24. Selector: `far_from`

```json
{
  "type": "far_from",
  "target": "main_road"
}
```

`target` 必须引用现有 World IR ID。

---

# 25. Selector: `direction_of`

```json
{
  "type": "direction_of",
  "target": "forest",
  "direction": "west"
}
```

Direction Set：

```text
north
south
east
west
northwest
northeast
southwest
southeast
```

`target` 必须引用现有 World IR ID。

---

# 26. Population 组合规则

这是 V2 的硬性 cross-field constraint。

## 合法

### `count` 单独使用

```text
count ✓
```

### qualitative `density` 单独使用

```text
density ✓
```

### `count + density_profile`

```text
count + density_profile ✓
```

解释：

```text
count
= 总实例预算

density_profile
= 这些实例在空间中如何分配
```

### Arrangement 可以和上述任意合法 density specification 组合

```text
count + clustered                         ✓
density(high) + random                    ✓
count + clustered + gradient              ✓
arrangement only                          ✓
density_profile only                      ✓
```

## 非法

```text
amount.mode = density
+
density_profile
→ INVALID
```

也就是：

```json
{
  "amount": {
    "mode": "density",
    "value": "high"
  },
  "density_profile": {
    "type": "gradient",
    "from": {},
    "to": {}
  }
}
```

无论 gradient endpoint 是否正确，这个组合本身都非法。

原因：

```text
amount.mode=density
= 一个 global / uniform density specification

density_profile
= 一个 spatially varying density specification
```

同一 density 维度不能同时有两个 authority。

---

# 27. 引用完整性

以下全部必须引用存在的 World IR ID：

```text
Placement Relation.target
Topology.via[]
Topology.from / to（当值不是 anchor 时）
SpatialSelector.target
```

所有引用都使用同一个跨四个 collection 的 global ID namespace。

---

# 28. Unknown Field Policy

World IR V2 当前 deterministic validator 是严格的：

> **不允许未知字段。**

例如以下全部非法：

```json
{
  "id": "church",
  "type": "church",
  "position": [1, 2, 3]
}
```

```json
{
  "id": "trees",
  "type": "tree",
  "density": "high"
}
```

```json
{
  "id": "house",
  "type": "house",
  "placement": {
    "distance": 50
  }
}
```

必须使用 V2 正式字段。

---

# 29. Preservation Rule

编辑模式下：

```text
Current IR
+
User Edit
→ New Full IR
```

Server 返回的是**新的完整 IR**，不是 patch。

没有被用户修改的既有语义应保留。

例如 church 当前：

```json
{
  "placement": {
    "anchor": "north",
    "relations": [
      {
        "type": "near",
        "target": "main_road"
      }
    ]
  }
}
```

用户说：

```text
不要移动教堂
```

正常应同时 preserve：

```text
anchor=north
near main_road
```

Preservation 是语义级，不是机械 freeze JSON field。

例如用户明确把：

```text
density=high
```

改成：

```text
near road low → west high gradient
```

删除旧 `amount.mode=density` 是合法且必要的修改。

---

# 30. 当前明确不支持的 World IR 语义

如果以下约束是用户请求的关键内容，不能偷偷近似：

```text
精确数值距离
“至少 50 米”

通用 between(A, B)

精确角度
精确面积 / 尺寸
任意连续 geometry constraint
复杂布尔空间关系
backend-specific physics constraint
```

应该：

```text
return IR GAP
```

---

# 31. 一份完整合法 World IR V2 示例

```json
{
  "regions": [
    {
      "id": "coast",
      "type": "coast",
      "placement": {
        "anchor": "east"
      }
    },
    {
      "id": "forest",
      "type": "forest",
      "placement": {
        "anchor": "west"
      }
    }
  ],
  "networks": [
    {
      "id": "main_road",
      "type": "road",
      "topology": {
        "from": "south",
        "to": "north"
      }
    }
  ],
  "entities": [
    {
      "id": "church",
      "type": "church",
      "placement": {
        "anchor": "north",
        "relations": [
          {
            "type": "near",
            "target": "main_road"
          }
        ]
      }
    }
  ],
  "distributions": [
    {
      "id": "houses",
      "type": "house",
      "placement": {
        "relations": [
          {
            "type": "along",
            "target": "main_road"
          }
        ]
      },
      "population": {
        "amount": {
          "mode": "count",
          "value": 12
        },
        "arrangement": {
          "type": "random"
        }
      }
    },
    {
      "id": "trees",
      "type": "tree",
      "placement": {
        "relations": [
          {
            "type": "inside",
            "target": "forest"
          }
        ]
      },
      "population": {
        "amount": {
          "mode": "count",
          "value": 100
        },
        "arrangement": {
          "type": "clustered"
        },
        "density_profile": {
          "type": "gradient",
          "from": {
            "selector": {
              "type": "near",
              "target": "main_road"
            },
            "density": "low"
          },
          "to": {
            "selector": {
              "type": "anchor",
              "value": "west"
            },
            "density": "high"
          }
        }
      }
    }
  ]
}
```

---

# Part II — Runtime Contract V1

> **以下不是 World IR。**  
> 它是 Godot Runtime 与 Compiler Server 之间为了玩家交互记忆而增加的旁路 Contract。

---

# 32. Godot Runtime Action Set V0

当前剪枝后的玩家世界修改动作空间为：

```text
ADD
REMOVE
SET_STATE
MARK_AREA
```

当前 V0 **不包含 MOVE**。

这些 Action 不直接发送给 LLM Server。

流程是：

```text
Gameplay Action
↓
Godot hook / log
↓
Godot deterministic aggregation
↓
Runtime Context V1 facts
↓
下一次 /v1/compile
```

典型映射：

| Player Action | Runtime Fact |
|---|---|
| ADD | `added_object` |
| REMOVE 单个重要对象 | `removed_object` |
| REMOVE 大量同类对象 | 聚合成 `marked_area` |
| SET_STATE | `object_state` |
| MARK_AREA | `marked_area` |

---

# 33. Runtime Context Root

固定格式：

```json
{
  "version": "1",
  "facts": []
}
```

规则：

```text
version 必须严格等于 "1"
facts 必须是 array
不允许其他 root field
```

---

# 34. Runtime Semantic Location

某些 Runtime Fact 可以带：

```json
{
  "anchor": "east",
  "inside": "forest",
  "near": "church"
}
```

允许字段只有：

```text
anchor
inside
near
```

至少必须存在一个字段。

`anchor` 使用 World IR 相同 Anchor Set：

```text
north
south
east
west
center
northwest
northeast
southwest
southeast
whole
```

`inside` / `near` 当前 Runtime JSON Schema 只要求为非空 string。

建议 Godot 使用稳定 semantic ID，通常应对应 Current IR 中的对象 ID。

不要发送：

```text
Vector3
Polygon
AABB
Transform3D
NodePath
instance IDs
```

真实 Spatial Payload 留在 Godot。

---

# 35. Runtime Fact: `added_object`

```json
{
  "id": "campfire_01",
  "kind": "added_object",
  "object_type": "campfire",
  "location": {
    "inside": "coast",
    "anchor": "east"
  }
}
```

### Required

```text
id: non-empty string
kind = "added_object"
object_type: non-empty string
```

### Optional

```text
location: SemanticLocation
```

不允许额外字段。

---

# 36. Runtime Fact: `removed_object`

```json
{
  "id": "removed_tree_17",
  "kind": "removed_object",
  "object_type": "tree",
  "location": {
    "inside": "forest",
    "anchor": "east"
  }
}
```

### Required

```text
id
kind = "removed_object"
object_type
```

### Optional

```text
location
```

V0 原则：

> 大量同类型 REMOVE 不要产生几十个 `removed_object`，应由 Godot 聚合成 `marked_area`。

---

# 37. Runtime Fact: `object_state`

对应 Runtime Action：

```text
SET_STATE
```

Schema：

```json
{
  "id": "church_door_open",
  "kind": "object_state",
  "target": "church_door",
  "state": "open"
}
```

### Required

```text
id: non-empty string
kind = "object_state"
target: non-empty string
state: non-empty string
```

### 非常重要：`state` 当前没有全局 enum

也就是说当前正式 Runtime Context V1 **没有规定**：

```text
state ∈ {open, closed, active, ...}
```

它只要求 non-empty string。

原因是状态属于具体 Interactable / Prototype 的 runtime vocabulary，不属于 World IR。

常见例子可以是：

```text
open
closed
active
inactive
burning
damaged
```

但这些目前只是示例，**不是全局合法 Set**。

### Godot 实现建议（非 World IR 规范）

为了避免 runtime 自己产生歧义，建议每类 Interactable 在 Prototype / script 中声明自己的允许状态，例如：

```text
Door:
  closed | open

Machine:
  inactive | active

Fire:
  unlit | burning
```

Server Contract 仍只看到普通 string。

---

# 38. Runtime Fact: `marked_area`

```json
{
  "id": "clearing_01",
  "kind": "marked_area",
  "mark": "cleared",
  "location": {
    "inside": "forest",
    "anchor": "east"
  },
  "affected_type": "tree",
  "count": 23
}
```

### Required

```text
id
kind = "marked_area"
mark
location
```

### Optional

```text
affected_type: non-empty string
count: non-negative integer
```

### Mark Set V1

```text
cleared
burned
```

当前只有这两个正式合法值。

---

# 39. Runtime Fact ID 与 Spatial Payload

Godot 内应该把同一个 Runtime Fact 分成两部分：

```text
clearing_01
│
├── Semantic Fact
│   → 发给 Server
│
└── Spatial Payload
    → 只留 Godot
```

例如：

```text
Semantic:
inside forest
anchor east
count 23

Spatial Payload:
polygon
center
AABB
affected tree instance IDs
```

Server 以后只通过：

```text
runtime_fact_id = "clearing_01"
```

把两边重新关联。

---

# Part III — Compile API Data Contract

---

# 40. CompileRequest V1

`POST /v1/compile` body：

```json
{
  "prompt": "...",
  "current_ir": null,
  "runtime_context": {
    "version": "1",
    "facts": []
  }
}
```

### Required Root Fields

```text
prompt
current_ir
runtime_context
```

不允许其他 root field。

### `prompt`

```text
non-empty string
```

### `current_ir`

```text
object | null
```

语义：

```text
null
→ initial generation

object
→ edit existing world
```

虽然 CompileRequest JSON Schema 只声明 `object | null`，Server 仍必须对非 null object 做完整 World IR V2 validation。

### `runtime_context`

必须符合 Runtime Context V1。

Initial Generation 的额外协议规则：

```text
current_ir = null
→ runtime_context.facts 应为空
```

---

# 41. CompileResult V1 — Success

```json
{
  "status": "ok",
  "world_ir": {
    "regions": [],
    "networks": [],
    "entities": [],
    "distributions": []
  },
  "runtime_bindings": [],
  "runtime_fact_ops": [],
  "meta": {
    "request_id": "req_xxx",
    "mode": "edit",
    "route": "bypass"
  }
}
```

Required：

```text
status
world_ir
runtime_bindings
runtime_fact_ops
meta
```

`world_ir` 是**下一版完整 World IR V2**，不是 patch。

---

# 42. Compile Result Status Set

当前只有：

```text
ok
ir_gap
```

`ir_gap` 是语义编译的正常结果，不是 HTTP Server crash。

---

# 43. Runtime Binding V1

Schema：

```json
{
  "ir_object_id": "graveyard",
  "runtime_fact_id": "clearing_01",
  "placement": "inside"
}
```

Required：

```text
ir_object_id
runtime_fact_id
placement
```

### Placement Set

```text
at
inside
near
```

语义：

```text
ir_object_id
→ Candidate World IR 中的对象

runtime_fact_id
→ 本次请求 Runtime Context 中的 Fact

placement
→ Godot lowering 时如何使用该 Fact 的 Spatial Payload
```

Runtime Binding：

```text
不是 World IR Relation
不是长期状态
不是写回 IR 的字段
```

它是本次 compile transaction 的一次性 lowering hint。

---

# 44. Runtime Fact Op V1

当前只有一种 op：

```text
clear
```

Schema：

```json
{
  "op": "clear",
  "runtime_fact_id": "clearing_01"
}
```

当前没有：

```text
update
merge
promote
replace
move
```

### Default Rule

如果 Server 没有返回 `clear`：

> 玩家留下的 Runtime Fact 默认继续 Preserve。

---

# 45. Compile Meta

```json
{
  "request_id": "req_xxx",
  "mode": "edit",
  "route": "bypass"
}
```

### Required

```text
request_id: non-empty string
mode: "initial" | "edit"
```

### Optional

```text
route
```

### Route Set

如果 `route` 出现，只允许：

```text
bypass
deliberate
```

**不存在 `route = "initial"`。**

Initial compile 没有 Router 路径时，应直接省略 `route`。

正确 initial meta 例如：

```json
{
  "request_id": "req_000001",
  "mode": "initial"
}
```

---

# 46. IR GAP Result

```json
{
  "status": "ir_gap",
  "gap": {
    "reason": "The requested semantic constraint cannot be represented by World IR V2.",
    "unsupported": [
      "exact numeric distance"
    ]
  },
  "meta": {
    "request_id": "req_000002",
    "mode": "edit",
    "route": "bypass"
  }
}
```

### Required

```text
status = "ir_gap"
gap
meta
```

`gap`：

```text
reason: non-empty string
unsupported: array<string>
```

IR GAP 时没有 `world_ir`、`runtime_bindings`、`runtime_fact_ops`。

---

# 47. 第一次 Compile 的完整正确示例

## Request

```json
{
  "prompt": "生成一个废弃海边小镇，西边是森林，东边是海岸，一条主路从南到北。",
  "current_ir": null,
  "runtime_context": {
    "version": "1",
    "facts": []
  }
}
```

## Response

```json
{
  "status": "ok",
  "world_ir": {
    "regions": [
      {
        "id": "forest",
        "type": "forest",
        "placement": {
          "anchor": "west"
        }
      },
      {
        "id": "coast",
        "type": "coast",
        "placement": {
          "anchor": "east"
        }
      }
    ],
    "networks": [
      {
        "id": "main_road",
        "type": "road",
        "topology": {
          "from": "south",
          "to": "north"
        }
      }
    ],
    "entities": [],
    "distributions": [
      {
        "id": "trees",
        "type": "tree",
        "placement": {
          "relations": [
            {
              "type": "inside",
              "target": "forest"
            }
          ]
        },
        "population": {
          "amount": {
            "mode": "density",
            "value": "high"
          }
        }
      }
    ]
  },
  "runtime_bindings": [],
  "runtime_fact_ops": [],
  "meta": {
    "request_id": "req_000001",
    "mode": "initial"
  }
}
```

---

# 48. Runtime Fact + Edit Compile 完整示例

玩家已经在森林东侧砍出空地。

Godot Runtime Context：

```json
{
  "version": "1",
  "facts": [
    {
      "id": "clearing_01",
      "kind": "marked_area",
      "mark": "cleared",
      "location": {
        "inside": "forest",
        "anchor": "east"
      },
      "affected_type": "tree",
      "count": 23
    }
  ]
}
```

玩家 Prompt：

```text
把我刚刚砍出来的地方变成墓地。
```

Server 可以返回：

```json
{
  "status": "ok",
  "world_ir": {
    "regions": [
      {
        "id": "forest",
        "type": "forest",
        "placement": {
          "anchor": "west"
        }
      },
      {
        "id": "coast",
        "type": "coast",
        "placement": {
          "anchor": "east"
        }
      },
      {
        "id": "graveyard",
        "type": "graveyard"
      }
    ],
    "networks": [
      {
        "id": "main_road",
        "type": "road",
        "topology": {
          "from": "south",
          "to": "north"
        }
      }
    ],
    "entities": [],
    "distributions": [
      {
        "id": "trees",
        "type": "tree",
        "placement": {
          "relations": [
            {
              "type": "inside",
              "target": "forest"
            }
          ]
        },
        "population": {
          "amount": {
            "mode": "density",
            "value": "high"
          }
        }
      }
    ]
  },
  "runtime_bindings": [
    {
      "ir_object_id": "graveyard",
      "runtime_fact_id": "clearing_01",
      "placement": "inside"
    }
  ],
  "runtime_fact_ops": [],
  "meta": {
    "request_id": "req_000002",
    "mode": "edit",
    "route": "bypass"
  }
}
```

这里：

```text
graveyard
→ 已正式成为 World IR Region

clearing_01
→ 仍然只是 Runtime Fact

runtime_binding
→ 本次告诉 Godot 把 graveyard lower 到 clearing_01 的 Spatial Payload
```

---

# 49. Restore Runtime Fact 示例

玩家 Prompt：

```text
恢复我刚刚砍掉的森林。
```

World IR 可能完全不需要变化。

Server 可以返回：

```json
{
  "status": "ok",
  "world_ir": {
    "regions": ["...完整 IR，不是 patch..."],
    "networks": [],
    "entities": [],
    "distributions": []
  },
  "runtime_bindings": [],
  "runtime_fact_ops": [
    {
      "op": "clear",
      "runtime_fact_id": "clearing_01"
    }
  ],
  "meta": {
    "request_id": "req_000003",
    "mode": "edit",
    "route": "bypass"
  }
}
```

注意：上面 `"...完整 IR，不是 patch..."` 只是说明文字，真实 API 中必须返回完整合法 World IR 对象，不能真的发送该字符串。

---

# 50. 所有正式 Set / Enum 一页速查

## World IR V2

### Root Collections

```text
regions
networks
entities
distributions
```

### Primitive

```text
Region
Network
Entity
Distribution
```

### Anchor

```text
north
south
east
west
center
northwest
northeast
southwest
southeast
whole
```

### Relation Direction

```text
north
south
east
west
northwest
northeast
southwest
southeast
```

### Placement Relation

```text
inside
near
far_from
along
direction_of
```

### Network Type

```text
road
path
```

### Amount Mode

```text
count
density
```

### Qualitative Density

```text
low
medium
high
```

### Arrangement

```text
uniform
random
clustered
```

### Density Profile Type

```text
gradient
```

### Spatial Selector Type

```text
anchor
near
far_from
direction_of
```

---

## Runtime Context V1

### Player Action Set V0

```text
ADD
REMOVE
SET_STATE
MARK_AREA
```

### Runtime Fact Kind

```text
added_object
removed_object
object_state
marked_area
```

### Marked Area Mark

```text
cleared
burned
```

### Object State

```text
NO GLOBAL ENUM
```

`state` 当前是 non-empty string，由具体 Godot Interactable / Prototype 定义。

---

## Compile Result V1

### Status

```text
ok
ir_gap
```

### Mode

```text
initial
edit
```

### Route（optional）

```text
bypass
deliberate
```

### Runtime Binding Placement

```text
at
inside
near
```

### Runtime Fact Op

```text
clear
```

---

# 51. Godot 实现时最值得死记的边界

```text
World IR
→ semantic world

Runtime Context
→ player-created semantic deviations

Runtime Spatial Payload
→ Godot-only coordinates / polygon / instances

Runtime Binding
→ one-shot bridge from new IR object to Runtime Spatial Payload

Resolved World
→ Godot Backend 算出的具体空间蓝图

SceneTree
→ 真正运行中的游戏世界
```

完整流：

```text
Prompt
+
Current World IR
+
Runtime Context
        ↓
Compiler Server
        ↓
New Full World IR
+
Bindings
+
Fact Ops
        ↓
Godot Backend
        ↓
Resolved World
        ↓
Animated Scene Transition
        ↓
Commit
```

---

# 52. 最终 Contract 原则

1. **World IR V2 只有四种 Primitive。**
2. **未知字段、未知 Relation、未知 enum 一律非法。**
3. **所有 `type` 字段在 JSON 中仍是 string，但语义值必须属于 World Catalog V1；Godot Prototype capability 是独立的后端检查。**
4. **Placement 的 absolute anchor 与 object-relative relation 必须分清。**
5. **所有 World IR 引用使用跨四类 Primitive 的 global ID namespace。**
6. **Distribution 的 amount / arrangement / density_profile 是独立 semantic axis。**
7. **`amount.mode=density + density_profile` 明确非法。**
8. **无法忠实表达的关键语义返回 IR GAP，不偷偷近似。**
9. **Runtime Context 不属于 World IR。**
10. **`SET_STATE` 通过 `object_state` 保存，但 state vocabulary 当前不设全局 enum。**
11. **玩家 Runtime Fact 默认 Preserve；V1 只有 `clear` 能显式移除。**
12. **Runtime Binding 只在本次 Godot lowering 中使用，不写回 World IR。**
13. **Server 返回完整 New IR，不返回 IR patch。**
14. **`meta.route` 只有 bypass / deliberate；initial 请求通常省略 route。**
15. **坐标、资产、碰撞、动画始终属于 Godot Backend / Runtime。**
