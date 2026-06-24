# hs-blackbox-agent

Haskell-native 黑盒探测 agent。对一个 PB task 目录里的 `./probe` 反复试探 + 综合上游文档，输出该目标的 `belief.md`。

## 五个 LLM 调用阶段

1. **init** — 读目录里 docs（README/SPEC/man），机械执行 `ls -la` / `file ./probe` / `./probe --help`，调一次 Deepseek 把文档推断 + --help 实测落进 `oracle.yaml` 的 7+other 槽位，confidence 全 = 0
2. **决策** — 每轮：harness 把 oracle 摘要 + 本轮动态 + 参考文档 + 探针计数 + 去重历史 cmd + last_result + hints 塞进 prompt，Deepseek 出一个 action（probe / grep / other）
3. **整理** — 探索执行完，harness 把 action + 结果回灌，Deepseek 用 writeSlot 把新事实落槽（一发只升 1 槽，提升 confidence / 替换内容）
4. **Gate** — 每轮整理后，独立的 LLM 节点只判「信息够不够收敛」
5. **belief 合成** — 收敛后，harness 把 oracle.yaml 全文喂 LLM，自由发挥写 belief.md

收敛条件：wall-clock 20 min 到 **或** Gate 返回 `continue: false`。决策阶段不出 stop（收到会被 harness 忽略并 warn）。

## 持久层

每个 task 目录下生成一个 **`.hsbb/`** 隐藏目录，避免污染原任务环境：

```
<task_dir>/
├── README.md              ← 上游 docs (只读)
├── SPEC.md                ← 任务说明 (只读)
├── probe                  ← docker exec wrapper (只读)
└── .hsbb/                 ← agent 所有产出
    ├── oracle.yaml        ← 7+other 槽位的事实库, agent 反复读写
    ├── probes.jsonl       ← 每发 probe 一行, 全量 stdout/stderr
    ├── trace.jsonl        ← 每个 LLM 调用 / tool dispatch 的事件流
    └── belief.md          ← 收敛后合成
```

`oracle.yaml` 是「事实库」，harness 用 title+confidence+content 投影做 prompt 摘要；
`probes.jsonl` 是探针流水，append-only；
`trace.jsonl` 是审计 / 调试用的事件流（可回放每次 LLM 请求/响应/工具调用）。

## 子命令

```bash
cabal build
HSBB=$(find dist-newstyle -name hsbb -type f -perm +111 | head -1)

$HSBB init   <task-dir>   # 消化 docs + 机械 probe → 初始 oracle.yaml
$HSBB step   <task-dir>   # 跑一轮 (决策 + 探索 + 整理 + Gate) 就退出
$HSBB loop   <task-dir>   # 跑到 20 min wall-clock 或 Gate 收敛
$HSBB belief <task-dir>   # 合成 belief.md
$HSBB full   <task-dir>   # init + loop + belief 一气 (已有 probe 则跳过 init)
$HSBB step-snap <root-dir>  # 快照模式: root 下 step_N/ 子目录, 每次cp前一步→跑一步
```

`step` 自动从 `probes.jsonl` 的 `countDecisionProbes`（只算 round>0）续 round 号，支持半路发车（中断后再调 `step` 接着跑）。

`--prompts-dir=<path>` 可覆盖内置 system prompt（decision.txt / integration.txt / gate.txt / init.txt），任一文件不存在则回退内置默认。用于无重编译跑多变体实验。

环境变量：

- `DEEPSEEK_API_KEY` (必填) — 调用 deepseek.com chat completions

## 关键机制

- **docker exec 重写**：探测 task 的 `./probe` 若是 docker wrapper，harness 自动把 cmd 重写为 `docker exec -i <container> timeout 5 bash -c '<binary> <args>'`，host 侧再包 30s 兜底
- **confidence 衰减**（LLM 看不到）：`obtained = min(LLM值, 0.2)`，`delta = obtained * (1 - current)`，逐步收敛
- **一发只升一槽**：integration 阶段 harness 硬拦，第 2 个及以后的 writeSlot 不生效
- **反重复拦截**：decision 输出的 cmd 若与历史 verbatim 重复且 why 未声明「重复 probe_」，harness 拒绝并 retry 一次
- **inconclusive 标记**：LLM 可诚实标记「探了但没结果」，confidence 不动，>=2 后摘要标 `[INCONCLUSIVE ×N]`
- **hint_for_next_round**：integration 可把 actionable 信号传给下一发 decision，通过 oracle.yaml 跨进程持久
- **参考文档常驻**：从 probes.jsonl 自动挑 --help / --version 类 probe，每轮 decision prompt 都带
- **API 审计**：每次请求体 append 到 `/tmp/hsbb_bodies.jsonl`

## 反作弊约束

agent 的输入边界：

| 合法 | 禁用 |
|---|---|
| `./probe <args>` 输出 (stdout/stderr/exit) | `programbench/data/tasks/*/tests.json` (grader 私有) |
| 任务目录下的 docs (README/SPEC/man) | HF `ProgramBench-Tests` tarball |
| target 自带的 `--help` / `--version` / 错误信息 | `distill_out/*.jsonl` (派生自 tests.json) |
| 上游 repo @ pinned commit | 老 `haskell-tester/data/*` (反推 grader 的产物) |

判定原则：**「这条信息是关于程序行为, 还是关于 grader 怎么测它」**——前者合法, 后者污染。
