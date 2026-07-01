# TODO

## P0 - Generic runtime hardening

- 增加 command 参数结构化，减少 shell quoting 依赖。
- 保持 `app 参数1 参数2 ...` 的 plan 写法，但 runtime 内部不要长期依赖 shell string。
- readiness gate 继续加强：不能只看 surface 名称齐不齐，还要看关键 step 是否真实命中对应证据。
- 继续把 binding spec catalog 数据化，避免 Haskell 入口堆项目。
- PB 同容器 runner 已有：`scripts/pb-dtc-runner.sh` 复用 Linux `hsbb`
  builder/cache，把 task image + `/workspace/executable` + `hsbb dtc ...`
  包成稳定入口；后续增强 artifact index 和 binding 分发。
- 根据 `binding_ready` 的外部 binding 生成 project spec/plan 已有初版：`plan-binding` / `run-binding` 支持 `HttpClientCli`。
- result 后续可补 artifact index，把 `${WORK}` 下的重要文件挂到 result。
- LLM 系统层已有 DeepSeek API adapter 和输出校验器；后续补更细的 schema 校验、response pretty/JSONL 包格式、以及外发数据脱敏/裁剪策略。
- `docs/pb/tasks.md` 已有 201 个 ProgramBench task 清单；后续要把 `unknown`
  difficulty 的 35 个任务做难度归类或单独分桶。

## P1 - DTC runtime components

- 执行 `FixtureAction`
  - `TouchFile` 已有
  - `WriteFileText` 已有
  - `AppendFileText` 已有
  - `StartHttpFixture`
  - `SleepMs` 已有
- 执行 `RunSpec`
  - `app` 绑定到实际 binary 已有
  - `${WORK}` runtime 插值 已有
  - stdin 注入 已有
  - sync mode 已有
  - async mode 已有
  - timeout 已有
  - evidence-stop 已有
- 执行 `TriggerAction`
  - file append trigger 已有
  - HTTP fixture ready trigger
- 执行 `Expectation`
  - exit code 已有
  - stdout/stderr contains/empty 已有
  - duration upper bound 已有

## P2 - Flow extraction

- `entr`: 从 `system_test.sh` 抽 watcher CLI flow archetype。
- `entr`: 从 grader 抽交互/状态/错误路径补充项。
- `bat`: `HttpClientCli` requirements + reusable flow builder 已有；当前主流 14-step flow 已覆盖 method/query/header/json/form/raw/status/pretty、response body print、basic auth、download file。
- `bat`: 用源码/grader 继续确认 URL shorthand、proxy/TLS、bench、大文件/流式响应行为，优先补到 archetype flow 或独立 reusable flow，不要继续堆 `batPlan` 单项目 step。
- PB 200+ 融合：继续挑选能暴露新 archetype 或现有 archetype 缺口的项目，不要
  以单项目得分为目标堆 step。
- PB 任务选择必须从 `docs/pb/tasks.md` 出发，避免继续依赖仓库外历史清单。
- `ariga__atlas.6d81150`: source/grader 已补到 corpus。第一版
  `StructuredSubcommandCli` binding-driven flow 最初是在 source corpus 缺失时
  扩出的，这个过程不合格；现已完成 source-grounded re-audit 并复跑
  source-audited 13/13。覆盖 help/no-args usage、completion/version/license、
  nested help、`schema fmt`、`migrate new/hash/validate`、checksum mismatch、
  config/env/var 驱动 schema inspect。version/license/completion 已改成
  optional 子流，避免污染下一个结构化 CLI。下一步补 config 错误路径和更多
  schema/migration edge cases，不要直接堆 atlas 专属步骤。

## 已完成 runtime 基础能力

- 增加 DTC result JSONL 落盘 已有。
- 增加 fixture 工作目录隔离 已有。
- 增加 file touch / mkdir trigger 已有。
- `PlanStep` 增加 `BehaviorSurface` / `SpecSurface` 已有。
- `DtcRunResult` 输出 `drrBehaviorSurfaces` / `drrSpecSurfaces` 已有。
- `Blackbox.DTC.Catalog` 项目绑定层 已有。
- `hsbb dtc coverage <plan>` 已有。
- `hsbb dtc requirements WatcherCli` 已有。
- `hsbb dtc requirements HttpClientCli` 已有。
- `hsbb dtc validate-binding --binding=<file>` 已有。
- `hsbb dtc plan-binding --binding=<file>` 已有，当前支持 `HttpClientCli`。
- `hsbb dtc run-binding --binding=<file> --app=<binary>` 已有，当前支持 `HttpClientCli`。
- `hsbb dtc system-prepare --corpus=<dir> [--results=<results.jsonl>] [--out=<file>]` 已有，生成 DeepSeek system packet：corpus chunks、signal lines、result chunks、四阶段 prompt。
- `hsbb dtc system-call --packet=<file> --stage=<stage> [--out=<file>]` 已有，读取 `DEEPSEEK_API_KEY` 并调用 DeepSeek API。
- `hsbb dtc system-validate --packet=<file> --stage=<stage> --response=<file>` 已有，可校验直接 JSON 或 DeepSeek API response wrapper。
- 轻量本地 HTTP fixture 已有，支持 method/path/query/header/body needle 匹配和 `${PORT}` 插值。
- continuous watcher evidence flow 已显式化：证据出现后 runtime 主动停止长驻进程，结果写出 `drrStopReason`。
- PB 同容器真实执行已验证：Linux `hsbb` 注入 task container 后，`entr` 9/9
  Pass，`bat` 14/14 Pass，`atlas` source-audited 13/13 Pass。执行细节见
  `docs/pb/README.md`。
- `scripts/pb-dtc-runner.sh` 已有，支持 `--mode=app` 首探
  `/workspace/executable`，以及默认 `hsbb` 模式执行同容器 DTC。
- runner 已支持 `--copy=host:container`，用于把 binding JSON 等 host 材料显式
  放进 task container。
- `StructuredSubcommandCli` 已有第一版 requirements + binding-driven plan builder；
  atlas 样例 binding 在 `docs/pb/bindings/ariga__atlas.6d81150.json`。

## 已完成 entr seed flow

这些 flow 现在由 `WatcherCliSpec -> watcherCliSteps` 生成，不应作为 entr 专属 step 复制到下一个项目。

- `entr.no_arguments`
- `entr.no_regular_files`
- `entr.empty_input`
- `entr.stdout_child_passthrough`
- `entr.child_exit_code`
- `entr.file_change_trigger`
- `entr.oneshot_after_file_change`
- `entr.first_changed_file_substitution`
- `entr.directory_altered`

## 暂停项

- 不再恢复旧 DeepSeek/oracle/confidence loop。
- 不再围绕 `.hsbb/oracle.yaml` 设计新功能。
