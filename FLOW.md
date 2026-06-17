# hs-blackbox-agent — 流程图（v2）

```mermaid
flowchart TD
    Start([hsbb 任务目录]) --> Init[init 阶段:<br/>读 docs → 调 Deepseek 消化<br/>writeSlot 落入 oracle 初始态]
    Init --> Conv

    Conv{是否收敛?<br/>wall-clock > 20 min<br/>或上轮 LLM stop}
    Conv -- 是 --> Synth[belief 合成:<br/>oracle.yaml 全文 + 必要 probes 喂 LLM<br/>纯自由发挥写 belief.md]
    Synth --> Done([退出:<br/>oracle.yaml + belief.md])
    Conv -- 否 --> Decide

    Decide[决策 prompt:<br/>系统 + oracle 摘要 + last_result] --> CallD[调 Deepseek #1]
    CallD --> Action{action}
    Action -- stop --> Conv
    Action -- probe / grep / other --> Exec[执行<br/>appendProbe → probes.jsonl 全量]
    Exec --> Integ[整理 prompt:<br/>系统 + oracle 摘要 + last_result + 上轮 action]
    Integ --> CallI[调 Deepseek #2]
    CallI --> Write[writeSlot × 0..N<br/>→ oracle.yaml]
    Write --> Conv
```

## 关键设计点

- **4 个 LLM 调用阶段**：init 消化 / 每轮决策 / 每轮整理 / 收敛后 belief 合成
- **决策 / 整理拆开**：决策 prompt 出 action（只此一项），整理 prompt 出 writeSlot（可零可多）。两件事不互挤
- **docs 不进主循环 prompt**：init 一次消化进 oracle，主循环只走 oracle 摘要
- **唯一闸门 Conv**：harness 20 min wall-clock + LLM stop 两个触发器统一从 Conv 出去
- **belief.md 不进 ReAct loop**：收敛后单次合成，纯 LLM 发挥（不结构化提示）
- **last_result 极短命**：只跨"探索 → 整理 prompt"那一步，被整理后即弃；后续要全量走 `lookupProbe`
- **错误容错**：Deepseek 调用 3 次重试，仍败意外退出

## 持久层（详见 SHAPES.md）

| 文件 | 内容 |
|---|---|
| `oracle.yaml` | 7 universal 槽 + other 自由槽 |
| `probes.jsonl` | 每个 probe 一行，含全量 stdout/stderr |
