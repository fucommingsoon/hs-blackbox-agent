# TODO

## P0 - Generic runtime hardening

- 增加 command 参数结构化，减少 shell quoting 依赖。
- 保持 `app 参数1 参数2 ...` 的 plan 写法，但 runtime 内部不要长期依赖 shell string。
- readiness gate 继续加强：不能只看 surface 名称齐不齐，还要看关键 step 是否真实命中对应证据。
- 继续把 binding spec catalog 数据化，避免 Haskell 入口堆项目。
- 根据 `binding_ready` 的外部 binding 生成 project spec/plan，减少手写 catalog。
- result 后续可补 artifact index，把 `${WORK}` 下的重要文件挂到 result。

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
- `bat`: 从 grader 抽 HTTP client CLI flow archetype。
- `bat`: 用源码确认 CLI 参数解析、URL shorthand、output/download/bench 行为。

## 已完成 runtime 基础能力

- 增加 DTC result JSONL 落盘 已有。
- 增加 fixture 工作目录隔离 已有。
- 增加 file touch / mkdir trigger 已有。
- `PlanStep` 增加 `BehaviorSurface` / `SpecSurface` 已有。
- `DtcRunResult` 输出 `drrBehaviorSurfaces` / `drrSpecSurfaces` 已有。
- `Blackbox.DTC.Catalog` 项目绑定层 已有。
- `hsbb dtc coverage <plan>` 已有。
- `hsbb dtc requirements WatcherCli` 已有。
- `hsbb dtc validate-binding --binding=<file>` 已有。
- continuous watcher evidence flow 已显式化：证据出现后 runtime 主动停止长驻进程，结果写出 `drrStopReason`。

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
