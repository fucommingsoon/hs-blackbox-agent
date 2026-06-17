# hs-blackbox-agent — 数据 shape 参考（v2）

实现时查"数据这一步长啥样"用。只描述 shape，不解释为什么。

## 持久层

| 文件 | 内容 | 格式 |
|---|---|---|
| `oracle.yaml` | 7 universal 槽 + other 自由槽 | yaml |
| `probes.jsonl` | 每个 probe 一行，含全量 stdout/stderr | JSONL append-only |

两文件通过 `probe_id` 跨引（`evidence: [probe_007]` → `probes.jsonl` 同 id 那行）。

## Oracle 模块抽象

harness 和 LLM 都不直接 I/O，全部走 `Oracle`：

```
Oracle
├─ 内部：loadYaml / saveYaml / appendJsonl / 校验 / atomic write
├─ harness-facing
│  ├─ summary()       → 摘要投影
│  └─ appendProbe(p)  → probes.jsonl 追加
└─ LLM-facing (tool 派发)
   ├─ readSlot(id)         → 完整 SlotRecord
   ├─ writeSlot(id, ...)   → 写 / 更新槽位（other id 冲突自动后缀顺延）
   └─ lookupProbe(id)      → 拉 probe 全量记录
```

## 四个 LLM 调用阶段

| 阶段 | 触发 | 输入 | 输出 |
|---|---|---|---|
| ① init 消化 | hsbb 启动后一次 | docs（README/SPEC.md/man）| 一批 writeSlot 落入 oracle |
| ② 决策 | 每轮非收敛时 | oracle 摘要 + last_result | 单个 action |
| ③ 整理 | 每轮探索后 | oracle 摘要 + last_result + 上轮 action | 零到多个 writeSlot |
| ④ belief 合成 | 收敛触发后一次 | oracle.yaml 全文 + 必要 probes | belief.md 文本 |

---

## ① oracle.yaml schema

```yaml
slots:
  identity:
    title: "yj 5.1.0 (Go binary)"      # 短描述, 力争一行
    confidence: 0.95                    # 0.0-1.0
    content: |                          # 详细事实, 多行
      yj version 5.1.0
      Implementation: Go (推断自 `flag` 错误风格)
    evidence: [probe_002, probe_005]    # 跨引 probes.jsonl
    updated_at: 2026-06-17T10:30:00Z
    notes: ""                           # 可选

  cli_flags:        { ... }
  io_channels:      { ... }
  exit_codes:       { ... }
  error_buckets:    { ... }
  impl_fingerprint: { ... }
  known_unknowns:   { ... }

other:                                  # 自由槽数组
  - id: round_trip_identity
    index: 1                            # 可选, LLM 自取
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

读取范围：

| 字段 | 用途 |
|---|---|
| `slots.*.title`、`confidence`（已填） | 摘要行 |
| `other.*.title`、`confidence`、`index` | other 子项行 |

不读 `content` / `evidence` / `notes` / `probes` 内容。空槽不出现在摘要里。

---

## ④ 阶段 ① — init 消化 prompt

```
## 任务文档
<README 全文>

<SPEC.md 全文>

<man pages ...>

## 你的任务
通读以上文档，把能推断的事实落到 oracle 槽里。
- 槽位 id：identity / cli_flags / io_channels / exit_codes / error_buckets / impl_fingerprint / known_unknowns
- 推断置信度填 0.3-0.7（未验证，仅来自文档）
- 不确定的角度放 `known_unknowns`
- 多余的发现放 `other`
- evidence 字段写 "source: README" / "source: SPEC.md" 之类（暂无 probe id）

回复以 writeSlot tool call 序列形式给出。
```

**输出**：一批 writeSlot tool call，落入 oracle 初始态。

## ⑤ 阶段 ② — 决策 prompt

```
## oracle 摘要
- identity         [0.65]  yj 5.1.0 (Go, 推断自 README)
- cli_flags        [0.60]  转换矩阵, 16 子模式 (推断)
- io_channels      [0.50]  stdin→stdout (推断)
- known_unknowns   [0.70]  exit code 各档语义未知
- other:
  - [1] yaml_v2_lib_hint [0.50]  README 提到 yaml.v2 bug
(未列出 = 未填; 详情读 readSlot)

## 上轮回灌 (last_result)
cmd: ./probe -x y -e t
exit: 0
stdout (24 B):
  a = 1

## 你的任务
基于以上, 决定下一步 action。
```

**输出**：单个 action JSON。

```json
{
  "action": "probe",
  "cmd": "./probe -x y -e t",
  "why": "试 toml 输出"
}
```

action 类型：`probe` / `grep` / `other` / `stop`。
**没有 verbose 字段**——切片永远是 preset，LLM 想看全量时主动发 `lookupProbe(probe_id)`。

## ⑥ 阶段 ③ — 整理 prompt

```
## oracle 摘要
<同上>

## 上轮 action
{"action":"probe","cmd":"./probe -x y -e t","why":"试 toml 输出"}

## 上轮回灌 (last_result)
cmd: ./probe -x y -e t
exit: 0
stdout (24 B):
  a = 1

## 你的任务
若 last_result 揭示新事实或修正既有槽位 → 发 writeSlot tool call。
若没新东西 → 不发 writeSlot, 直接结束本轮。
```

**输出**：零到多个 writeSlot tool call。

```json
{"tool": "writeSlot", "args": {
  "slot_id": "exit_codes",
  "title": "exit 0 = 转换成功",
  "content": "yaml→toml 输入合法时, exit 0, stdout 含 toml 文本",
  "confidence": 0.85,
  "evidence": ["probe_013"]
}}
```

## ⑦ 阶段 ④ — belief 合成 prompt

```
## oracle.yaml 全文
<dump oracle.yaml>

## 你的任务
为这个 target 写一份 belief.md。
自由格式, 给消费者（人或上游 agent）看的, 写你认为重要的所有结论。
```

**输出**：belief.md 文本（纯 markdown，无结构约束）。

---

## last_result 生命周期

```
探索完成
  ↓ appendProbe → probes.jsonl 落地全量
  ↓ last_result = { cmd, exit, stdout 切片, stderr 切片 }  存内存
  ↓ 喂入"整理 prompt"
  ↓ 整理完成 (writeSlot 可能落槽)
  ↓ 进下一轮决策 prompt 也带着 last_result (供决策参考)
  ↓ 再下一轮 (再次探索后) last_result 被新值覆盖
```

后续轮次需要全量 → `lookupProbe(id)`。

## 切片规则

| 字段 | 切片 | 数据是否丢 |
|---|---|---|
| `last_result.stdout` | 2 KB（preset） | 否（全量在 jsonl） |
| `last_result.stderr` | 1 KB（preset） | 否 |
| `probes.jsonl.{stdout, stderr}` | 不切 | 不丢 |

LLM 想看全量 → `lookupProbe(probe_id)` 拉。
