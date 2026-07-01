# Codex-as-LLM PB Flow

本文件描述当前没有真实 LLM 参与时，新窗口 Codex 如何临时代替 LLM 完成
PB 新任务融合。它不是聊天记忆总结，而是机械 runbook。

## 目标

Codex 只替代系统层 LLM 节点：

```text
source/grader/results -> archetype decision -> binding generation
                    -> run-binding result evaluation -> next action
```

Codex 不直接手写 runtime step，不跳过 Haskell `requirements`，也不根据
`--help` 或 README/SPEC 猜完整 binding。

## 必读入口

新窗口按顺序读：

1. `STATUS.md`
2. `AGENTS.md`
3. `docs/pb/README.md`
4. 本文件
5. 目标任务的 source/grader/results

如果目标任务是新 archetype，先确认 `src/Blackbox/DTC/Requirements.hs` 是否已有
对应 requirement 入口。当前 binding-driven archetype 包括：

- `HttpClientCli`
- `StructuredSubcommandCli`
- `TabularRenderCli`

`WatcherCli` 目前主要由 regression catalog 使用；类 entr 新任务若要进入
binding-driven flow，需要先确认或补齐对应 binding-driven builder。

## 固定流程

### 1. 选任务

从 `docs/pb/tasks.md` 选任务，优先选能暴露新 archetype 或现有 archetype
缺口的项目。不要以“容易多加几个 Pass”为目标。

记录任务 id，例如：

```text
wfxr__csview.8ac4de0
```

### 2. 取齐材料

必须先落地：

- upstream source，锁定 `task.yaml` 的 repository + commit；
- PB grader/eval tests，优先 metadata `tests.json`，缺失时从 task image/container 抽取；
- reference executable 首探结果，只用于确认入口和可观察行为，不替代 source/grader。

推荐目录形态：

```text
corpus/probe-plan-seeds/<short-name>/source/github
corpus/probe-plan-seeds/<short-name>/grader
```

材料不齐时，先补材料；不要先写 binding。

### 3. 编译 hsbb

```bash
/Users/kangxin/.ghcup/bin/cabal build --with-compiler=/Users/kangxin/.ghcup/bin/ghc-9.6.7
BIN=$(find dist-newstyle -name hsbb -type f -perm +111 | head -1)
```

### 4. 首探 reference executable

只做最小首探，确认 binary 入口、help、明显错误路径：

```bash
scripts/pb-dtc-runner.sh --task=<task-id> --mode=app -- --help
```

必要时补少量命令，例如 version、子命令 help、最小输入输出。首探结果放在
runner 的 host `--out` 目录，后续只作为取证缓存。路径语义见
`docs/pb/README.md` 的“同容器执行方案 / 路径语义”。

### 5. 生成 system packet

如果已有首探或 DTC run 结果，把 results 带进去：

```bash
$BIN dtc system-prepare \
  --corpus=corpus/probe-plan-seeds/<short-name> \
  --results=<results.jsonl> \
  --out=<host-packet.json>
```

没有 results 时也可以先生成 source/grader 包：

```bash
$BIN dtc system-prepare \
  --corpus=corpus/probe-plan-seeds/<short-name> \
  --out=<host-packet.json>
```

Codex 替代 LLM 时，必须基于 packet、source、grader、results 做判断，不能凭聊天记忆。

### 6. 判定 archetype

先粗判类型，再跑 Haskell requirements：

```bash
$BIN dtc requirements HttpClientCli
$BIN dtc requirements StructuredSubcommandCli
$BIN dtc requirements TabularRenderCli
```

当前第四类 `TabularRenderCli` 的典型任务是 `csview` / `xsv` 类表格渲染 CLI。
它关注 stdin/file 输入、CSV/TSV/custom delimiter、style/layout、missing file、
no-header、序号列、宽字符、畸形输入错误等共性面。

如果 requirements 不覆盖目标项目的核心行为，先记录缺口；只有缺口是跨项目共性
时，才扩 `src/Blackbox/DTC/Archetype/*`。

### 7. 生成 binding

Codex 读取 requirements 后，从 source/grader/results 中填 binding JSON：

```text
docs/pb/bindings/<task-id>.json
```

必须保留字段来源意识：

- 必填字段找不到证据时，不要编；
- 可选字段只有 source/grader/results 有证据才填；
- 单项目特例不要塞进 archetype 共性字段。

已有样例：

```text
docs/pb/bindings/ariga__atlas.6d81150.json
docs/pb/bindings/wfxr__csview.8ac4de0.json
```

### 8. 校验 binding

```bash
$BIN dtc validate-binding --binding=docs/pb/bindings/<task-id>.json
```

如果不是 `binding_ready`：

- `binding_missing`: 回到 source/grader/results 补证据；
- `binding_ambiguous`: 缩小字段含义或删掉低置信可选字段；
- 不要通过改 runtime 绕过 binding 质量问题。

### 9. 预览 plan

```bash
$BIN dtc plan-binding --binding=docs/pb/bindings/<task-id>.json
```

检查 step 是否是 archetype 共性行为，不是项目专项堆砌。若 step 看起来太像
单项目测试脚本，回到 archetype/binding 边界重新切分。

### 10. 同容器 run-binding

真实 PB reference 标准入口必须同容器运行：

```bash
scripts/pb-dtc-runner.sh \
  --task=<task-id> \
  --copy=docs/pb/bindings/<task-id>.json:/tmp/binding.json \
  --out=<host-runner-out> \
  -- dtc run-binding --binding=/tmp/binding.json --app=/workspace/executable --out=/tmp/hsbb-dtc-run
```

执行语义：

```text
host binding --copy -> container /tmp/binding.json
container hsbb --out -> /tmp/hsbb-dtc-run
runner copy-out -> <host-runner-out>/container-out/...
```

`<host-runner-out>/container-out/.../results.jsonl` 是拷出的证据副本，不是
runtime 互通路径。若结果体积小、结论重要，再复制到 `docs/pb/results/` 留存。

### 11. 评估结果

Codex 替代 LLM 评估时必须回答：

1. archetype 假定是否准确；
2. binding 字段是否由 source/grader/results 支撑；
3. Pass step 是否覆盖了足够多的共性行为面；
4. 相对 source/grader，当前结果能复原多少代码/行为；
5. 下一步是扩 archetype、拆新 archetype、补 binding，还是收敛去下一个任务。

`Pass` 不等于完整项目可用。`Pass` 只表示当前 DTC plan 的 expectation 成立。

### 12. 文档回写

完成一个任务后，必须更新：

- `STATUS.md`: seed、结果路径、结论和下一步；
- `TODO.md`: archetype 状态和剩余缺口；
- `docs/pb/README.md`: 若新增通用流程或重要结果；
- `docs/pb/bindings/<task-id>.json`: binding 样例；
- 必要时更新 `AGENTS.md`，但不要复制 TODO。

## 常见错误

- 只看 `--help` 就写 binding。
- 新增 `dtc run <project>` 命令，而不是走 binding-driven `run-binding`。
- 把项目专项 step 堆进 archetype。
- 因为 `Pass` 就宣称项目完整可用。
- 让 Codex 凭聊天上下文猜参数，而不是跑 `requirements` 并回 source/grader/results。
- 忘记把 binding 用 `--copy=host:container` 放进 PB task container。
