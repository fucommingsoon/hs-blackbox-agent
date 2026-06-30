# hs-blackbox-agent - Haskell DTC flows

DTC 要分成两条流程看：

- **构建流程**：把公开源码和测试流程沉淀成可复用的 Haskell DTC plan。
- **Agent 执行流程**：拿一个 DTC plan 和一个目标 binary，执行 fixture/run/trigger/verify。

## 构建流程

```mermaid
flowchart TD
    Corpus[Seed corpus<br/>source + upstream tests + grader] --> Read
    Read[Haskell readers<br/>source/test/grader adapters] --> Surface
    Surface[Behavior surfaces<br/>CLI flags / IO channels / fixtures / errors] --> Archetype
    Archetype[Flow archetypes<br/>watcher CLI / HTTP client CLI / formatter CLI] --> Calibrate
    Calibrate{Optional LLM calibration<br/>business direction + priority only} --> Plan
    Plan[DTC plan library<br/>PlanStep fixture/run/trigger/expect/source] --> Review
    Review[Human/code review<br/>remove low-value or overfit flows] --> Versioned[Versioned Haskell plan]
```

构建流程的产物是 plan，不执行目标程序，也不判断某个 app 是否通过。

## Agent 执行流程

```mermaid
flowchart TD
    Input[DTC plan + app binary] --> Select
    Select[Select PlanStep] --> Setup
    Setup[Fixture setup<br/>files / HTTP server / temp workspace] --> Run
    Run[Run app args<br/>stdin + timeout + sync/async process] --> Trigger
    Trigger[Trigger actions<br/>file append / HTTP ready / future events] --> Capture
    Capture[Capture evidence<br/>stdout / stderr / exit / duration / artifacts] --> Verify
    Verify[Haskell verifier<br/>expectations -> pass/fail/unsupported] --> Result
    Result[DTC run result JSON<br/>per-step verdict + gaps] --> Report
    Report{Optional LLM report<br/>organize findings only} --> Done[Verified feature report]
```

执行流程不读取 grader 私有答案，不让 LLM 打分，也不通过 oracle/confidence 收敛。

## 当前实现状态

已完成：

- `hsbb dtc plan entr`
- `hsbb dtc plan bat`
- `hsbb dtc flow`
- `hsbb dtc run <entr|bat> --app=<binary>`

Runtime 当前支持文件类 fixture、同步/异步 `RunSpec`、stdin、timeout、file append trigger、基础 stdout/stderr/exit/duration expectation。`StartHttpFixture` 仍会显式返回 unsupported gap。

## 已删除旧逻辑

旧 DeepSeek/oracle/confidence loop 已从编译面删除，不再有 legacy CLI。
