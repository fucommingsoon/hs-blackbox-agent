# hs-blackbox-agent

Haskell DTC for ProgramBench-style black-box targets.

DTC 是这个项目的主线：用 Haskell 承载可复用测试流程，逐步融合上游 regression、PB grader、以及后续更多项目特有 runner。LLM 不负责每轮猜 probe、打分、收敛；LLM 只保留在少量非确定性节点，例如业务方向校准和报告整理。

## 快速接手

新窗口 Codex / 开发者建议按这个顺序读：

1. `STATUS.md`: 当前代码状态、已删逻辑、下一步优先级。
2. `AGENTS.md`: 本地构建、运行和开发约束。
3. `FLOW.md`: DTC 构建流程和 Agent 执行流程。
4. `TODO.md`: 当前待办。

## 输入边界

DTC seed corpus 只放两类材料：

| 输入 | 用途 |
|---|---|
| 上游源码 | 判断程序公开能力、参数面、实现约束 |
| 测试流程 | 上游自带测试和 PB grader，用来抽取真实行为面 |

当前 seed 在 `corpus/probe-plan-seeds/`，每个项目只保留 `source/` 和 `grader/`。`pb-metadata`、PB task README/SPEC、旧 distill 产物都不作为 DTC seed。

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
$HSBB dtc validate-binding --binding=<file>
$HSBB dtc flow
$HSBB dtc run entr --app=<binary>
$HSBB dtc run entr --app=<binary> --out=out/dtc-runs
```

## 当前 seed 判断

- `entr`: 上游 `system_test.sh` 覆盖主行为面较强，已抽出 9 个 watcher CLI DTC flow，并用 corpus 内真实 `entr` binary 验证通过。
- `bat`: 上游自带测试主要覆盖 `httplib`，CLI 主行为主要由 PB grader 暴露，适合抽 HTTP client CLI 的 grader-led flow。

## 当前代码面

旧 DeepSeek/oracle/confidence loop 已从编译面删除。当前只保留：

- `Blackbox.DTC`: plan 组装和公开入口。
- `Blackbox.DTC.Catalog`: 项目绑定层，当前包含 entr/bat seed plans。
- `Blackbox.DTC.Types`: Haskell DTC 类型。
- `Blackbox.DTC.Archetype.WatcherCli`: 类 entr watcher CLI 的 requirement + flow builder。
- `Blackbox.DTC.Requirements`: archetype 参数需求入口，用于“先假定类型，再让 Haskell 反问需要哪些 binding 参数”。
- `Blackbox.DTC.Env`: runtime 变量上下文，当前支持 `${WORK}` 和 `${PORT}` 插值。
- `Blackbox.DTC.Runtime`: 分层 runtime，已支持隔离工作目录、result JSONL 落盘、文件 fixture、sync/async process、file append trigger、evidence-stop 和基础 expectation。

当前代码没有 LLM API 调用。文档里提到的 optional LLM 节点是未来边缘能力占位，不是现有 runtime 行为。

类 entr 任务不要复制 `entrPlan` 的具体 step。先用 `hsbb dtc requirements WatcherCli` 取得参数需求，再由决策节点从 source/upstream tests/grader/help 中抽取 binding，并用 `hsbb dtc validate-binding --binding=<file>` 校验是否 `binding_ready`；当前 plan 落地形态仍是新建一个 `WatcherCliSpec`，填入 flag、changed-path token、错误文案和 source/grader 来源，再用 `watcherCliSteps` 生成通用 watcher flow。

`PlanStep` 和 `DtcRunResult` 已带 `BehaviorSurface` / `SpecSurface` 标签。它们用于让 Codex 看到“验证了哪些行为面、依赖哪些规格面”，后续 readiness gate 应基于这些标签，而不是主观判断信息密度。

`hsbb dtc coverage entr` 当前会汇总 watcher surfaces：behavior/spec surfaces 均无缺口，readiness 为 `ReadinessHigh`。continuous watcher flow 使用 `runtime.evidence_stop`，证据出现后由 runtime 主动停止长驻进程。
