# Project Status

给新窗口 Codex / 开发者的快速接手页。先读本文件，再按需要读 `README.md`、`FLOW.md`、`AGENTS.md`、`TODO.md`。

## 当前结论

项目已经从旧的 LLM/oracle/confidence 黑盒循环切到 Haskell DTC 主线。

## 当前推荐动作

下一步不要优先给主框架做不痛不痒的 hardening。当前更高价值动作是继续融合
新的 PB 测试项目：从 `docs/pb/tasks.md` 选一个能暴露新 archetype 或现有
archetype 缺口的任务，先取齐 upstream source + PB grader/eval tests，再走
source/grader/results -> archetype decision -> binding -> 同容器 run-binding ->
结果评估。

只有当新任务真实暴露出 runtime 或 archetype 的共性缺口时，才回到主框架补丁。
不要为了“看起来在优化框架”去做 structured command、artifact index 或 gate
细化；这些是支撑项，不是当前主线。

当前可编译代码里没有 LLM API 调用，也没有旧 DeepSeek/oracle/confidence loop。DeepSeek 被放在系统层边缘节点：消费 Haskell 机械读取和提纯后的 source/grader/results 包，负责黑盒类型决策、binding 生成、执行结果评估、oracle/report 提案。它不参与每步 probe hot path，不直接驱动 runtime。

PB 200+ 任务和后续外部约 800 个项目是同一条路线：不要扩展成 1000 个
`dtc run <project>` 指令，而是沉淀 archetype flow + binding-driven execution。
当前本地 ProgramBench metadata 有 201 个 task，完整清单在
`docs/pb/tasks.md`；PB 融合的具体 runbook 在 `docs/pb/README.md`。

## 当前代码面

- `app/Main.hs`: CLI 入口，只保留 `dtc` 子命令。
- `src/Blackbox/DTC.hs`: 公开入口，re-export 类型、catalog、requirements、binding validation、system packet，并提供 `dtcFlowMermaid`。
- `src/Blackbox/DTC/Catalog.hs`: 项目绑定层，当前包含 `entrPlan` / `batPlan` / `planByName`。
- `src/Blackbox/DTC/Types.hs`: DTC 数据类型，包含 plan/result surface、archetype requirements、binding validation shape。
- `src/Blackbox/DTC/Requirements.hs`: archetype 参数需求入口，当前支持 `WatcherCli` / `HttpClientCli` / `StructuredSubcommandCli`。
- `src/Blackbox/DTC/Binding.hs`: 校验 LLM/Codex 产出的 binding JSON，区分 missing/ambiguous/ready。
- `src/Blackbox/DTC/Archetype/WatcherCli.hs`: 类 entr watcher CLI 的 requirement + reusable flow builder，入口是 `WatcherCliSpec -> watcherCliSteps`。
- `src/Blackbox/DTC/Archetype/HttpClientCli.hs`: 类 bat/httpie/curl HTTP client CLI 的 requirement contract + reusable flow builder，入口是 `HttpClientCliSpec -> httpClientCliSteps`。
- `src/Blackbox/DTC/Archetype/StructuredSubcommandCli.hs`: 类 atlas 多子命令 CLI 的 requirement + reusable flow builder，入口是 `StructuredSubcommandCliSpec -> structuredSubcommandCliSteps`。
- `src/Blackbox/DTC/Env.hs`: runtime 变量展开，当前支持 `${WORK}` 和 `${PORT}`。
- `src/Blackbox/DTC/Fixture.hs`: fixture setup，已支持文件类 fixture和轻量本地 HTTP fixture；HTTP fixture 可分配 `${PORT}`，并按 method/path/query/header/body needles 匹配路由。
- `src/Blackbox/DTC/Runner.hs`: sync/async process runner，支持 stdin、timeout、trigger。
- `src/Blackbox/DTC/Trigger.hs`: trigger runner，已支持 file append trigger。
- `src/Blackbox/DTC/Verifier.hs`: expectation verifier。
- `src/Blackbox/DTC/Runtime.hs`: plan orchestration、隔离工作目录、可选 `results.jsonl` 落盘。
- `src/Blackbox/DTC/Result.hs`: process capture 和 run result JSON shape。
- `src/Blackbox/DTC/System.hs`: LLM 系统层包生成器，机械读取 source/grader/results，生成 DeepSeek 决策、binding、结果评估、oracle 生成输入包。

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
- `corpus/probe-plan-seeds/atlas/source/github`
- `corpus/probe-plan-seeds/atlas/grader`

`pb-metadata`、PB task README/SPEC、旧 distill 产物不作为 DTC seed。

PB task README/SPEC 可作为公开初始文档，但不是 DTC seed truth。融合新项目时
优先回到 source/upstream tests/grader/results。

新 PB 项目融合前必须先把材料取齐：upstream source 锁定到 `task.yaml` 的
repository/commit，PB grader/eval tests 优先来自本地 metadata 的 `tests.json`，
缺失时从 task image/container 中抽取，reference executable 的真实运行结果作为
结果证据。没有 source + grader 时，不应先写 binding 或把 `--help` 首探误当作
完整材料。

## PB task inventory

完整 PB task 清单已维护在 `docs/pb/tasks.md`。当前 metadata root 为
`/Users/kangxin/.cache/uv/archive-v0/sTrhsMs9voIeKDQ8/programbench/data/tasks`，
共 201 个 task：hard 18、medium 120、easy 28、unknown 35。`unknown` 表示
当前 `task.yaml` 未标 difficulty，不代表无需处理。

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
$BIN dtc requirements HttpClientCli
$BIN dtc validate-binding --binding=<file>
$BIN dtc plan-binding --binding=<file>
$BIN dtc run-binding --binding=<file> --app=<binary> --out=out/dtc-runs
$BIN dtc system-prepare --corpus=<dir> --results=<results.jsonl> --out=<deepseek-packet.json>
$BIN dtc system-call --packet=<deepseek-packet.json> --stage=<stage> --out=<deepseek-response.json>
$BIN dtc system-validate --packet=<deepseek-packet.json> --stage=<stage> --response=<deepseek-response.json>
$BIN dtc flow
$BIN dtc run entr --app=<binary> --out=out/dtc-runs
```

`dtc plan/run <name>` 是 regression seed 入口；最终 200+800 任务不要新增 1000 个 name 指令，主入口应是 `plan-binding` / `run-binding`。

`--out=<dir>` 会创建一次 run 目录，每个 step 一个隔离 `${WORK}`，并写 `results.jsonl`。
`dtc system-prepare` 的 `--out=<file>` 是例外：它写 DeepSeek 系统包文件，stdout 只打印摘要。

## 已验证状态

- `cabal build --with-compiler=/Users/kangxin/.ghcup/bin/ghc-9.6.7` 通过。
- Linux amd64 版 `hsbb` 已在 PB task image 内编译成功，导出路径为
  `/private/tmp/hsbb-linux-amd64`。
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
- `dtc requirements HttpClientCli` 会输出 HTTP client CLI 的必填/可选 binding 字段，供 bat/httpie/curl 类任务抽取 URL、method、body/header item、form/raw/auth/download/print 等参数面。
- `dtc requirements StructuredSubcommandCli` 会输出多子命令 CLI 的必填 binding
  字段和可选子流字段，供 atlas 这类任务抽取 help/no-args/nested help、
  optional version/license/completion、formatter 文件输入、migration 文件生成、
  config/env/var 等参数面。version/license/completion 已被降级为 optional，
  避免把 atlas 的元信息命令强加给所有结构化 CLI。
- `dtc validate-binding --binding=<file>` 会校验 LLM/Codex 产出的 binding JSON，并区分 `binding_ready` / `binding_missing` / `binding_ambiguous`。
- `dtc system-prepare --corpus=<dir> [--results=<results.jsonl>] [--out=<file>]` 会生成 DeepSeek 系统包，包含 corpus chunks、signal lines、execution result chunks，以及 archetype decision / binding generation / result evaluation / oracle generation 四个强约束 prompt。
- `dtc system-call --packet=<file> --stage=<stage> [--out=<file>]` 会读取 `DEEPSEEK_API_KEY` 并调用 DeepSeek OpenAI-compatible API；真实调用会外发 packet 内容，必须先确认数据边界。
- `dtc system-validate --packet=<file> --stage=<stage> --response=<file>` 会离线校验 DeepSeek 输出：阶段必填字段、是否引用已知 chunk/result id、是否出现未知 citation。
- corpus 内真实 `bat` 可用 `go build -o bat .` 构建；当前已走 `requirements HttpClientCli -> validate-binding -> plan-binding -> run-binding`，通过 14 个 step：help、basic GET、default GET、default POST、GET query items、headers、PUT JSON items、form body、raw body、non-2xx body、pretty=false JSON rendering、response body print、basic auth、download file。
- HTTP fixture 在当前沙箱下监听 `127.0.0.1` 需要 escalated 运行；这不是 hsbb 业务问题。
- PB 真实 reference 环境验证：把 Linux `hsbb` 注入 PB task 容器，与
  `/workspace/executable` 同容器运行，`entr` 为 `9/9 Pass`，`bat` 为
  `14/14 Pass`。结果分别导出到：
  - `/private/tmp/hsbb-dtc-in-docker-entr/entr/20260701-061958-628670417000/results.jsonl`
  - `/private/tmp/hsbb-pb-bat-dtc-v3/container-out/bat/20260701-080127-528043513000/results.jsonl`
- 这些 Pass 只表示当前 DTC plan 中的 expectation 成立，不表示项目完整正常
  使用，也不表示 PB grader 完整覆盖。`entr 9/9` 代表 watcher CLI 主干行为
  已被 reference executable 验证；`bat 14/14` 代表 HTTP client CLI 主流请求/
  响应面已验证。未覆盖行为仍需继续从 source/grader 抽取。
- PB 同容器 runner 已产品化为 `scripts/pb-dtc-runner.sh`。它会推断 task image、
  复用或重建 `/private/tmp/hsbb-linux-amd64`，创建一次性 task container，
  注入 `hsbb`，并收集 stdout/stderr/exit code/DTC output。
- `ariga__atlas.6d81150` 已开始首探：image
  `programbench/ariga_1776_atlas.6d81150:task` 已拉取成功；通过 runner 跑过
  `--help`、`version`、`license`、`migrate --help`、`schema --help`、
  `completion bash`，均 exit 0。结果目录：
  - `/private/tmp/hsbb-pb-atlas-help`
  - `/private/tmp/hsbb-pb-atlas-version`
  - `/private/tmp/hsbb-pb-atlas-license`
  - `/private/tmp/hsbb-pb-atlas-migrate-help`
  - `/private/tmp/hsbb-pb-atlas-schema-help`
  - `/private/tmp/hsbb-pb-atlas-completion-bash`
- atlas 初步方向不是现有 `WatcherCli` / `HttpClientCli` 的直接套用，而是
  `StructuredSubcommandCli` + 文件系统副作用 flow。当前 Codex 人工替代 LLM
  抽出的 binding 在 `docs/pb/bindings/ariga__atlas.6d81150.json`。
- atlas binding-driven 同容器 DTC 最初在源码 corpus 缺失时扩出 provisional
  `11/11 Pass`，这个过程不合格；现已补入 source/grader，并按源码/grader
  重新审计关键字段后扩到 source-audited `13/13 Pass`：
  `help`、no-args usage、`version`、`license`、`completion bash`、`migrate --help`、
  `schema --help`、`schema fmt` 文件原地格式化、`migrate new` 生成 migration
  文件和 `atlas.sum`、`migrate hash`、`migrate validate`、checksum mismatch
  错误路径、`--config/--env/--var` 配置驱动 schema inspect。最新结果：
  - `/private/tmp/hsbb-pb-atlas-dtc-structured-audit/container-out/atlas/20260701-083041-788100297000/results.jsonl`
  旧 source-audited 12-step 结果：
  - `/private/tmp/hsbb-pb-atlas-dtc-config-env-var/container-out/atlas/20260701-082403-737927710000/results.jsonl`
  旧 source-audited 11-step 结果：
  - `/private/tmp/hsbb-pb-atlas-dtc-source-audit/container-out/atlas/20260701-080917-987701050000/results.jsonl`
  旧 provisional 结果：
  - `/private/tmp/hsbb-pb-atlas-dtc-v4/container-out/atlas/20260701-080142-505559548000/results.jsonl`
- 当前已在源码/grader 中找到 `schema fmt`、`migrate new/hash/validate`、
  `atlas.sum`、checksum mismatch、help/version/license/completion、config/env/var
  以及 no-args usage 的证据；最新结果确认 13 个 step 全部 Pass。这个结论只升级为
  source-audited seed 起点，不代表 atlas 高难度任务已足够复原。
- 本轮逐项审计后的剪裁判断：保留 atlas 的 13 个 step，因为都有 source/grader
  依据；把 version/license/completion 从 required 改成 optional，因为它们对
  atlas 成立但不是所有结构化 CLI 共性；暂不把 migrate apply/status、schema
  inspect sqlite DB、复杂 diff/lint/apply 状态机一次性塞入当前 archetype，避免
  从“结构化 CLI”膨胀成 atlas 专项大而全流程。
- atlas 还没有覆盖全量高难度面：config 错误路径、更多 schema/migration edge
  cases、复杂 migration diff/lint/apply 状态机都还需要继续抽到
  `StructuredSubcommandCli` 或拆成新的文件状态 archetype。
- 不再把 host `hsbb` + PB `docker exec` wrapper 当作标准执行方案。该模式会让
  `${WORK}` 文件和 `127.0.0.1` HTTP fixture 跨环境失真。

注意：`entr.file_change_trigger` 和 `entr.first_changed_file_substitution` 是 continuous watcher evidence flow。它们在证据出现后由 runtime 主动停止进程，`drrStopReason` 为 `EvidenceMatched`，`drrExit` 为 `null` 但 verdict 可为 `Pass`。

## 下一步优先级

1. 继续融合新的 PB 项目，而不是先做抽象框架优化。候选必须从
   `docs/pb/tasks.md` 出发，优先选择能暴露新 archetype 或现有 archetype
   明显缺口的任务。
2. 新任务流程固定为：取齐 source + grader/eval tests -> 首探 reference
   executable -> `system-prepare`/Codex 决策 archetype -> 生成并校验 binding ->
   同容器 `run-binding` -> 对照 source/grader/results 评估还原度。
3. 不要恢复旧 LLM loop。先保持 Haskell DTC 为执行和验证核心；DeepSeek 只能消费 `system-prepare` 的机械读取包做系统层决策/评估/oracle 提案。
4. 类 entr/bat/atlas 任务不要复制旧 seed 的具体 step；先跑对应
   `dtc requirements <Archetype>`，再让决策节点从 source/upstream
   tests/grader/help 中抽取 binding，并用 reusable flow builder 生成流程。
5. 如果新项目暴露共性缺口，再补 archetype 或 runtime：readiness gate、
   structured command、artifact index、HTTP request evidence 等都属于被任务牵引的
   支撑工作，不是单独优先项。
6. bat 后续如果被选中继续扩，不要堆随机 grader case；优先补 request artifact
   index、URL shorthand、proxy/TLS/large or streaming response 这些主流行为面。
7. atlas 若回头继续扩，应在 source-audited 13-step 起点上继续扩
   `StructuredSubcommandCli`/文件状态 archetype，优先补 config 错误路径和更多
   schema/migration edge cases，不要在 catalog 里硬堆 atlas 专属 step。

## 不要做

- 不要恢复 `hsbb init / step / loop / full / step-snap`。
- 不要恢复 `.hsbb/oracle.yaml`、confidence gate、DeepSeek 每轮 probe 决策。
- 不要在 DTC plan 里使用 `./probe`；目标程序统一写 `app 参数1 参数2 ...`。
- 不要把 docker 故障当成 hsbb 的业务问题。
- 不要把 PB wrapper bridge 问题建模成业务 flow；标准方案是 hsbb 与黑盒同容器。
