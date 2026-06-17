# hs-blackbox-agent

Haskell-native 黑盒探测 agent。对一个 PB task 目录里的 `./probe` 反复试探 + 综合上游文档，输出该目标的 `belief.md`。

## 4 阶段

1. **init** — 读目录里 docs（README/SPEC/man），调一次 Deepseek 把文档里能推断的事实落进 `oracle.yaml` 的 7+other 槽位
2. **决策** — 每轮：harness 把 oracle.yaml 摘要（title + confidence）+ 上轮回灌塞进 prompt，Deepseek 出一个 action（probe / grep / other / stop）
3. **整理** — 探索执行完，harness 把 action + 结果回灌，Deepseek 用 writeSlot 把新事实落槽（提升 confidence / 替换内容）
4. **belief 合成** — 收敛后，harness 把 oracle.yaml 全文喂 LLM，让它自由发挥写 belief.md

收敛条件：wall-clock 20 min 到 或 LLM 主动 stop。

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

`oracle.yaml` 是「事实库」, harness 用 title+confidence 投影做 prompt 摘要；
`probes.jsonl` 是探针流水, append-only；
`trace.jsonl` 是审计 / 调试用的事件流（可回放每次 LLM 请求/响应/工具调用）。

## 子命令

```bash
cabal build
HSBB=$(find dist-newstyle -name hsbb -type f -perm +111 | head -1)

$HSBB init   <task-dir>   # 消化 docs → 初始 oracle.yaml
$HSBB step   <task-dir>   # 跑一轮 (决策 + 探索 + 整理) 就退出
$HSBB loop   <task-dir>   # 跑到 20 min wall-clock 或 LLM stop
$HSBB belief <task-dir>   # 合成 belief.md
$HSBB full   <task-dir>   # init + loop + belief 一气
```

`step` 自动从 `probes.jsonl` 续 round 号, 支持半路发车 (中断后再调 `step` 接着跑)。

环境变量：

- `DEEPSEEK_API_KEY` (必填) — 调用 deepseek.com chat completions

## 反作弊约束

agent 的输入边界：

| 合法 | 禁用 |
|---|---|
| `./probe <args>` 输出 (stdout/stderr/exit) | `programbench/data/tasks/*/tests.json` (grader 私有) |
| 任务目录下的 docs (README/SPEC/man) | HF `ProgramBench-Tests` tarball |
| target 自带的 `--help` / `--version` / 错误信息 | `distill_out/*.jsonl` (派生自 tests.json) |
| 上游 repo @ pinned commit | 老 `haskell-tester/data/*` (反推 grader 的产物) |

判定原则：**「这条信息是关于程序行为, 还是关于 grader 怎么测它」**——前者合法, 后者污染。
