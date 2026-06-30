# Project Status

给新窗口 Codex / 开发者的快速接手页。先读本文件，再按需要读 `README.md`、`FLOW.md`、`AGENTS.md`、`TODO.md`。

## 当前结论

项目已经从旧的 LLM/oracle/confidence 黑盒循环切到 Haskell DTC 主线。

当前可编译代码里没有 LLM API 调用，也没有 DeepSeek/oracle/confidence loop。LLM 只在架构上保留为未来的少数边缘节点：构建流程里的业务方向校准、执行后的报告整理。它不参与每步 probe 决策、不打分、不写 oracle。

## 当前代码面

- `app/Main.hs`: CLI 入口，只保留 `dtc` 子命令。
- `src/Blackbox/DTC.hs`: 公开入口，re-export 类型、catalog、requirements、binding validation，并提供 `dtcFlowMermaid`。
- `src/Blackbox/DTC/Catalog.hs`: 项目绑定层，当前包含 `entrPlan` / `batPlan` / `planByName`。
- `src/Blackbox/DTC/Types.hs`: DTC 数据类型，包含 plan/result surface、archetype requirements、binding validation shape。
- `src/Blackbox/DTC/Requirements.hs`: archetype 参数需求入口，当前支持 `WatcherCli`。
- `src/Blackbox/DTC/Binding.hs`: 校验 LLM/Codex 产出的 binding JSON，区分 missing/ambiguous/ready。
- `src/Blackbox/DTC/Archetype/WatcherCli.hs`: 类 entr watcher CLI 的 requirement + reusable flow builder，入口是 `WatcherCliSpec -> watcherCliSteps`。
- `src/Blackbox/DTC/Env.hs`: runtime 变量展开，当前支持 `${WORK}` 和 `${PORT}`。
- `src/Blackbox/DTC/Fixture.hs`: fixture setup，已支持文件类 fixture，HTTP fixture 仍 unsupported。
- `src/Blackbox/DTC/Runner.hs`: sync/async process runner，支持 stdin、timeout、trigger。
- `src/Blackbox/DTC/Trigger.hs`: trigger runner，已支持 file append trigger。
- `src/Blackbox/DTC/Verifier.hs`: expectation verifier。
- `src/Blackbox/DTC/Runtime.hs`: plan orchestration、隔离工作目录、可选 `results.jsonl` 落盘。
- `src/Blackbox/DTC/Result.hs`: process capture 和 run result JSON shape。

## 工作流分层

`hsbb` 本体应该是工具类工作流，不应该变成 entr 业务本身：

- 工具工作流：`Runtime` / `Runner` / `Fixture` / `Trigger` / `Verifier`，负责执行、隔离、采集、校验。
- 业务工作流库：`Archetype.WatcherCli`，描述 watcher CLI 这一类业务行为，例如 watch list、file mutation、one-shot、changed-path token。
- 项目绑定：`entrWatcherSpec`，只填 entr 的 flags、错误文案、source/grader 来源。

所以“测 entr”时，`hsbb` 运行的是工具工作流；被执行的 plan 来自 watcher CLI 业务工作流库 + entr 项目绑定。类 entr 任务应该新增项目绑定或扩展 watcher archetype，不应该改 hsbb runtime。

## Surface 标注

`PlanStep` 现在带两类机器可见标签：

- `psBehaviorSurfaces`: 该 step 验证了哪些行为面，如 `stdin.watch_list`、`trigger.file.append`、`child.stdout`、`directory.altered`。
- `psSpecSurfaces`: 该 step 要被文档/规格复原时依赖哪些规格面，如 `run.cmd`、`fixture.shape`、`trigger.shape`、`expect.stdout`。

`DtcRunResult` 会把这些标签原样输出为 `drrBehaviorSurfaces` / `drrSpecSurfaces`。`dtc coverage` 已能汇总 covered/missing surfaces 并给出 readiness；下一步要加强 gate 粒度，避免只看 surface 名称导致虚高。

## 当前 seed corpus

只把源码和测试流程当 seed：

- `corpus/probe-plan-seeds/entr/source/github`
- `corpus/probe-plan-seeds/entr/grader`
- `corpus/probe-plan-seeds/bat/source/github`
- `corpus/probe-plan-seeds/bat/grader`

`pb-metadata`、PB task README/SPEC、旧 distill 产物不作为 DTC seed。

## 命令

必须用 ghcup 的 GHC 9.6.7：

```bash
/Users/kangxin/.ghcup/bin/cabal build --with-compiler=/Users/kangxin/.ghcup/bin/ghc-9.6.7
BIN=$(find dist-newstyle -name hsbb -type f -perm +111 | head -1)
```

常用 DTC 命令：

```bash
$BIN dtc plan entr
$BIN dtc plan bat
$BIN dtc coverage entr
$BIN dtc requirements WatcherCli
$BIN dtc validate-binding --binding=<file>
$BIN dtc flow
$BIN dtc run entr --app=<binary> --out=out/dtc-runs
```

`--out=<dir>` 会创建一次 run 目录，每个 step 一个隔离 `${WORK}`，并写 `results.jsonl`。

## 已验证状态

- `cabal build --with-compiler=/Users/kangxin/.ghcup/bin/ghc-9.6.7` 通过。
- corpus 内真实 `entr` 可通过 `./configure` + `make` 构建。
- 真实 entr DTC run 通过 9 个 step：
  - `entr.no_arguments`
  - `entr.no_regular_files`
  - `entr.empty_input`
  - `entr.stdout_child_passthrough`
  - `entr.child_exit_code`
  - `entr.file_change_trigger`
  - `entr.oneshot_after_file_change`
  - `entr.first_changed_file_substitution`
  - `entr.directory_altered`
- `results.jsonl` 每个 step 一行，result 内含 `drrWorkDir`。
- `results.jsonl` 已包含 `drrBehaviorSurfaces` 和 `drrSpecSurfaces`。
- `dtc coverage entr` 当前为 `ReadinessHigh`，behavior/spec surfaces 均无缺口。
- `dtc requirements WatcherCli` 会输出该 archetype 的必填/可选 binding 字段，供决策节点按清单回到源码/测试/help/grader 中抽取参数。
- `dtc validate-binding --binding=<file>` 会校验 LLM/Codex 产出的 binding JSON，并区分 `binding_ready` / `binding_missing` / `binding_ambiguous`。

注意：`entr.file_change_trigger` 和 `entr.first_changed_file_substitution` 是 continuous watcher evidence flow。它们在证据出现后由 runtime 主动停止进程，`drrStopReason` 为 `EvidenceMatched`，`drrExit` 为 `null` 但 verdict 可为 `Pass`。

## 下一步优先级

1. 不要恢复旧 LLM loop。先保持 Haskell DTC 为执行和验证核心。
2. 下一轮看 bat 时，先定义 `HttpClientCli` 的 requirements/binding shape，再决定 HTTP fixture 是否需要补强。
3. 继续加强 readiness gate 的判定粒度，避免只看 surface 名称导致虚高。
4. 类 entr 任务不要复制 `entrPlan` step；先跑 `dtc requirements WatcherCli`，再新增一个 `WatcherCliSpec`，最后用 `watcherCliSteps` 生成流程。
5. 做 generic runtime hardening：structured command，减少 shell quoting 依赖。
6. 给 result 增加 artifact index，把 `${WORK}` 下的重要文件挂到 result。
7. 从 `entr` 和 `bat` 源码 + grader 中继续抽可复用 flow archetype，但避免过度绑定单项目细节。

## 不要做

- 不要恢复 `hsbb init / step / loop / full / step-snap`。
- 不要恢复 `.hsbb/oracle.yaml`、confidence gate、DeepSeek 每轮 probe 决策。
- 不要在 DTC plan 里使用 `./probe`；目标程序统一写 `app 参数1 参数2 ...`。
- 不要把 docker 故障当成 hsbb 的业务问题。
