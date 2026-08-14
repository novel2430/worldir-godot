# World IR V2 设计规范与语义契约

> **状态：Milestone 1 — Semantic Compiler Frontend Baseline**  
> **版本：World IR V2**  
> **目标：自然语言世界描述 / 编辑意图 → 稳定、可验证、后端无关的语义 IR**

---

## 1. 文档目的

World IR V2 是 WorldIR 项目当前用于连接 **LLM 语义理解** 与 **2D / Web3D / Unreal 等世界生成后端** 的中间表示（Intermediate Representation）。

它解决的不是“如何直接摆出 3D 几何”，而是更靠前的一层问题：

> 用户说的世界是什么？对象之间有什么空间关系？重复对象应该如何分布？哪些语义必须被后端保留？

当前系统可以概括为：

```text
Natural Language Prompt / Edit
            ↓
      LLM Compiler Frontend
            ↓
         World IR V2
            ↓
   Deterministic Validation
            ↓
  Target-specific Backend Lowering
     ┌────────┼─────────┐
     ↓        ↓         ↓
    2D      Web3D     Unreal
```

其中，**World IR 是跨后端唯一正式共享的语义接口**。

后端可以拥有自己的 Placement IR、Resolved World、坐标系统、资产表、碰撞规则或生成算法，但这些不进入共享 World IR。

---

# Part I：World IR 的定义域

## 2. World IR 负责什么

World IR V2 只描述**后端无关、对世界语义有稳定意义的结构**。

当前主要覆盖：

1. 世界中有哪些具有语义意义的对象；
2. 哪些对象是区域、网络、单体实体、重复分布；
3. 对象位于世界哪个粗略方向；
4. 对象之间的定性空间关系；
5. Road / Path 等 Network 的连接拓扑；
6. 重复对象的数量、排列方式与空间密度变化；
7. 编辑时哪些原有语义需要保留；
8. 当前 IR 无法表达某项关键约束时，明确报告 IR GAP。

换句话说，它回答的是：

```text
WHAT exists?
WHERE semantically?
HOW are objects related?
HOW does a network connect?
HOW is a repeated population organized?
```

---

## 3. World IR 暂时不负责什么

以下内容刻意不进入 V2：

### 3.1 不负责最终坐标

World IR 不保存：

```text
x / y / z
rotation
scale
bounding box
terrain vertex
```

例如：

```json
{"type": "near", "target": "church"}
```

只表达“靠近教堂”。到底是 8 米、20 米还是基于地图尺寸按比例计算，由 backend lowering 决定。

---

### 3.2 不负责资产和几何

World IR 不指定：

```text
mesh path
FBX / GLTF / UE Asset
material
LOD
collision shape
animation
```

例如 `type="church"` 代表语义上的教堂，而不是某一个特定教堂模型。

---

### 3.3 不负责程序生成算法

IR 可以说：

```text
clustered
random
low → high gradient
```

但不规定 backend 必须使用：

```text
Poisson Disk
Perlin Noise
Voronoi
PCG Graph
某个 UE Blueprint
```

这些属于 backend implementation。

---

### 3.4 不假装支持尚不存在的语义

当前 V2 明确**不支持或不保证支持**：

- 精确数值距离，例如“至少 50 米”；
- 通用 `between(A, B)`；
- 精确角度；
- 精确面积与尺寸；
- 任意连续几何约束；
- 复杂布尔空间关系；
- backend-specific physics constraint。

如果这些语义对用户请求是关键约束，Compiler Frontend 应返回 **IR capability gap**，而不是偷偷弱化成 `near` / `far_from` 等近似关系。

---

## 4. 一个重要原则：语义稳定，几何允许不同

相同 World IR 在不同 backend 中：

- 不要求坐标完全一致；
- 不要求道路形状一致；
- 不要求房屋实例位置一致；
- 不要求森林边界像素级一致。

但必须保留相同的**核心语义**。

例如：

```text
forest 在 west
church 在 north 且 near main_road
houses along main_road
houses far_from church
```

2D、Web3D、Unreal 可以分别得到不同的地图，但这些关系必须成立。

因此目标是：

> **semantic equivalence，而不是 coordinate equivalence。**

---

# Part II：顶层结构

## 5. Root Collections

World IR V2 保留四种 Primitive，并使用四个固定 root collection：

```json
{
  "regions": [],
  "networks": [],
  "entities": [],
  "distributions": []
}
```

四种 Primitive 是当前 IR 的核心本体分类：

| Primitive | 核心语义 |
|---|---|
| `Region` | 有空间范围的场所、环境、聚落、功能区域 |
| `Network` | 具有连接拓扑的道路 / 路径结构 |
| `Entity` | 单个具有明确语义的重要对象、建筑或地标 |
| `Distribution` | 大量同类型实例作为一个整体进行描述 |

当前设计**没有**把它们统一成泛化 `objects[]`，因为四类对象在 backend lowering 中承担的语义责任明显不同。

---

# Part III：Primitive 的定义与分类

## 6. Region

Region 表示有空间范围的地方。

基本形式：

```json
{
  "id": "forest",
  "type": "forest",
  "placement": {
    "anchor": "west"
  }
}
```

`id` 与 `type` 必填，`placement` 可选。

典型 Region：

```text
forest
coast
town
village
graveyard
district
field
swamp
```

### Region 的判断标准

判断依据不是物理大小，而是它在世界中的**空间角色**。

如果一个东西自然被理解成：

> 一个有范围的场所，其他对象可以位于其中或围绕它组织

则优先建模为 Region。

因此：

```text
“小村庄” → Region
```

而不是因为“小”就变成 Entity。

---

## 7. Entity

Entity 表示单个、语义明确的重要物体、建筑、结构或地标。

例如：

```json
{
  "id": "church",
  "type": "church",
  "placement": {
    "anchor": "north"
  }
}
```

典型 Entity：

```text
church
lighthouse
tower
bridge
radio_tower
gas_station
research_lab
```

同样，物体大小本身不是分类标准：

```text
“小教堂” → Entity
```

因为它仍然是一个离散建筑，而不是一个区域。

---

## 8. Region vs Entity

这是 V2 当前非常重要的一条 semantic contract。

### 优先 Region

如果用户把对象描述成：

- 一个地方；
- 一个区域；
- 可以容纳其他对象；
- 其他对象可以 `inside` 它。

例如：

```text
“墓地作为一个区域，里面稀疏分布墓碑”
```

则：

```text
graveyard → Region
tombstones → Distribution
```

### 优先 Entity

如果用户描述的是：

- 单体建筑；
- 单个地标；
- 单一结构；
- 位于某区域里或某对象附近。

例如：

```text
“在村庄里增加一个小教堂”
```

则：

```text
church → Entity
inside village
```

---

## 9. Network

Network 表示连接结构，目前 V2 正式限定：

```text
road
path
```

基本形式：

```json
{
  "id": "main_road",
  "type": "road",
  "topology": {
    "from": "south",
    "to": "north"
  }
}
```

Network 必须拥有 `topology`。

Network 也可以拥有独立的 `placement`，但：

> `topology` 与 `placement` 是两个不同维度。

---

## 10. Distribution

Distribution 表示大量同类型实例的集合，例如：

```text
houses
trees
tombstones
lamps
```

典型形式：

```json
{
  "id": "houses",
  "type": "house",
  "placement": {
    "relations": [
      {"type": "along", "target": "main_road"}
    ]
  },
  "population": {
    "amount": {
      "mode": "count",
      "value": 12
    }
  }
}
```

Distribution 的核心设计思想是把：

```text
WHERE
HOW MANY
HOW ARRANGED
HOW DENSITY VARIES
```

分开描述。

---

# Part IV：Placement — 对象在哪里

## 11. Placement 结构

Region、Network、Entity、Distribution 都可以拥有：

```json
"placement": {
  "anchor": "...",
  "relations": []
}
```

两部分语义不同：

```text
anchor     → 相对于整个 World Frame
relations  → 相对于其他 World Object
```

两者可以同时存在，并且默认是**合取（AND）**关系。

---

## 12. placement.anchor

`anchor` 表示对象位于整个世界的粗略方位。

允许值：

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

例如：

```text
“森林在西边”
```

```json
{
  "placement": {
    "anchor": "west"
  }
}
```

### Anchor 是绝对世界语义

例如：

```text
“北边靠近道路有一个教堂”
```

正确表达是：

```json
{
  "placement": {
    "anchor": "north",
    "relations": [
      {"type": "near", "target": "main_road"}
    ]
  }
}
```

而不是：

```text
direction_of(main_road, north)
```

因为用户表达的是：

```text
世界北边 + 靠近道路
```

而不是：

```text
道路的北边
```

---

# Part V：Relations — 对象之间的空间关系

## 13. 当前 Relation Vocabulary

V2 当前正式支持：

```text
inside
near
far_from
along
direction_of
```

Relation 存放于：

```text
placement.relations[]
```

---

## 14. inside

```json
{"type": "inside", "target": "forest"}
```

表示 source 位于 target Region 内部。

### 类型约束

- Source：Region / Network / Entity / Distribution
- Target：必须是 Region

例如：

```text
trees inside forest
church inside village
```

---

## 15. near

```json
{"type": "near", "target": "church"}
```

表示定性上的接近。

允许所有四种 Primitive 作为 source / target。

距离阈值不属于 World IR，由 backend 定义。

`near` 是 symmetric semantic relation。

---

## 16. far_from

```json
{"type": "far_from", "target": "church"}
```

表示 source 与 target 之间应有明显空间分离。

同样不定义具体米数。

例如：

```text
“住宅不要太靠近教堂”
```

可以表达为：

```json
{"type": "far_from", "target": "church"}
```

### 缺失不等于反义

这一点非常重要：

```text
没有 near ≠ far_from
没有 far_from ≠ near
```

Relation 缺失代表**未指定**。

---

## 17. along

```json
{"type": "along", "target": "main_road"}
```

表示 source 沿某个 Network 布置或分布。

类型限制：

- Source：Entity / Distribution
- Target：Network

典型：

```text
houses along main_road
lamps along path
```

---

## 18. direction_of

```json
{
  "type": "direction_of",
  "target": "forest",
  "direction": "south"
}
```

表示 source 相对于 target 的定性方向。

方向允许：

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

例如：

```text
“在森林南边增加一个小村庄”
```

```json
{
  "id": "village",
  "type": "village",
  "placement": {
    "relations": [
      {
        "type": "direction_of",
        "target": "forest",
        "direction": "south"
      }
    ]
  }
}
```

这里 village 是 Region，而 `direction_of` 负责描述它与 forest 的相对位置。

---

# Part VI：Network Topology — 路怎么连接

## 19. Topology 独立于 Placement

Network 的：

```text
from
to
via
```

统一放在：

```text
topology
```

而不是 Placement。

```json
{
  "id": "main_road",
  "type": "road",
  "topology": {
    "from": "south",
    "to": "north",
    "via": ["church"]
  }
}
```

语义：

```text
道路从南边进入
→ 经过 church
→ 向北边离开
```

### Topology 回答的是连接顺序

```text
HOW DOES THE NETWORK CONNECT?
```

### Placement 回答的是空间位置

```text
WHERE IS THE NETWORK?
```

这两个维度不能混用。

---

# Part VII：Population — 重复对象如何存在

## 20. Population 的三个轴

Distribution 可以包含：

```json
"population": {
  "amount": {},
  "arrangement": {},
  "density_profile": {}
}
```

三个概念分别回答：

```text
amount          → 总体有多少
arrangement     → 实例彼此怎么排列
density_profile → 密度如何随空间变化
```

其中 arrangement 与 density specification 是正交的。

---

## 21. population.amount

Amount 是 tagged union，目前只有两个 mode。

### 21.1 count

精确数量：

```json
{
  "mode": "count",
  "value": 12
}
```

`value` 必须是非负整数。

例如：

```text
“12 栋房子”
```

优先用 count。

---

### 21.2 density

定性的整体均匀密度：

```json
{
  "mode": "density",
  "value": "high"
}
```

允许：

```text
low
medium
high
```

这里的 density 定义为：

> 当前 Distribution placement domain 上的 **uniform / global qualitative density specification**。

因此它不是 density profile。

---

## 22. population.arrangement

Arrangement 描述实例之间的排列结构。

当前支持：

```text
uniform
random
clustered
```

### uniform

近似均匀间隔，不代表必须是严格网格。

### random

不规则随机分布，但没有明显聚团趋势。

### clustered

实例形成局部簇，簇之间相对稀疏。

例如：

```text
“树木明显聚成几团，每团之间留出较大空隙”
```

```json
{
  "arrangement": {
    "type": "clustered"
  }
}
```

### 省略 arrangement 的语义

```text
missing arrangement = unspecified
```

而不是：

```text
missing arrangement = uniform
```

---

## 23. 高层风格词不直接进入 IR

诸如：

```text
natural
wild
eerie
civilized
abandoned
```

不是 V2 的低层空间枚举。

Compiler Frontend 应尝试把高层描述 lower 成真正可以执行的语义。

例如：

```text
“不要像人工均匀种植，而像自然生长”
```

经过 Planner 后，可以具体化为：

```json
{
  "arrangement": {
    "type": "random"
  }
}
```

但不能因为只出现“natural”一个词，就自行发明一大批自然主义结构。

---

# Part VIII：Density Profile — 密度如何随空间变化

## 24. density_profile 与 arrangement 的区别

这两个维度不能混淆：

```text
arrangement
→ 实例相互之间是什么布局结构

 density_profile
→ 同一个空间 domain 内，不同位置的密度如何变化
```

因此完全可以同时存在：

```text
clustered + gradient
```

意思是：

> 树木本身会成团，同时整体上某一方向越来越密。

---

## 25. 当前 DensityProfile：gradient

V2 当前只正式支持：

```text
gradient
```

结构：

```json
{
  "type": "gradient",
  "from": {
    "selector": {},
    "density": "low"
  },
  "to": {
    "selector": {},
    "density": "high"
  }
}
```

它表达的是一个**连续、定性的密度变化意图**。

准确插值方式仍由 backend 决定。

---

## 26. SpatialSelector

Gradient endpoint 不是一个普通 Placement Relation，而是一个**空间取样位置描述**。

目前支持：

```text
anchor
near
far_from
direction_of
```

---

### 26.1 Selector: anchor

```json
{
  "type": "anchor",
  "value": "west"
}
```

这是 world-relative selector，但有一个非常重要的 V2 规则：

> **它在当前 Distribution 的 placement domain 内解析。**

例如 trees 已经：

```json
{
  "placement": {
    "relations": [
      {"type": "inside", "target": "forest"}
    ]
  }
}
```

那么 gradient endpoint：

```json
{"type": "anchor", "value": "west"}
```

表示：

> forest 所限制出的树木生成区域中的 world-west 一侧。

因此：

```text
“越往森林西侧越密”
```

应该使用 `selector anchor=west`。

不能写成：

```json
{
  "type": "direction_of",
  "target": "forest",
  "direction": "west"
}
```

因为后者表示：

> forest 外部的西边。

---

### 26.2 Selector: near / far_from

例如：

```text
“靠近主路比较稀疏，离道路远处更密”
```

可以写：

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
      "type": "far_from",
      "target": "main_road"
    },
    "density": "high"
  }
}
```

---

## 27. amount 与 density_profile 的关系

这是 V2 当前已经确定的重要 contract。

### 27.1 count + density_profile：允许

```text
count
→ 总实例预算

density_profile
→ 这些实例在空间中如何分配
```

例如：

```text
一共 100 棵树，东边稀、西边密
```

概念上可以表达为：

```json
{
  "amount": {
    "mode": "count",
    "value": 100
  },
  "density_profile": {
    "type": "gradient",
    "from": {"...": "..."},
    "to": {"...": "..."}
  }
}
```

---

### 27.2 density + density_profile：禁止

以下组合非法：

```json
{
  "amount": {
    "mode": "density",
    "value": "high"
  },
  "density_profile": {
    "type": "gradient"
  }
}
```

原因是两者都在规定 density：

```text
amount.mode=density
→ uniform/global density

density_profile
→ spatially varying density
```

它们是**同一个 density 维度的两种 specification**，不是两个正交属性。

Deterministic Validator 会直接拒绝这种组合。

---

### 27.3 编辑时允许 density specification 被替换

假设初始状态：

```json
{
  "amount": {
    "mode": "density",
    "value": "high"
  }
}
```

用户说：

```text
“靠近主路稀疏，越往森林西侧越密”
```

那么正确编辑不是保留旧 `density=high` 再新增 profile，而是：

```text
删除旧 uniform/global density
→ 用 gradient density_profile 替代
```

这种删除属于用户主动修改 density 语义，不算违反“其他内容保持不变”。

---

# Part IX：编辑语义与 Preservation

## 28. Current IR 是世界状态

Agentic Editing 中：

> **Chat History 不是 Source of Truth。Current World IR 才是。**

每次编辑原则上接收：

```text
Current IR
+
User modification prompt
```

输出新的完整 IR 或 IR GAP。

---

## 29. Preserve 未修改状态

如果用户说：

```text
“其他内容保持不变”
“不要移动教堂”
```

则应保留对象已有的**真正语义约束**，而不是只保留某一个字段。

例如 church 当前：

```json
{
  "placement": {
    "anchor": "north",
    "relations": [
      {"type": "near", "target": "main_road"}
    ]
  }
}
```

那么“不要移动教堂”通常意味着：

```text
preserve anchor=north
AND
preserve near main_road
```

除非用户明确修改其中之一。

---

## 30. Preserve 不是机械字段冻结

Preservation 必须按语义理解，而不是简单 JSON diff。

例如用户明确把：

```text
uniform density high
```

修改成：

```text
low → high gradient
```

那么删除旧 `amount.mode=density` 是正确修改，不是 preservation violation。

---

# Part X：Compiler Frontend 与 IR GAP

## 31. Compiler Frontend 当前职责

当前 LLM Compiler Frontend 已形成：

```text
User Prompt
    ↓
Router
 ┌──┴──────────┐
 ↓             ↓
Bypass      Planner
 │             │
 └──────┬──────┘
        ↓
Semantic Intent
        ↓
Expressibility
   ┌────┴─────┐
  YES         NO
   ↓           ↓
Editor       IR GAP
   ↓
Validator
   ↓
World IR'
```

---

## 32. Router 的定义域

Router 不负责判断 IR 是否支持。

Router 只判断：

> 用户是否已经明确说出了“世界应该怎么变”。

例如：

```text
“在森林南边增加一个村庄”
```

虽然涉及 IR relation，但语义已经非常明确：

```text
→ bypass
```

而：

```text
“让森林看起来更自然，不像人工种植”
```

属于高层意图：

```text
→ deliberate → Planner
```

---

## 33. Planner 的定义域

Planner 负责：

> 把抽象目标转换成具体的世界语义变化。

Planner 不需要直接输出合法 JSON。

例如：

```text
“自然生长”
```

可以 lower 为：

```text
树木排列改为 random
保持 forest / density / placement 等既有结构
```

---

## 34. Expressibility 的定义域

Expressibility 回答：

> 当前 active World IR schema 能否忠实表达这个 Semantic Intent？

这里不能因为“能写出一个合法 JSON”就判 YES。

关键是：

> 用户的重要语义有没有被保留。

例如：

```text
“住宅距离教堂至少 50 米”
```

虽然可以写 `far_from church`，但会丢失“50 米”的精确约束。

因此必须：

```text
IR GAP
```

---

## 35. Editor 的定义域

Editor 负责：

```text
Semantic Intent
→
Legal World IR
```

它不应：

- 发明 schema 之外的字段；
- 发明 relation type；
- 为了让 JSON 合法而弱化关键语义；
- 无理由删除用户未修改的已有世界状态。

---

# Part XI：Validator

## 36. Deterministic Validator

确定性 Validator 负责可以机械判断的内容：

- root structure；
- required / optional field；
- unknown field；
- enum；
- tagged union；
- ID 唯一性；
- reference integrity；
- relation source / target type compatibility；
- nested selector reference；
- cross-field semantic constraint。

例如现在已经 deterministic enforce：

```text
amount.mode=density
+
density_profile
→ INVALID
```

---

## 37. Semantic Validator

部分错误无法仅靠 JSON schema 判断，例如：

```text
用户要求保持教堂不动，但 Editor 删除了 near road
```

或：

```text
direction_of(forest, west)
被错误用于表示“森林内部西侧”
```

这种需要 Current State + User Intent 才能判断的问题，可以由 semantic validator 检查。

原则是：

> 能 deterministic 的尽量 deterministic；需要理解语义的才交给 LLM。

---

# Part XII：Backend Contract

## 38. Backend 接收到 World IR 后做什么

Backend 负责把 World IR 的语义 lower 成目标环境可以执行的形式。

例如：

```text
World IR
  houses along main_road
  houses far_from church
  count = 12
        ↓
Web3D backend
        ↓
road spline
candidate sampling
constraint scoring
12 concrete transforms
        ↓
Three.js objects
```

另一个 backend 可以完全使用不同算法。

---

## 39. Backend 可以拥有 Local IR

推荐允许：

```text
World IR
   ↓
Backend-specific Lowered IR
   ↓
Resolved Placement / Coordinates
   ↓
Target World
```

例如：

```text
UE Backend
→ PCG Graph constraints
→ FVector / Actor transform

Web Backend
→ JS placement constraints
→ Three.js transforms

2D Backend
→ raster/vector layout
→ PNG
```

但这些 Local IR 不成为新的跨后端共享 contract。

---

## 40. Determinism

目标 deterministic contract：

```text
same World IR
+ same seed
+ same backend version/config
→ same target world
```

这有利于：

- regression test；
- debug；
- replay；
- backend comparison；
- incremental editing。

---

# Part XIII：完整示例

## 41. 示例 World IR V2

自然语言：

> 地图东边是海岸，西边是森林。主路从南向北贯穿区域。北边靠近主路有一座教堂。道路两旁分布 12 栋房屋。森林里有高密度树木。

可以表达为：

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
          "mode": "density",
          "value": "high"
        }
      }
    }
  ]
}
```

---

## 42. 编辑示例：加入相对区域

用户：

```text
在森林南边增加一个小村庄。
```

新增：

```json
{
  "id": "village",
  "type": "village",
  "placement": {
    "relations": [
      {
        "type": "direction_of",
        "target": "forest",
        "direction": "south"
      }
    ]
  }
}
```

Primitive 必须是 Region。

---

## 43. 编辑示例：加入孤立教堂语义

用户：

```text
让教堂仍然位于北边并靠近主路，但住宅不要太靠近它。
```

保持 church：

```text
anchor=north
near main_road
```

houses 增加：

```json
{
  "type": "far_from",
  "target": "church"
}
```

---

## 44. 编辑示例：自然分布

用户：

```text
让森林看起来不像人工均匀种植，而像自然生长。
```

经过 Planner 可 lower 为：

```json
{
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

---

## 45. 编辑示例：Clustered + Gradient

用户：

```text
让森林里的树木明显成团，同时靠近主路的一侧比较稀疏，越往森林西侧越密。
```

正确结果：

```json
{
  "placement": {
    "relations": [
      {
        "type": "inside",
        "target": "forest"
      }
    ]
  },
  "population": {
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
```

这里三个维度分别是：

```text
inside forest      → placement
clustered          → arrangement
low → high         → density profile
```

---

# Part XIV：当前语言设计原则

## 46. 原则一：Orthogonal Semantic Axes

V2 不再不断往 Primitive 顶层增加特殊字段。

核心思想是把问题拆成相对独立的轴：

```text
placement
├── anchor
└── relations

topology
└── from / via / to

population
├── amount
├── arrangement
└── density_profile
```

这让新语义优先寻找“属于哪个维度”，而不是随手新增一个字段。

---

## 47. 原则二：Semantic IR，不是 Geometry IR

World IR 尽量表达：

```text
语义关系
定性结构
用户真正关心的约束
```

而不是：

```text
实现参数
坐标
算法选择
资产细节
```

---

## 48. 原则三：Schema 与 Semantic Contract 分离

当前项目已经明确区分：

### JSON Schema / Spec

回答：

> 什么结构是合法的？

### Semantic Guidance

回答：

> 多个合法结构中，哪个结构真正表示用户这句话？

例如 JSON schema 可以同时允许：

```text
anchor north
```

和：

```text
direction_of road north
```

但 Semantic Guidance 决定：

```text
“北边靠近道路有教堂”
→ anchor north + near road
```

---

## 49. 原则四：不要偷偷近似 IR GAP

如果关键语义不能表达：

```text
return IR GAP
```

比输出一个“看起来差不多”的合法 JSON 更正确。

这是 World IR 能持续演进的重要信号来源。

---

## 50. 原则五：先用真实 Backend 压测，再扩语言

V2 已经完成一次较系统的 semantic coverage。

当前不应仅凭想象继续增加：

```text
between
numeric_distance
复杂 selector
复杂 shape constraints
```

更合理的下一阶段是：

```text
World IR V2
      ↓
Backend Lowering
      ↓
2D / Web3D / Unreal realization
```

用真实 backend failure 来决定下一批 IR extension。

---

# Part XV：当前 Milestone

## 51. Milestone 1 — World IR V2 Semantic Compiler Frontend

截至当前阶段，已经形成并经过覆盖测试的能力包括：

```text
Natural Language Translation     ✓
Agentic Editing                  ✓
Primitive Classification        ✓
Absolute Placement              ✓
Relative Placement              ✓
Negative Spatial Relation       ✓
Network Topology                ✓
Distribution Amount             ✓
Distribution Arrangement        ✓
Continuous Density Gradient     ✓
Arrangement + Gradient          ✓
Preservation Semantics          ✓
IR Expressibility / GAP         ✓
Deterministic Validation        ✓
Semantic Guidance Contract      ✓
Regression Coverage             ✓
```

因此当前阶段可以定义为：

> **World IR V2 已经成为一个可作为后续 backend development baseline 的语义中间表示。**

下一阶段核心问题不再是：

> LLM 能不能写出这个 JSON？

而是：

> Backend 能不能稳定、自然地把这些语义 lower 成一个真正可玩的世界？

---

# Appendix A：V2 快速参考

## A.1 Anchors

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

## A.2 Placement Relations

```text
inside
near
far_from
along
direction_of
```

## A.3 Network Types

```text
road
path
```

## A.4 Amount

```text
count(non-negative integer)
density(low | medium | high)
```

## A.5 Arrangement

```text
uniform
random
clustered
```

## A.6 Density Profile

```text
gradient
```

## A.7 Spatial Selector

```text
anchor
near
far_from
direction_of
```

---

# Appendix B：一句话理解 V2

```text
Region / Entity / Network / Distribution
        ↓
先确定“它是什么”
        ↓
placement 决定“它在哪里”
        ↓
Network.topology 决定“路怎么连接”
        ↓
Distribution.population 决定“重复对象有多少、怎么排、密度怎么变化”
        ↓
无法忠实表达的关键语义 → IR GAP
```

