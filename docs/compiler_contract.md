# WorldIR Godot ↔ LLM Compiler Server API Contract V0

> **用途**：Godot Backend 开发阶段的接口基线。本文只描述 Godot 需要知道的 Server API、JSON Contract 与调用方式；不讨论 Router / Planner / Editor 等 Server 内部实现。
>
> **基线**：WorldIR LLM Compiler Server V0、World IR V2、Runtime Context V1、Compile Result V1。

---

## 1. Godot 需要把 Server 当成什么？

Godot 把 LLM Compiler Server 当成一个**低频、事务式的语义编译服务**：

```text
Godot 持有：
- Current World IR
- Runtime Facts
- Runtime Fact 的真实空间 payload
- Actual Scene

Godot 发送：
Current World IR + Runtime Context + User Prompt

Server 返回：
New World IR + Runtime Bindings + Runtime Fact Ops
```

Server 不返回 Godot 坐标、NodePath、Mesh、动画或资产路径。Godot 收到编译结果后，才负责 lowering、placement、scene diff 与 A→B 动画。

默认 Base URL：

```text
http://127.0.0.1:8787
```

Godot 侧应把 Base URL 做成可配置项，不要散落硬编码。

---

## 2. V0 只有三个 API

| Method | Path | Godot 何时调用 | 是否触发 LLM |
|---|---|---|---|
| `GET` | `/health` | 启动时检查 Server 是否存活 | 否 |
| `GET` | `/info` | 启动时检查协议版本 | 否 |
| `POST` | `/v1/compile` | 第一次生成世界、之后每次 Prompt 编辑世界 | 是 |

V0 **没有**：`/session`、`/history`、`/save`、`/load`、`/assets`、`/auth`。

---

# 3. `GET /health`

## 用途

Godot 启动后先检查 Compiler Server 是否已经启动。

### Request

```http
GET /health
```

### Response — HTTP 200

```json
{
  "status": "ok"
}
```

## Godot 行为

- `200 + status=ok`：Server 可用。
- 网络失败 / 非 200：Compiler 暂不可用；不要进入世界编译流程。
- `/health` 不代表 LLM Provider 一定可用，只代表本地 Server 活着。

---

# 4. `GET /info`

## 用途

确认 Godot 当前实现和 Server 使用的是同一版 Contract。

### Response

```json
{
  "compiler_version": "0.3.0",
  "world_ir_version": "2",
  "world_catalog_version": "1",
  "runtime_context_version": "1",
  "compile_result_version": "1"
}
```

## V0 Godot 建议检查

```text
world_ir_version == "2"
world_catalog_version == "1"
runtime_context_version == "1"
compile_result_version == "1"
```

如果不匹配，应明确报 protocol mismatch，而不是继续猜字段。

`compiler_version` 主要用于日志/debug，不要求 Godot 与它完全一致。

---

# 5. `POST /v1/compile`

这是 Godot 唯一真正的世界编译 API。

同一个 Endpoint 同时负责：

```text
Initial Generation
Edit Existing World
```

请求必须发送 JSON，并使用：

```http
Content-Type: application/json
```

---

## 5.1 CompileRequest V1

固定 Root：

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

### 字段

| 字段 | 类型 | 含义 |
|---|---|---|
| `prompt` | string | 玩家本次给“世界设计者”的原始 Prompt |
| `current_ir` | object / null | 当前完整 World IR；第一次生成时必须为 `null` |
| `runtime_context` | object | 玩家 interaction 形成的语义 Runtime Facts |

---

# 6. 第一次生成世界

玩家输入：

```text
生成一个废弃的海边小镇，西边是森林，东边是海岸。
```

Godot 请求：

```json
{
  "prompt": "生成一个废弃的海边小镇，西边是森林，东边是海岸。",
  "current_ir": null,
  "runtime_context": {
    "version": "1",
    "facts": []
  }
}
```

规则：

```text
current_ir = null
→ Initial Generation

Initial Generation
→ runtime_context.facts 必须为空
```

Server 成功后返回完整 `world_ir`。Godot 用它生成第一版世界。

---

# 7. 第二次及之后编辑世界

玩家游玩后，Godot 已经持有：

```text
Current World IR = IR0
Runtime Facts = 玩家造成的重要改变
```

例如玩家在森林东侧砍出一块空地：

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

然后玩家 Prompt：

```text
把我刚刚砍出来的地方变成墓地。
```

请求：

```json
{
  "prompt": "把我刚刚砍出来的地方变成墓地。",
  "current_ir": {
    "regions": ["..."],
    "networks": ["..."],
    "entities": ["..."],
    "distributions": ["..."]
  },
  "runtime_context": {
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
}
```

这里 `current_ir` 实际发送完整合法 World IR，上面的 `"..."` 仅用于文档省略。

---

# 8. Runtime Context V1

Root 永远是：

```json
{
  "version": "1",
  "facts": []
}
```

V1 只允许四种 Runtime Fact。

## 8.1 `added_object`

玩家向世界中放置了一个有意义的对象。

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

## 8.2 `removed_object`

玩家移除了一个**值得单独记住**的对象。

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

大量重复对象被删除时，不要传几十个 `removed_object`，应由 Godot 聚合成 `marked_area`。

## 8.3 `object_state`

玩家改变了一个可互动对象的持久状态。

```json
{
  "id": "church_door_open",
  "kind": "object_state",
  "target": "church_door",
  "state": "open"
}
```

`state` 是 Backend/interactable 自己的 vocabulary，不属于 World IR V2。

## 8.4 `marked_area`

玩家行为形成了有空间意义的痕迹。

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

V1 `mark` 仅允许：

```text
cleared
burned
```

---

# 9. `location` 的 API 语义

Runtime Fact 中的 semantic location 可以包含：

```json
{
  "anchor": "east",
  "inside": "forest",
  "near": "church"
}
```

其中 `anchor` 可取：

```text
north / south / east / west / center
northwest / northeast / southwest / southeast
whole
```

它是给 Compiler 阅读的**语义位置**，不是 Godot 真实坐标。

---

# 10. Godot 必须自己保留 Spatial Payload

同一个 Runtime Fact 在 Godot 内应有两份视图：

```text
clearing_01
│
├── Semantic View
│   → 发给 Compiler
│   → inside=forest, anchor=east, count=23
│
└── Spatial Payload
    → 只留在 Godot
    → polygon / AABB / center / instance IDs / Transform 等
```

**不要把 Polygon、Transform3D、NodePath 等通过 Compiler API 发出去。**

之后 Server 如果返回：

```text
runtime_fact_id = clearing_01
```

Godot 用这个 ID 找回自己的真实 Spatial Payload。

---

# 11. CompileResult — `status = ok`

正常成功：

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
    "request_id": "...",
    "mode": "edit",
    "route": "bypass"
  }
}
```

Godot 真正需要消费的只有三个字段：

```text
world_ir
runtime_bindings
runtime_fact_ops
```

`meta` 主要用于 trace/debug。

---

# 12. `world_ir`

`world_ir` 是**下一版完整 World IR**，不是 patch。

因此 Godot 不应该：

```text
IR0 + 手动套一个 JSON patch
```

而应该把返回值视为：

```text
Candidate IR1
```

只有整个 Backend 应用流程成功后，才把 `Current World IR` 从 IR0 commit 为 IR1。

---

# 13. Runtime Binding V1

Binding 解决：

> 新 IR 对象需要利用玩家 Runtime 中的某个真实位置，但这个 Runtime 对象本身不进入 World IR。

格式：

```json
{
  "ir_object_id": "graveyard",
  "runtime_fact_id": "clearing_01",
  "placement": "inside"
}
```

V1 `placement` 只允许：

```text
at
inside
near
```

Godot 的解释：

```text
ir_object_id
→ 找到 IR 中准备生成的对象

runtime_fact_id
→ 找到 Godot Runtime Fact 的 Spatial Payload

placement
→ Backend lowering 时怎样利用这个 payload
```

例如：

```text
graveyard + clearing_01 + inside
→ 在 clearing_01 对应的实际范围内 lower graveyard
```

Binding 是**一次性 lowering hint**：

```text
CompileResult
→ Godot 消费
→ placement 完成
→ 不写回 World IR
```

---

# 14. Runtime Fact Ops V1

默认规则：

> 玩家留下的 Runtime Facts 在世界重新编辑后继续保留。

V1 Server 只能要求一种操作：

```text
clear
```

格式：

```json
{
  "op": "clear",
  "runtime_fact_id": "clearing_01"
}
```

典型 Prompt：

```text
恢复我刚刚砍掉的森林。
```

World IR 可能根本没有变化，但 Server 返回：

```text
clear clearing_01
```

Godot 据此让之前因玩家造成的 clearing 消失，并让实际世界重新趋近 IR 定义的森林。

---

# 15. `status = ir_gap`

IR 无法忠实表示用户要求时，不是 Server 崩溃，而是正常语义结果。

HTTP 仍为 `200`：

```json
{
  "status": "ir_gap",
  "gap": {
    "reason": "The requested semantic constraint cannot be represented by the active World IR contract.",
    "unsupported": ["..."]
  },
  "meta": {
    "request_id": "...",
    "mode": "edit",
    "route": "bypass"
  }
}
```

Godot 行为：

```text
显示/记录 gap 信息
不修改 Current IR
不修改 Runtime Facts
不改变 Scene
```

---

# 16. HTTP Error Policy

| HTTP | 意义 | Godot 行为 |
|---|---|---|
| `200` | `ok` 或 `ir_gap` | 按 JSON `status` 分支 |
| `400` | API Request Shape 错误 | 视为客户端 bug，记录完整错误 |
| `422` | Current IR / Runtime Context 违反 Contract | 视为状态/协议 bug，不修改世界 |
| `500` | Compiler Server 内部异常 | 保持旧世界 |
| `502` | 上游 LLM Provider 失败 | 保持旧世界，可提示重试 |
| `504` | LLM Provider timeout | 保持旧世界，可提示重试 |

此外，如果 Godot 的 `HTTPRequest` 本身没有成功完成，同样视为 transport failure：

```text
No Commit
No Fact Mutation
No Transition
```

---

# 17. 最重要的 Godot Transaction Rule

一次 world compile **不能收到 HTTP 200 就立刻修改正式状态**。

推荐顺序：

```text
1. POST /v1/compile
        ↓
2. 收到 status=ok
        ↓
3. 保存为 Candidate：
   candidate_ir
   candidate_bindings
   candidate_fact_ops
        ↓
4. 在 Runtime Facts 的临时副本上应用 fact_ops
        ↓
5. Godot Backend：
   candidate_ir
   + candidate runtime facts
   + bindings
   → Desired World
        ↓
6. 准备/执行 A → B Transition
        ↓
7. 全部成功
        ↓
8. COMMIT：
   Current IR = candidate_ir
   Runtime Facts = candidate runtime facts
   Scene = New Scene
```

任何一步失败：

```text
ROLLBACK / 保持旧状态
```

尤其不要在 Transition 完成前永久 `clear` Runtime Fact。

---

# 18. Godot 侧建议只有一个 `CompilerClient`

推荐概念结构：

```text
CompilerClient (Autoload / Service Node)
│
├── base_url
├── HTTPRequest
├── health()
├── info()
├── compile_world(...)
└── response/error signals
```

它只负责 HTTP 与 JSON Contract。

不要让它负责：

```text
World lowering
Runtime Fact aggregation
Asset selection
Scene transition
```

这样 Server Contract 与 Godot World Backend 不会混在一起。

---

# 19. Godot `HTTPRequest` 最小调用方式

Godot 官方的 `HTTPRequest` Node 可以直接发送 HTTP(S) 请求。V0 是低频的 Prompt 编译请求，因此一个串行 `HTTPRequest` 就足够。

概念性 GDScript：

```gdscript
extends Node

const BASE_URL := "http://127.0.0.1:8787"

@onready var http: HTTPRequest = $HTTPRequest

func _ready() -> void:
    http.request_completed.connect(_on_request_completed)
    # 项目建议值：应略大于 Compiler Server 的 LLM timeout。
    http.timeout = 120.0

func compile_world(
    prompt: String,
    current_ir: Variant,
    runtime_context: Dictionary
) -> Error:
    var payload := {
        "prompt": prompt,
        "current_ir": current_ir,
        "runtime_context": runtime_context,
    }

    var headers := PackedStringArray([
        "Content-Type: application/json"
    ])

    return http.request(
        BASE_URL + "/v1/compile",
        headers,
        HTTPClient.METHOD_POST,
        JSON.stringify(payload)
    )

func _on_request_completed(
    result: int,
    response_code: int,
    headers: PackedStringArray,
    body: PackedByteArray
) -> void:
    if result != HTTPRequest.RESULT_SUCCESS:
        push_error("Compiler transport failed")
        return

    var data = JSON.parse_string(body.get_string_from_utf8())

    if response_code != 200:
        push_error("Compiler HTTP error: %s" % response_code)
        return

    if typeof(data) != TYPE_DICTIONARY:
        push_error("Compiler returned invalid JSON")
        return

    match data.get("status", ""):
        "ok":
            # 交给 WorldBackend 准备 Candidate World。
            pass
        "ir_gap":
            # 提示用户；世界保持不变。
            pass
        _:
            push_error("Unknown compiler result")
```

注意：同一个 `HTTPRequest` Node 在一个请求尚未完成时，不应并发发送另一个请求。V0 推荐把 world compile 串行化；如果未来确实需要并行请求，再使用多个 HTTPRequest 实例。

---

# 20. 推荐启动流程

```text
Godot Start
   ↓
GET /health
   ↓ success
GET /info
   ↓ versions compatible
Compiler Ready
   ↓
允许玩家提交 First Prompt
```

如果 Server 暂时不可用，Godot 可以仍然显示 UI/场景，但不要允许提交世界编译事务。

---

# 21. 推荐 First Prompt 流程

```text
User Prompt
   ↓
POST /v1/compile
current_ir = null
runtime facts = []
   ↓
status=ok
   ↓
Godot Lower IR
   ↓
构建 Initial Scene
   ↓
Commit Current IR
```

第一次生成没有旧世界时，是否做“世界从虚无生成”的动画属于 Godot Transition System，不属于 Server API。

---

# 22. 推荐 Edit Prompt 流程

```text
IR0 + RuntimeFacts0 + Prompt2
        ↓
POST /v1/compile
        ↓
IR1 + Bindings + FactOps
        ↓
复制 RuntimeFacts0
        ↓
对副本应用 FactOps
        ↓
Lower(IR1, RuntimeFactsCandidate, Bindings)
        ↓
Desired World1
        ↓
Scene0' → Scene1 动画
        ↓
成功后一次性 Commit：
CurrentIR = IR1
RuntimeFacts = RuntimeFactsCandidate
```

这条链是 Godot 侧最重要的运行 Contract。

---

# 23. 完整例子：砍树 → Prompt → 墓地

## Step A — Initial

```text
Prompt:
“生成一个废弃海边小镇。”

current_ir = null
runtime_context = []
```

Server：

```text
→ IR0
```

Godot：

```text
IR0 → World0
```

## Step B — Gameplay

玩家砍掉森林东侧很多树。

Godot：

```text
REMOVE tree × N
→ deterministic aggregation
→ clearing_01
```

同时 Godot 自己保存：

```text
clearing_01 spatial payload
→ 实际 polygon / center / affected instances
```

## Step C — Second Prompt

```text
“把我刚刚砍出来的地方变成墓地。”
```

Godot：

```text
POST /v1/compile
IR0 + clearing_01 + prompt
```

Server：

```json
{
  "status": "ok",
  "world_ir": {
    "regions": ["...graveyard..."],
    "networks": ["..."],
    "entities": ["..."],
    "distributions": ["..."]
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
    "request_id": "req_xxx",
    "mode": "edit",
    "route": "bypass"
  }
}
```

Godot：

```text
binding references clearing_01
↓
找回 clearing_01 实际 spatial payload
↓
把 graveyard lower 到这块范围
↓
计算 Desired World
↓
墓碑/地表/VFX 渐进生成
↓
Transition 成功
↓
Commit IR1
```

这就是 Server API 与 Godot Backend 的完整接缝。

---

# 24. Godot 侧 V0 不需要做什么

API Client 层不要提前实现：

```text
WebSocket streaming
LLM token streaming
Server session state
Prompt history synchronization
Runtime Selector DSL
Runtime → IR Promotion
Server asset API
复杂请求并发
```

当前只需要保证：

```text
GET health
GET info
POST compile

+ Runtime Context V1
+ Compile Result V1
+ Transactional Commit
```

---

# 25. 一页速查

```text
BASE URL
http://127.0.0.1:8787

STARTUP
GET /health
GET /info

FIRST WORLD
POST /v1/compile
{
  prompt,
  current_ir: null,
  runtime_context: {version:"1", facts:[]}
}

EDIT WORLD
POST /v1/compile
{
  prompt,
  current_ir: IR0,
  runtime_context: RuntimeFacts0
}

SUCCESS
{
  status:"ok",
  world_ir: IR1,
  runtime_bindings:[...],
  runtime_fact_ops:[...],
  meta:{...}
}

SEMANTIC FAILURE
HTTP 200 + status:"ir_gap"
→ WORLD UNCHANGED

INFRA FAILURE
400 / 422 / 500 / 502 / 504 / transport failure
→ WORLD UNCHANGED

COMMIT RULE
Server response ≠ immediately commit

Compile
→ Candidate Lowering
→ Desired World
→ Animated Transition
→ Success
→ Commit IR + Runtime Facts
```

---

## Contract 结论

Godot 对 Compiler Server 的理解可以永远保持在这一句话：

> **Godot 把“当前设计状态 + 玩家留下的语义事实 + 新 Prompt”交给 Server；Server 返回“新的设计状态 + 本次如何利用玩家痕迹 + 哪些玩家痕迹被明确覆盖”。Godot 再负责把这个结果安全、渐进地变成实际世界。**
