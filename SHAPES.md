# hs-blackbox-agent — 数据 shape 参考

实现时查「数据这一步长啥样」用。只描述 shape，不解释为什么。所有内容对照 src/ 实际代码。

## 持久层

| 文件 | 内容 | 格式 |
|---|---|---|
| <task>/.hsbb/oracle.yaml | 7 universal 槽 + other 自由槽 + root 级 hints | yaml |
| <task>/.hsbb/probes.jsonl | 每个 probe 一行，含全量 stdout/stderr | JSONL append-only |
| <task>/.hsbb/trace.jsonl | LLM 调用 / tool 派发 / 阶段 / 收敛事件流 | JSONL append-only |
| <task>/.hsbb/belief.md | 收敛后合成 | markdown |

oracle.yaml 的 evidence: [probe_007] 跨引 probes.jsonl 同 id 那行。所有产物都在 .hsbb/ 隐藏目录，不污染任务原始环境。

## Oracle 模块抽象

harness 和 LLM 都不直接 I/O，全部走 Oracle（src/Blackbox/Oracle.hs）：

```
Oracle
├─ 内部：loadYaml / saveYaml / appendJsonl / atomic write / IORef 内存镜像
├─ harness-facing
│  ├─ summary()            → 摘要投影（title + confidence + content 截断 1200 字符）
│  ├─ dynamicSection(round)→ 本轮动态（上轮升级 / 未触槽 / writeSlot 尝试次数）
│  ├─ appendProbe(p)       → probes.jsonl 追加
│  ├─ countProbes()        → 已发 probe 总数
│  ├─ countDecisionProbes()→ 只算 round>0 的 probe（init 机械 probe round=0 不计）
│  ├─ lastProbeRecord()    → 读最后一行（step 模式重建 last_result）
│  ├─ uniqueProbeCommands()→ 去重的历史 cmd 列表（防 decision 重复探）
│  ├─ referenceProbes()    → 常驻参考文档（--help / --version 类，最多 2 条）
│  ├─ setCurrentRound(n)   → 设置当前轮号（writeSlot 元数据用）
│  ├─ setLastIntegrationAttempts(n) → 整理阶段 writeSlot 尝试次数
│  ├─ resetNextRoundHints()  → integration 开始时清空 hint buffer
│  ├─ readNextRoundHints()   → decision 渲染 prompt 时读上一发留的 hint
│  └─ loadOracle()           → belief 合成取全文
└─ LLM-facing (tool 派发)
   ├─ writeSlot(id, ...)  → 写 / 更新槽位（other id 冲突自动 _2/_3 后缀顺延）
   ├─ readSlot(id)        → 读单槽全文（yaml 文本返回）
   └─ lookupProbe(id)     → 从 probes.jsonl 取全量 probe 记录
```

readSlot / lookupProbe 在主循环中不暴露给 decision / gate（harness 已经把它该看到的全投影进 prompt），但 integration 阶段可用 writeSlot。belief 阶段不暴露任何 tool。

## 五个 LLM 调用阶段

API 统一参数：model = deepseek-chat，temperature = 0.3，max_tokens = 2000，3 次重试。

| 阶段 | 触发 | 暴露 tool | maxRounds | 输入 | 输出 |
|---|---|---|---|---|---|
| ① init | hsbb init / full 启动 | writeSlot | 6 | docs + fs 上下文 (ls -la / file ./probe) + --help 实测 | writeSlot × N，confidence 全 = 0 |
| ② decision | 每轮非收敛时 | 无 | 2 | oracle 摘要 + 本轮动态 + 参考文档 + 探针计数 + 探索历史(含结果浓缩) + last_result + hints | action JSON: probe / grep / other（无 stop） |
| ② decision retry | 反重复拦截触发 | 无 | 2 | 原 msgs + harness feedback | action JSON |
| ③ integration | 每轮探索后 | writeSlot（最多 3 个生效） | 4 | oracle 摘要 + 上轮 action + last_result | writeSlot × 0..3 |
| ④ gate (默认) | 每轮整理后 | 无 | — | 7 槽均值 (harness 端计算) | continue/converge |
| ④ gate (LLM) | --prompts-dir 提供 gate.txt | 无 | 2 | oracle 摘要 + 探针计数 | {"continue": true/false, "why": "..."} |
| ⑤ belief | 收敛触发后一次 | 无 | 2 | oracle.yaml 全文 | belief.md markdown |

收敛触发：harness 端 wall-clock 20 min / Gate 判收敛（默认 harness 启发式 7 槽均值 >= 0.8，或 LLM 返回 continue: false）。decision 出 stop 会被 harness 忽略并 warn，不触发收敛。

## ① oracle.yaml schema

```yaml
# root 级字段
slots:                           # 7 universal 槽的 dict
  identity:
    title: "yj 5.1.0 (Go binary, std flag parser, 4-format converter)"
    confidence: 0.2              # 衰减后实际值（LLM 看不到衰减公式）
    content: |                   # 高密度事实 bullet list
      - exit 2 on --foo (unknown flag) ← probe_007
      - stdout: HTTP body / stderr: progress
    evidence: [probe_002, probe_005]   # 跨引 probes.jsonl
    notes: ""                    # 可选 caveat
    write_count: 1               # 该槽被 writeSlot 多少次（init 不计）
    last_round: 1                # 最后一次 writeSlot 的 round 号（init = -1）
    last_delta: 0.2              # 上次实际 confidence 增量（衰减后）
    last_proposed_conf: 0.7      # LLM 上次给的原始 confidence（衰减前）
    inconclusive_count: 0        # inconclusive=true 累加次数；≥2 后摘要标 [INCONCLUSIVE ×N]
    updated_at: 2026-06-23T11:27:49 UTC

  cli_flags:        { ... }
  io_channels:      { ... }
  exit_codes:       { ... }
  error_buckets:    { ... }
  impl_fingerprint: { ... }
  known_unknowns:   { ... }

other:                            # 自由槽数组
  - id: round_trip_identity       # LLM 自取 id；冲突自动 _2/_3 后缀
    index: 1                      # 可选排序号
    title: "y→j→y 保 bool 类型"
    confidence: 0.36              # 同样走衰减公式
    content: |
      Round-trip y→j→y on {a:true} yields {a:true}
    evidence: [probe_010, probe_011]
    notes: ""
    write_count: 2
    last_round: 3
    last_delta: 0.16
    last_proposed_conf: 0.9
    inconclusive_count: 0
    updated_at: 2026-06-17T10:30:00Z

next_round_hints: []             # root 级，跨 hsbb step 进程持久
                                 # integration 阶段 writeSlot 的 hint_for_next_round
                                 # 累加到这里，下一发 decision 读到后清空
```

7 universal 槽固定：identity / cli_flags / io_channels / exit_codes / error_buckets / impl_fingerprint / known_unknowns。

harness 注入的元数据字段（LLM 不感知，由 writeSlotRaw 自动写）：

| 字段 | 含义 |
|---|---|
| write_count | 该槽被有效 writeSlot 的次数（init 阶段 isInitPhase=true 时不递增） |
| last_round | 最后一次 writeSlot 的 round 号（init = -1） |
| last_delta | 上次实际 confidence 增量（衰减后，newConf - currentConf） |
| last_proposed_conf | LLM 上次给的原始 confidence 值（衰减前） |
| inconclusive_count | inconclusive=true 的累加次数 |
| updated_at | UTC 时间戳 |

## ② probes.jsonl schema

每行一个 JSON 对象（append-only）：

```json
{
  "id": "probe_001",
  "round": 1,
  "cmd": "./probe -h",
  "exit": 1,
  "stdout_bytes": 370,
  "stderr_bytes": 78,
  "stdout": "...",
  "stderr": "...",
  "duration_ms": 268
}
```

stdout / stderr 存全量，不截断。

init 阶段的机械 probe（round = 0）：

| id | cmd | round |
|---|---|---|
| probe_init_fs_ls | ls -la . | 0 |
| probe_init_help | ./probe --help | 0 |

decision 阶段的 probe（round >= 1）：id 格式 probe_NNN（3 位零填充）。

## ③ trace.jsonl event types

每行一个 JSON 对象，所有事件都有 ts + type，其余字段按 type 不同：

| type | 额外字段 | 产出位置 |
|---|---|---|
| phase_start | phase | init / loop / round_NNN_decision / round_NNN_integration / round_NNN_gate / belief |
| phase_end | phase | 同上 |
| meta | phase, docs_files, docs_total_chars | init 阶段开头 |
| probe_appended | round, probe_id, exit, stdout_bytes, stderr_bytes, init_probe(仅 init) | 每次 appendProbe 后 |
| llm_request | round, messages, tools, model, temperature, max_tokens | 每次 callOnce 前 |
| llm_response | round, content, tool_calls | 每次 callOnce 后 |
| tool_dispatch_start | id, name, args | 每次 tool 调用前 |
| tool_dispatch_result | id, name, result | 每次 tool 调用后 |
| action_chosen | round, action | decision 产出 action 后 |
| decision_duplicate_rejected | cmd, why, retry_with | 反重复拦截触发 |
| convergence | reason(wall_clock/gate_stop), elapsed_sec(仅 wall_clock) | 收敛触发 |
| warn | where, msg, ... | decision 出 stop 等异常 |
| belief_written | path, bytes | belief 写盘后 |
| error | where, msg | LLM 调用失败等 |

## ④ Confidence 衰减机制

LLM 看不到以下公式（src/Blackbox/Oracle.hs applyConfidenceDecay）：

```
obtained = min(LLM给的值, 0.2)
delta    = obtained * (1 - current)
new      = current + delta
```

即便 LLM 每次都给 1.0，单次上升也不超过 0.2 * (1 - current)，逐步收敛。

特殊情况：
- inconclusive: true 时 confidence 不动，只累加 inconclusive_count
- init 阶段（roundN < 0）：write_count 不递增，last_round 保持 -1
- inconclusive_count >= 2 后，oracle 摘要标 [INCONCLUSIVE ×N]，decision 阶段会避开

## ⑤ harness 摘要投影（Oracle.summary()）

decision / integration / gate prompt 通用。每个 universal 槽渲染：

```
- identity         [0.20]  entr 5.7 (Event Notify Test Runner...)
    - Name: entr (Event Notify Test Runner)
    - Version: 5.7
    ...
```

- confidence 标签：[0.XX] 或 [INCONCLUSIVE ×N]（当 inconclusive_count >= 2）
- 空槽显式 [EMPTY] (未填)
- content 也渲染（截断 1200 字符），缩进 4 格
- evidence / notes / updated_at 不进摘要

other 子项渲染：  - [1] round_trip_identity [0.90]  y→j→y 保 bool

摘要顶端带 confidence 语义声明。

## ⑥ 本轮动态（Oracle.dynamicSection(round)）

decision prompt 专用，紧跟摘要后。内容：

```
## 本轮动态
- 上轮升级: cli_flags  (你给 0.700, decay 后实际 +0.200 → 当前 0.200)
- 上轮 writeSlot 尝试: 1 次, 生效
- 未触槽: identity, io_channels, exit_codes, error_buckets, impl_fingerprint, known_unknowns
- 各槽累计 writeSlot 次数:
    identity:0  cli_flags:1  io_channels:0  exit_codes:0  error_buckets:0  impl_fingerprint:0  known_unknowns:0
```

- 上轮升级：last_round == currentRoundN - 1 且 > 0 的槽，显示 LLM 给的值 / decay delta / 当前值
- writeSlot 尝试：lastIntegrationAttempts，>1 时提示「后续被 harness 静默丢弃」
- 未触槽：write_count == 0 的 universal 槽
- 累计次数：每槽 write_count 横排

## ⑦ 参考文档常驻（referenceProbes()）

decision prompt 专用。从 probes.jsonl 自动挑选 --help / --version 类 probe 作为常驻参考：

- help 类优先级：--help > -h > -?
- version 类优先级：--version > -v > -V
- 有效性校验：内容 >= 50 字节 + 关键词匹配（usage: / options: / flags: / 缩进 flag 列表 等）
- 每类只挑 1 个胜出者，最多返回 2 条
- prompt 中每条截断 8192 字符

经验法则源自 30 道 PB 任务实测（见代码注释）：29/30 canonical 是 --help；通道分布 20 stdout / 9 stderr，必须 concat 两边再校验。

## ⑧ init 阶段 prompt

System 段（src/Blackbox/Init.hs initSystemPrompt）：

```
你是黑盒探测 agent 的 init 阶段。
通读任务文档（README/SPEC.md/man pages 等），把能推断的事实落到 oracle 槽里。

可用 tool：writeSlot
  - slot_id：identity / cli_flags / io_channels / exit_codes / error_buckets / impl_fingerprint / known_unknowns（universal）
  - 或自定义 id 写到 other

title is critical: must be one info-dense sentence with concrete name/version/counts/key flags/quirks.
置信度统一填 0（init 阶段所有内容都是未经 probe 验证的文档推断, 一律 0 = 不可置信）
```

User 段：

```
## 任务文档
<docs 全文, 每个 ≤ 8KB 截断>

## fs 上下文 (init 阶段看到的环境)
### $ ls -la .
<ls 输出>
### $ file ./probe
<file 输出>

## 实测自我介绍 (init 阶段已机械执行 --help)
### $ ./probe --help
exit: 1
stdout: ...
stderr: ...

## 你的任务
通读以上，推断能填的事实，发起 writeSlot tool calls。
```

输出：一批 writeSlot tool call（maxRounds = 6 轮 tool-call 循环）。

## ⑨ decision 阶段 prompt

User 段（src/Blackbox/Loop.hs decisionPhase）：

```
## oracle 摘要
<summary() 投影>

## 本轮动态
<dynamicSection() 投影>

## 参考文档 (常驻)
### probe_init_help
$ ./probe --help
<输出截断 8KB>

## 探针计数
本任务已发 probe 数: 4
历史参考: 同类案例平均 ~70 发, 范围 10-200。

## 已执行过的 probe (去重)
- ./probe --help
- ./probe -h
- ...

## 上轮回灌 (last_result)
cmd: ./probe -h
exit: 1
stdout (370 B total, ≤2KB sliced):
  ...
probe_id: probe_001 (lookupProbe for full)

## 上发 integration 给本发的 hint (actionable, 一次性)
- stderr 暗示 use -n 探 non-interactive 模式

## 你的任务
基于以上, 决定下一步 action, 直接输出 action JSON。
```

System 段：定义 action 协议（probe / grep / other 三选一，无 stop），why 字段 = 推理依据 + 目标槽。

输出（仅 content，无 tool call）：

```json
{
  "action": "probe",
  "cmd": "./probe -n echo test",
  "why": "假设: -n 是 non-interactive 模式, 应不等待键盘输入直接执行. 目标: cli_flags."
}
```

反重复拦截：若 cmd verbatim 已在历史列表中且 why 未声明「重复 probe_」，harness 拒绝并 retry 一次，喂 feedback 提示换角度。

## ⑩ integration 阶段 prompt

User 段（src/Blackbox/Loop.hs integrationPhase）：

```
## oracle 摘要
<summary() 投影>

## 上轮 action
{"action":"probe","cmd":"./probe -n echo test","why":"..."}

## 上轮回灌 (last_result)
<同 decision>

## 你的任务
看 action.why 中声明的「目标槽 + 预期」, 比对 last_result:
  - 符合假设 (验证型) → writeSlot 同槽位, 提升 confidence
  - 揭示新事实 → writeSlot 落槽
  - 反驳现有槽 (冲突型) → writeSlot 修正
  - 跟 why 声明完全无关 → 不发 tool call
```

硬限制：一发 probe 只升 1 个槽。harness 用 wrappedHandler 拦截，第 2 个及以后的 writeSlot 返回 rejected 消息。

writeSlot 额外字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| inconclusive | bool (可选) | true 时 confidence 不动，inconclusive_count 累加 |
| hint_for_next_round | string (可选) | ≤120 字 actionable 一句话，传给下一发 decision |
| index | int (可选) | 仅 other 条目排序用 |

输出：零到一个 writeSlot tool call（maxRounds = 4 轮 tool-call 循环，但只有第 1 个生效）。

## ⑪ gate 阶段 prompt

User 段（src/Blackbox/Loop.hs gatePhase）：

```
## oracle 摘要
<summary() 投影>

## 探针计数
本任务已发 probe 数: 4
历史参考: 同类案例平均 ~70 发, 范围 10-200。

## 你的任务
判断信息是否足够收敛。直接输出 JSON:
{"continue": true / false, "why": "..."}
```

System 段（gateSystemPrompt）：Gate 唯一职责是判断收敛，不参与「探什么」。判断规则基于 7 槽均值：< 0.6 强制 continue，>= 0.8 可收敛，0.6-0.8 酌情。

输出：{"continue": true, "why": "7槽均值0.03，远低于0.6，需大量probe验证"}

解析失败默认 True（继续），避免无故收敛。

## ⑫ belief 阶段 prompt

User 段（src/Blackbox/Belief.hs synthesize）：

```
## oracle.yaml 全文
```yaml
<dump oracle.yaml>
```

请写 belief.md（直接输出 markdown 正文, 无围栏）。
```

System 段：黑盒目标分析师，写给消费者（人或上游 agent）看。格式自由。

输出：belief.md 文本（纯 markdown），写入 <task>/.hsbb/belief.md。

## last_result 生命周期

```
探索完成
  ↓ appendProbe → probes.jsonl 落地全量
  ↓ last_result = { cmd, exit, stdout 切片, stderr 切片, probe_id } 存内存
  ↓ 喂入 integration prompt
  ↓ integration 完成
  ↓ 进 gate prompt 不带 last_result（Gate 只看 oracle + 计数）
  ↓ Gate 决定 continue/stop
  ↓ 若 continue → 进下一轮 decision prompt（仍带 last_result）
  ↓ 下一轮探索后 last_result 被新值覆盖
```

step 模式（hsbb step）是 one-shot 进程：从 probes.jsonl 最后一行 reconstructLastResult 重建 last_result，跑一轮就退出。hint 通过 oracle.yaml next_round_hints 字段跨进程持久。

## 切片规则

| 字段 | 切片 | 数据是否丢 |
|---|---|---|
| last_result.stdout | 2 KB（maxStdoutSlice） | 否（全量在 probes.jsonl） |
| last_result.stderr | 1 KB（maxStderrSlice） | 否 |
| probes.jsonl.{stdout, stderr} | 不切 | 不丢 |
| oracle 摘要 slot content | 1200 字符 | 否（全量在 oracle.yaml） |
| 参考文档每条 | 8192 字符 | 否（全量在 probes.jsonl） |
| init docs 每文件 | 8000 字符 | 是（超长文档截断） |
| init probe stdout/stderr | 8000 / 4000 字符 | 否（全量在 probes.jsonl） |
| decision / integration / gate prompt 中的 docs | init 时已读, 主循环不再带 | — |

## 审计日志

除 .hsbb/ 内的 trace.jsonl 外，每次 Deepseek API 请求体额外 append 到 /tmp/hsbb_bodies.jsonl（src/Blackbox/Deepseek.hs postChat），一行一个 JSON，含完整 messages + tools + model + temperature + max_tokens。用于事后审计 LLM 请求内容。
