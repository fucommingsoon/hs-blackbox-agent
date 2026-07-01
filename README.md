# hs-blackbox-agent

Haskell DTC for ProgramBench-style black-box targets.

DTC 是这个项目的主线：用 Haskell 承载可复用测试流程，逐步融合上游 regression、PB grader、以及后续更多项目特有 runner。DeepSeek/LLM 只在系统层消费 `system-prepare` 生成的机械读取包，用于黑盒类型决策、binding 生成、结果评估、oracle/report 提案；它不参与 runtime hot path，也不恢复旧逐轮 probe/confidence loop。

## 快速接手

新窗口 Codex / 开发者建议按这个顺序读：

1. `STATUS.md`: 当前代码状态、已删逻辑、下一步优先级。
2. `docs/pb/README.md`: PB 200+ / 外部 800 融合目标和同容器执行方案。
3. `docs/pb/tasks.md`: 当前本地 ProgramBench 201 个 task 清单。
4. `AGENTS.md`: 本地构建、运行和开发约束。
5. `FLOW.md`: DTC 构建流程和 Agent 执行流程。
6. `TODO.md`: 当前待办。

## 输入边界

DTC seed corpus 只放两类材料：

| 输入 | 用途 |
|---|---|
| 上游源码 | 判断程序公开能力、参数面、实现约束 |
| 测试流程 | 上游自带测试和 PB grader，用来抽取真实行为面 |

当前 seed 在 `corpus/probe-plan-seeds/`，每个项目只保留 `source/` 和 `grader/`。`pb-metadata`、PB task README/SPEC、旧 distill 产物都不作为 DTC seed。

融合新 PB 项目前，必须先拿到 upstream source 和 PB grader/eval tests；grader
必要时从 task image/container 中抽取。`--help` 首探和 binding 生成只能在材料
齐备或缺口已明确记录后进行。

PB 200+ 任务和后续外部约 800 个项目走同一套机制：通过 archetype
requirements + binding-driven execution 逐步融合，不为每个项目新增一条 CLI
命令。当前本地 ProgramBench metadata 中有 201 个 task，完整清单见
`docs/pb/tasks.md`；具体执行 runbook 见 `docs/pb/README.md`。

## Haskell DTC 流程

流程分两层，详见 `FLOW.md`：

- **构建流程**：从 source/upstream tests/grader 抽取 behavior surfaces，沉淀成 versioned Haskell DTC plan。
- **Agent 执行流程**：拿 DTC plan 和 app binary，执行 fixture/run/trigger/verify，产出 per-step verdict 和 gaps。

## 子命令

```bash
cabal build
HSBB=$(find dist-newstyle -name hsbb -type f -perm +111 | head -1)

$HSBB dtc plan entr
$HSBB dtc plan bat
$HSBB dtc coverage entr
$HSBB dtc requirements WatcherCli
$HSBB dtc requirements HttpClientCli
$HSBB dtc requirements StructuredSubcommandCli
$HSBB dtc validate-binding --binding=<file>
$HSBB dtc plan-binding --binding=<file>
$HSBB dtc run-binding --binding=<file> --app=<binary> --out=out/dtc-runs
$HSBB dtc system-prepare --corpus=<dir> --results=<results.jsonl> --out=<deepseek-packet.json>
$HSBB dtc system-call --packet=<deepseek-packet.json> --stage=archetype_decision --out=<deepseek-response.json>
$HSBB dtc system-validate --packet=<deepseek-packet.json> --stage=archetype_decision --response=<deepseek-response.json>
$HSBB dtc flow
$HSBB dtc run entr --app=<binary>
$HSBB dtc run entr --app=<binary> --out=out/dtc-runs
```

`dtc plan/run <name>` 只用于 regression seed。面向大量 PB/外部任务的主入口是 `plan-binding` / `run-binding`，避免为每个项目维护一个 CLI 指令。

## 当前 seed 判断

- `entr`: 上游 `system_test.sh` 覆盖主行为面较强，已抽出 9 个 watcher CLI DTC flow，并用 corpus 内真实 `entr` binary 验证通过。
- `bat`: 上游自带测试主要覆盖 `httplib`，CLI 主行为主要由 PB grader 暴露。当前已走 `requirements HttpClientCli -> validate-binding -> plan-binding -> run-binding`，跑通 14 个 seed flow：help、basic GET、default GET、default POST、GET query items、headers、PUT JSON items、form body、raw body、non-2xx body、pretty=false JSON rendering、response body print、basic auth、download file。
- `atlas`: 高难度 PB 任务，当前由 Codex 人工替代 LLM 抽取
  `StructuredSubcommandCli` binding，已在 PB task container 内跑通 11 个
  binding-driven flow：help、version、license、completion、migrate/schema nested help、
  `schema fmt`、`migrate new`、`migrate hash`、`migrate validate`、checksum mismatch。

PB reference 环境标准执行方式是把 Linux 版 `hsbb` 注入 task container，与
`/workspace/executable` 同容器运行。最近一次真实结果：`entr` 为 `9/9 Pass`，
`bat` 为 `14/14 Pass`，`atlas` 为 `11/11 Pass`。这比 host `hsbb` +
`docker exec` wrapper 更可靠，因为 fixture、trigger 和黑盒共享同一个文件/网络视角。

这些 Pass 的含义是“当前 DTC plan 覆盖的 behavior/spec surfaces 成立”，不是
“项目完整正常使用”或“PB grader 全覆盖”。entr/bat 当前是可复用 archetype seed
验证通过：entr 覆盖 watcher CLI 主干行为，bat 覆盖 HTTP client CLI 主流请求/响应
行为；未进入 flow 的平台差异、边缘命令、URL shorthand、TLS/代理、大文件等仍需继续
从 source/grader 中抽取。

## 架构边界

旧 DeepSeek/oracle/confidence loop 已从编译面删除。当前代码面分三层：

- Haskell runtime：fixture/run/trigger/capture/verify，负责确定性执行。
- Haskell archetype：`WatcherCli`、`HttpClientCli`、`StructuredSubcommandCli`
  这类可复用业务 flow builder。
- LLM 系统层：`system-prepare` 机械读取 source/grader/results 并生成 DeepSeek 输入包，后续 API adapter 只能消费这个包。

类 entr 任务不要复制 `entrPlan` 的具体 step。先用 `hsbb dtc requirements WatcherCli` 取得参数需求，再由决策节点从 source/upstream tests/grader/help 中抽取 binding，并用 `hsbb dtc validate-binding --binding=<file>` 校验是否 `binding_ready`；当前 plan 落地形态仍是新建一个 `WatcherCliSpec`，填入 flag、changed-path token、错误文案和 source/grader 来源，再用 `watcherCliSteps` 生成通用 watcher flow。

`PlanStep` 和 `DtcRunResult` 已带 `BehaviorSurface` / `SpecSurface` 标签。它们用于让 Codex 看到“验证了哪些行为面、依赖哪些规格面”，后续 readiness gate 应基于这些标签，而不是主观判断信息密度。

`hsbb dtc coverage entr` 当前会汇总 watcher surfaces：behavior/spec surfaces 均无缺口，readiness 为 `ReadinessHigh`。continuous watcher flow 使用 `runtime.evidence_stop`，证据出现后由 runtime 主动停止长驻进程。

`hsbb dtc run-binding --binding=<file>` 当前会启动本地 HTTP fixture 并展开 `${PORT}`。HTTP fixture 支持 method/path/query/header/body needles，用于避免 request surface 虚标；在当前沙箱下监听 `127.0.0.1` 需要 escalated 运行。

`hsbb dtc system-prepare --corpus=<dir> [--results=<results.jsonl>] [--out=<file>]` 是 LLM 系统层入口：Haskell 机械读取 source/grader/results，切成 chunk，提取 signal lines，并生成 DeepSeek 的 archetype decision、binding generation、result evaluation、oracle generation 四阶段输入包。DeepSeek 只能基于 chunk id / result chunk id 做决策，不直接参与 runtime hot path。

`hsbb dtc system-call` 会通过 OpenAI-compatible DeepSeek API 调用指定 stage，API key 从 `DEEPSEEK_API_KEY` 读取；`system-validate` 会离线校验 DeepSeek 输出的阶段字段和 chunk/result 引用。真实 API 调用会把 packet 内容发送到外部服务，默认应先人工确认数据外发边界。
