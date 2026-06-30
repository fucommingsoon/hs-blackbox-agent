# AGENTS.md

给 agent / 开发者的操作手册。不重复 README/FLOW 的架构描述，只补怎么干活。新窗口先读 `STATUS.md`，再读本文件。

## 构建

必须用 ghcup 的 GHC 9.6.7，Homebrew 的 GHC 9.14.x 有 ffi.h 兼容问题会编译失败：

```bash
cd /Users/kangxin/Documents/workspace/konceptosv18/hs-blackbox-agent
/Users/kangxin/.ghcup/bin/cabal build --with-compiler=/Users/kangxin/.ghcup/bin/ghc-9.6.7
```

二进制路径：

```bash
BIN=$(find dist-newstyle -name hsbb -type f -perm +111 | head -1)
```

## 当前主线：Haskell DTC

优先修改 `src/Blackbox/DTC.hs`、`src/Blackbox/DTC/Archetype/*` 及后续 DTC runtime 模块。当前没有 LLM API 调用；不要把文档里的 optional LLM calibration/report 理解成已实现功能。

工作流边界：

- `hsbb` runtime 是工具工作流，只做 fixture/run/trigger/capture/verify。
- `Archetype.*` 是业务工作流库，承载 watcher CLI、HTTP client CLI 等可复用业务行为。
- 具体项目只提供 spec/catalog 绑定。不要为了 entr 特例改 runtime；先判断是 archetype 缺能力还是项目 spec 配错。
- `PlanStep` / `DtcRunResult` 的 `BehaviorSurface` 和 `SpecSurface` 是 coverage/readiness 的输入，不要删成普通备注。

默认命令：

```bash
$BIN dtc plan entr
$BIN dtc plan bat
$BIN dtc coverage entr
$BIN dtc requirements WatcherCli
$BIN dtc validate-binding --binding=<file>
$BIN dtc flow
$BIN dtc run entr --app=<binary> --out=out/dtc-runs
```

DTC 计划语言里目标程序统一写 `app 参数1 参数2 ...`。不要在 DTC plan 里使用 `./probe` 作为抽象。fixture、trigger、stdin、cmd 里的临时路径优先写 `${WORK}/...`，由 runtime 为每个 step 创建隔离工作目录。

复跑真实 entr seed flow：

```bash
cd corpus/probe-plan-seeds/entr/source/github
./configure
make
cd /Users/kangxin/Documents/workspace/konceptosv18/hs-blackbox-agent
$BIN dtc run entr --app=corpus/probe-plan-seeds/entr/source/github/entr --out=/private/tmp/hsbb-dtc-real-entr
```

当前真实 entr run 应有 9 个 step，全部 `Pass`。其中 continuous watcher evidence flow 会在 stdout/stderr 证据出现后由 runtime 主动停止长驻进程，`drrStopReason` 应为 `EvidenceMatched`，`drrExit` 可为 `null`。
结果 JSON 中应包含 `drrBehaviorSurfaces` / `drrSpecSurfaces`。
`$BIN dtc coverage entr` 当前应返回 `ReadinessHigh`，behavior/spec surface 缺口都应为空。

类 entr 任务接入方式：

1. 不复制 `entrPlan` 生成出来的 `PlanStep`。
2. 先跑 `$BIN dtc requirements WatcherCli`，让 Haskell 给出必填/可选 binding 字段。
3. 决策节点从 source/upstream tests/grader/help 中抽取这些字段，并记录来源和置信度。
4. 用 `$BIN dtc validate-binding --binding=<file>` 校验 binding 是否 `binding_ready`。
5. 当前代码落地时，在 `Blackbox.DTC` 中新增一个项目 spec，或后续拆到项目 catalog。
6. 用 `Blackbox.DTC.Archetype.WatcherCli.WatcherCliSpec` 填项目差异：flag、changed-path token、错误文案、source/grader 来源。
7. 用 `watcherCliSteps spec` 生成流程。

## Seed Corpus

当前语料目录：

- `corpus/probe-plan-seeds/entr/source/github`
- `corpus/probe-plan-seeds/entr/grader`
- `corpus/probe-plan-seeds/bat/source/github`
- `corpus/probe-plan-seeds/bat/grader`

只把源码和测试流程当 seed。`pb-metadata`、PB task README/SPEC、旧 distill 产物属于干扰项。

## 已删除旧逻辑

旧 DeepSeek/oracle/confidence loop 已从编译面删除。不要恢复这些命令：

```bash
hsbb init / step / loop / full / step-snap
hsbb legacy ...
```

## 当前 TODO

1. 增加 structured command，减少 shell quoting 依赖。
2. 继续加强 readiness gate：不能只看 surface 名称齐不齐，还要看关键 step 是否真实命中对应证据。
3. 继续把项目 spec catalog 数据化，避免 Haskell 入口堆项目。
4. 给 result 增加 artifact index，把 `${WORK}` 下的重要文件挂到 result。
5. 实现低权重 runtime component：HTTP fixture 和 `TriggerHttpReady`。
6. 从 `entr` 和 `bat` 的 source/grader 中提取更多 flow archetype。

不要继续调旧 confidence / gate prompt。
