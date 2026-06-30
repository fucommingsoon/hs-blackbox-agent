# hs-blackbox-agent

Haskell DTC for ProgramBench-style black-box targets.

DTC 是这个项目的主线：用 Haskell 承载可复用测试流程，逐步融合上游 regression、PB grader、以及后续更多项目特有 runner。LLM 不负责每轮猜 probe、打分、收敛；LLM 只保留在少量非确定性节点，例如业务方向校准和报告整理。

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
$HSBB dtc flow
$HSBB dtc run entr --app=<binary>
```

## 当前 seed 判断

- `entr`: 上游 `system_test.sh` 覆盖主行为面较强，适合抽 watcher CLI 的通用 Haskell flow。
- `bat`: 上游自带测试主要覆盖 `httplib`，CLI 主行为主要由 PB grader 暴露，适合抽 HTTP client CLI 的 grader-led flow。

## 当前代码面

旧 DeepSeek/oracle/confidence loop 已从编译面删除。当前只保留：

- `Blackbox.DTC`: Haskell DTC 类型和 entr/bat seed plan。
- `Blackbox.DTC.Runtime`: 分层 runtime，已支持文件 fixture、sync/async process、file append trigger 和基础 expectation。
