# TODO

## P0 - DTC runtime

- 执行 `FixtureAction`
  - `TouchFile` 已有
  - `WriteFileText` 已有
  - `AppendFileText` 已有
  - `StartHttpFixture`
  - `SleepMs` 已有
- 执行 `RunSpec`
  - `app` 绑定到实际 binary 已有
  - stdin 注入 已有
  - sync mode 已有
  - async mode 已有
  - timeout 已有
- 执行 `TriggerAction`
  - file append trigger 已有
  - HTTP fixture ready trigger
- 执行 `Expectation`
  - exit code 已有
  - stdout/stderr contains/empty 已有
  - duration upper bound 已有

## P1 - Flow extraction

- `entr`: 从 `system_test.sh` 抽 watcher CLI flow archetype。
- `entr`: 从 grader 抽交互/状态/错误路径补充项。
- `bat`: 从 grader 抽 HTTP client CLI flow archetype。
- `bat`: 用源码确认 CLI 参数解析、URL shorthand、output/download/bench 行为。

## P2 - Runtime hardening

- 增加 DTC result JSONL 落盘。
- 增加 fixture 工作目录隔离。
- 增加 command 参数结构化，减少 shell quoting 依赖。

## 暂停项

- 不再恢复旧 DeepSeek/oracle/confidence loop。
- 不再围绕 `.hsbb/oracle.yaml` 设计新功能。
