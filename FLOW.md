# hs-blackbox-agent — 流程图

```mermaid
flowchart TD
    Start([hsbb 任务目录]) --> Init
    Init[init 阶段<br>读 docs + 机械执行 ls -la / file ./probe / --help<br>调一次 Deepseek writeSlot 落初始 oracle<br>所有 confidence = 0]
    Init --> Conv

    Conv{wall-clock 超 20 min}
    Conv -- 是 --> Synth
    Conv -- 否 --> Decision

    Decision[决策 LLM 调用<br>oracle 摘要 + 本轮动态 + 参考文档<br>+ 探针计数 + 去重历史 cmd + last_result + hints<br>只选 probe / grep / other, 不出 stop]
    Decision --> DupCheck{cmd 与历史<br>verbatim 重复?}
    DupCheck -- 是, why 未声明重复 --> Retry[retry 一次<br>喂 feedback 提示换角度]
    Retry --> Exec
    DupCheck -- 否 --> Exec

    Exec[执行 action<br>docker exec 重写 (若 probe 是 wrapper)<br>容器内 timeout 5s + host 30s 兜底<br>追加 probes.jsonl 全量]
    Exec --> Integration[整理 LLM 调用<br>oracle 摘要 + 上轮 action + last_result<br>writeSlot 0 到 1 个 (硬限制: 一发只升一槽)<br>更新 oracle.yaml]
    Integration --> Gate{Gate LLM 调用<br>oracle 摘要 + 探针计数<br>只判 信息够不够收敛}

    Gate -- 不够 --> Conv
    Gate -- 够 --> Synth[belief 合成<br>oracle.yaml 全文 调 Deepseek<br>自由发挥写 belief.md]
    Synth --> Done([退出<br>oracle.yaml / probes.jsonl / trace.jsonl / belief.md])
```

## 五个 LLM 调用阶段

1. **init** — 读 docs + 机械执行 3 个 fs 上下文 probe（`ls -la` / `file ./probe` / `./probe --help`），调一次 Deepseek 把文档推断 + --help 实测落进 `oracle.yaml` 的 7+other 槽位，confidence 全 = 0
2. **决策** — 每轮：harness 把 oracle 摘要 + 本轮动态 + 参考文档 + 探针计数 + 去重历史 cmd + last_result + hints 塞进 prompt，Deepseek 出一个 action（probe / grep / other，无 stop）
3. **整理** — 探索执行完，harness 把 action + 结果回灌，Deepseek 用 writeSlot 把新事实落槽（硬限制一发只升 1 槽，提升 confidence / 替换内容）
4. **Gate** — 每轮整理后，独立的 LLM 节点只判「信息够不够收敛」，输出 `{"continue": true/false}`
5. **belief 合成** — 收敛后，harness 把 oracle.yaml 全文喂 LLM，让它自由发挥写 belief.md

收敛条件：wall-clock 20 min 到 **或** Gate 返回 `continue: false`。decision 出 `stop` 会被 harness 忽略并 warn，不触发收敛。

## 关键设计点

- **决策与收敛判断拆开两个 LLM 节点**：决策只想「探什么」，Gate 只想「够不够」，互不干扰
- **决策不出 stop**：能到决策这一步必定继续探，action 集合塌成 probe / grep / other 三选
- **Gate 节点专吃 stat 信号**：probe 计数 + oracle 摘要是 Gate 的核心输入，决策不被这类元数据干扰
- **docs 不进主循环 prompt**：init 一次消化进 oracle，主循环只走 oracle 摘要
- **init 写入 confidence 一律 0**：文档推断不可置信，逼 probe 实测后再升级
- **init 机械执行 3 个 probe**：`ls -la .` / `file ./probe` / `./probe --help`，结果连同文档一起喂 LLM，让 init 阶段就有实测信号
- **oracle 摘要里空槽显式 `[EMPTY]`**，避免「看不到 = 已覆盖」误判
- **content 进摘要**：slot content 截断 1200 字符也渲染给 decision LLM，不只看 title
- **本轮动态段**：上轮升级了哪些槽（含 LLM 给的值 / decay delta / 当前值）、writeSlot 尝试次数、未触槽、各槽累计次数
- **参考文档常驻**：从 probes.jsonl 自动挑 --help / --version 类 probe，每轮 decision prompt 都带，最多 2 条各 8KB
- **反重复拦截**：decision 输出的 cmd 若与历史 verbatim 重复且 why 未声明「重复 probe_」，harness 拒绝并 retry 一次喂 feedback
- **docker exec 重写**：探测 task 的 `./probe` 若是 docker wrapper，harness 自动把 cmd 重写为 `docker exec -i <container> timeout 5 bash -c '<binary> <args>'`，host 侧再包 30s `System.Timeout` 兜底
- **一发只升一槽**：integration 阶段 harness 用 wrappedHandler 硬拦，第 2 个及以后的 writeSlot 返回 rejected，不生效
- **confidence 衰减**（LLM 看不到）：`obtained = min(LLM值, 0.2)`，`delta = obtained * (1 - current)`，逐步收敛
- **inconclusive 标记**：LLM 可诚实标记「探了但没结果」，confidence 不动，inconclusive_count 累加，>=2 后摘要标 `[INCONCLUSIVE ×N]`，decision 避开
- **hint_for_next_round**：integration 阶段可把「只对下一发 cmd 有意义」的信号传给下一发 decision，通过 oracle.yaml `next_round_hints` 字段跨 hsbb step 进程持久
- **belief.md 不进 ReAct loop**：收敛后单次合成，纯 LLM 发挥
- **last_result 极短命**：跨「探索 → 整理 prompt」一步，被整理后即弃；后续要全量走 `probes.jsonl` 直接查
- **错误容错**：Deepseek 调用 3 次重试，仍败意外退出
- **API 审计**：每次请求体 append 到 `/tmp/hsbb_bodies.jsonl`

## 运行模式

| 子命令 | 行为 |
|---|---|
| `hsbb init <task>` | 只跑 init 阶段 |
| `hsbb step <task>` | 跑一轮（决策 + 探索 + 整理 + Gate）就退出，支持半路发车 |
| `hsbb loop <task>` | 跑到 20 min wall-clock 或 Gate 收敛 |
| `hsbb belief <task>` | 只跑 belief 合成 |
| `hsbb full <task>` | init + loop + belief 一气；已有 probe 则跳过 init |
| `hsbb step-snap <root>` | 快照模式：root 下 step_N/ 子目录，每次 cp 前一步 → 跑一步，可逐步观测 |

`step` 自动从 `probes.jsonl` 的 `countDecisionProbes`（只算 round>0）续 round 号，支持中断后再调 `step` 接着跑。

`--prompts-dir=<path>` 可覆盖内置 system prompt（decision.txt / integration.txt / gate.txt / init.txt），任一文件不存在则回退内置默认。
