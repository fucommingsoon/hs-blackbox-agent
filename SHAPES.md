# hs-blackbox-agent — 数据 shape 参考（v3）

实现时查"数据这一步长啥样"用。只描述 shape，不解释为什么。

## 持久层

| 文件 | 内容 | 格式 |
|---|---|---|
| `<task>/.hsbb/oracle.yaml` | 7 universal 槽 + other 自由槽 | yaml |
| `<task>/.hsbb/probes.jsonl` | 每个 probe 一行，含全量 stdout/stderr | JSONL append-only |
| `<task>/.hsbb/trace.jsonl` | LLM 调用 / tool 派发 / 阶段 / 收敛事件流 | JSONL append-only |
| `<task>/.hsbb/belief.md` | 收敛后合成 | markdown |

两文件通过 `probe_id` 跨引（`evidence: [probe_007]` → `probes.jsonl` 同 id 那行）。
所有产物都在 `.hsbb/` 隐藏目录，不污染任务原始环境。

## Oracle 模块抽象

harness 和 LLM 都不直接 I/O，全部走 `Oracle`：

```
Oracle
├─ 内部：loadYaml / saveYaml / appendJsonl / 校验 / atomic write
├─ harness-facing
│  ├─ summary()       → 摘要投影
│  ├─ appendProbe(p)  → probes.jsonl 追加
│  └─ countProbes()   → 已发 probe 计数
└─ LLM-facing (tool 派发)
   └─ writeSlot(id, ...) → 写 / 更新槽位（other id 冲突自动后缀顺延）
```

`readSlot` / `lookupProbe` 不暴露给 LLM——harness 已经把它该看到的全投影进 prompt。

## 五个 LLM 调用阶段

| 阶段 | 触发 | 输入 | 输出 | LLM 可用 tool |
|---|---|---|---|---|
| ① init 消化 | hsbb 启动后一次 | docs | writeSlot 一批，confidence 全 = 0 | writeSlot |
| ② 决策 | 每轮非收敛时 | oracle 摘要 + last_result + 已发 probe 数 | 单个 action: `probe` / `grep` / `other`（**无 stop**） | 无 |
| ③ 整理 | 每轮探索后 | oracle 摘要 + 上轮 action + last_result | writeSlot × 0..N | writeSlot |
| ④ Gate | 每轮整理后 | oracle 摘要 + 已发 probe 数 + 历史均值 70 / 范围 10-200 | `{"continue": true / false}` | 无 |
| ⑤ belief 合成 | 收敛触发后一次 | oracle.yaml 全文 | belief.md 文本 | 无 |

收敛触发：harness 端 wall-clock 20 min / LLM 端 Gate 返回 `false`。

---

## ① oracle.yaml schema

```yaml
slots:
  identity:
    title: "yj 5.1.0 (Go binary)"
    confidence: 0.95                    # 0 = 未经 probe 验证, > 0 = probe 实测后逐步升级
    content: |
      yj version 5.1.0
      Implementation: Go
    evidence: [probe_002, probe_005]    # 跨引 probes.jsonl
    updated_at: 2026-06-17T10:30:00Z
    notes: ""

  cli_flags:        { ... }
  io_channels:      { ... }
  exit_codes:       { ... }
  error_buckets:    { ... }
  impl_fingerprint: { ... }
  known_unknowns:   { ... }

other:
  - id: round_trip_identity
    index: 1
    title: "y→j→y 保 bool 类型"
    confidence: 0.9
    content: |
      Round-trip y→j→y on {a:true} yields {a:true}
    evidence: [probe_010, probe_011]
    updated_at: ...
```

7 universal 槽固定：`identity / cli_flags / io_channels / exit_codes / error_buckets / impl_fingerprint / known_unknowns`。
`other` 自由槽，id 由 LLM 自取，可选 `index`。

## ② probes.jsonl schema

每行一个 JSON 对象（append-only）：

```json
{
  "id": "probe_001",
  "round": 1,
  "cmd": "./probe --help",
  "exit": 1,
  "stdout_bytes": 0,
  "stderr_bytes": 955,
  "stdout": "",
  "stderr": "Usage of /workspace/executable:\n  -abspath\n    ...",
  "duration_ms": 423,
  "run_at": "2026-06-17T10:29:50Z"
}
```

`stdout` / `stderr` 存全量，不截断。

---

## ③ harness 摘要投影（`Oracle.summary()`）

| 字段 | 用途 |
|---|---|
| `slots.*.title`、`confidence` | 已填槽位摘要行；未填槽位显式 `[EMPTY]` |
| `other.*.title`、`confidence`、`index` | other 子项摘要行 |

摘要顶端带一行 confidence 语义声明：
```
(confidence: 0 = 未经 probe 验证的文档推断, 不可置信; > 0 = probe 实测后逐步升级)
```

未填槽显示样例：
```
- error_buckets    [EMPTY]  (未填)
```

`content` / `evidence` / `notes` / probes 内容均不进摘要。

---

## ④ 阶段 ① — init 消化 prompt

System 段：

```
你是 init 阶段, 通读文档把能推断的事实落进 oracle 槽里。
- slot_id: 7 universal 之一 或 自定义 id 写到 other
- **confidence 统一填 0**（init 内容都是未经 probe 验证的文档推断, 一律 0 = 不可置信）
- title 字段是关键：一句话信息密度高，含具体名字/版本/数量/关键 flag/异常
- evidence 字段写 'source: README' 之类（暂无 probe id）
```

User 段：

```
## 任务文档
<docs 全文, 每个 ≤ 8KB 截断>

## 你的任务
通读以上，发起 writeSlot tool calls。完成后简短总结。
```

**输出**：一批 writeSlot tool call。

## ⑤ 阶段 ② — 决策 prompt

User 段：

```
## oracle 摘要
(confidence: 0 = 未经 probe 验证..., > 0 = probe 实测后逐步升级)
- identity         [0.85]  yj 5.1.0 (Go binary)
- cli_flags        [0.80]  20 flags, 4×4 转换矩阵
- io_channels      [0.90]  stdin→stdout, usage→stderr
- exit_codes       [EMPTY]  (未填)
- error_buckets    [0.0]   ...
- impl_fingerprint [0.95]  ...
- other:
  - [1] round_trip_identity [0.90]  y→j→y 保 bool

## 探针计数
本任务已发 probe 数: 4
历史参考: 同类案例平均 ~70 发, 范围 10-200, 具体探多少自行判断。

## 上轮回灌 (last_result)
cmd: ./probe -x y -e t
exit: 0
stdout (24 B):
  a = 1

## 你的任务
决定下一步 action, 直接输出 action JSON。
```

System 段：定义 action 协议（`probe` / `grep` / `other` 三选一，**无 stop**），强制以 `./probe` 开头。

**输出**（仅 content，无 tool call）：

```json
{
  "action": "probe",
  "cmd": "./probe -x y -e t",
  "why": "试 toml 输出"
}
```

## ⑥ 阶段 ③ — 整理 prompt

User 段：

```
## oracle 摘要
<同决策>

## 上轮 action
{"action":"probe","cmd":"./probe -x y -e t","why":"试 toml 输出"}

## 上轮回灌 (last_result)
<同决策>

## 你的任务
若 last_result 揭示新事实 → writeSlot 落槽。
若无新意 → 不发 writeSlot, 简短总结。
```

System 段：定义 title 要求 + confidence 语义 + writeSlot 用法。

**输出**：零到多个 writeSlot tool call。

```json
{"tool": "writeSlot", "args": {
  "slot_id": "exit_codes",
  "title": "exit 0/1/2 三档已识别 (probe_007)",
  "content": "0 = 正常, 1 = 转换错误, 2 = flag 错误",
  "confidence": 0.85,
  "evidence": ["probe_003", "probe_004", "probe_007"]
}}
```

## ⑦ 阶段 ④ — Gate prompt

User 段：

```
## oracle 摘要
<同决策>

## 探针计数
本任务已发 probe 数: 4
历史参考: 同类案例平均 ~70 发, 范围 10-200

## 你的任务
判断信息是否足够收敛。
- 继续探: 输出 {"continue": true, "why": "..."}
- 收敛: 输出 {"continue": false, "why": "..."}
```

System 段：定义 Gate 角色——只做收敛判断，不参与"探什么"决策。

**输出**：

```json
{"continue": true, "why": "exit_codes 仍 [EMPTY], error_buckets 0.3 低置信, 应继续验"}
```

或：

```json
{"continue": false, "why": "已发 80 发, 关键槽 ≥ 0.8, 边际收益低"}
```

## ⑧ 阶段 ⑤ — belief 合成 prompt

User 段：

```
## oracle.yaml 全文
```yaml
<dump oracle.yaml>
```

请写 belief.md（直接输出 markdown 正文）。
```

System 段：自由发挥，写给消费者（人或上游 agent）看。

**输出**：belief.md 文本（纯 markdown）。

---

## last_result 生命周期

```
探索完成
  ↓ appendProbe → probes.jsonl 落地全量
  ↓ last_result = { cmd, exit, stdout 切片, stderr 切片 } 存内存
  ↓ 喂入 整理 prompt
  ↓ 整理完成
  ↓ 进 Gate prompt 不带 last_result（Gate 只看 oracle + 计数）
  ↓ Gate 决定 yes/no
  ↓ 若 yes → 进下一轮 决策 prompt（仍带 last_result）
  ↓ 再下一轮 探索后 last_result 被新值覆盖
```

后续轮次需要全量 → 直接查 `probes.jsonl`（不暴露为 LLM tool）。

## 切片规则

| 字段 | 切片 | 数据是否丢 |
|---|---|---|
| `last_result.stdout` | 2 KB（preset） | 否（全量在 probes.jsonl） |
| `last_result.stderr` | 1 KB（preset） | 否 |
| `probes.jsonl.{stdout, stderr}` | 不切 | 不丢 |
| 决策 / 整理 / Gate prompt 中的 docs | init 时已读, 主循环不再带 | — |
