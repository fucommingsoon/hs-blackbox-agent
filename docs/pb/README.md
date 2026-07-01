# PB Integration Runbook

本文件给新窗口 Codex / 开发者快速恢复 PB 200+ 任务融合工作。先读根目录
`STATUS.md`，再读本文件。

## 目标范围

当前主目标不是只把 `entr` / `bat` 跑通，而是把 Haskell DTC 变成可复用
验证内核，逐步覆盖：

- PB 200+ 任务：优先用公开源码 + PB grader + 真实 reference executable
  反复抽取 archetype flow。
- 外部约 800 个项目：后续按同一套 archetype/binding/runtime 机制接入，不
  为每个项目新增一条 CLI 命令。

`dtc plan/run <name>` 只用于本仓库 regression seed。长期入口应是：

```bash
hsbb dtc system-prepare --corpus=<task-corpus> --out=<packet.json>
hsbb dtc requirements <Archetype>
hsbb dtc validate-binding --binding=<binding.json>
hsbb dtc plan-binding --binding=<binding.json>
hsbb dtc run-binding --binding=<binding.json> --app=<app> --out=<run-dir>
```

当前本地 ProgramBench metadata 中有 201 个 task，完整清单维护在
`tasks.md`。不要再从旁边的历史 AFL 预测文档临时查任务数量；
那些文档只作为历史评估参考。

## 任务材料边界

PB 融合时只把这些视作高价值材料：

- upstream source
- upstream tests
- PB grader/eval tests
- reference executable 的真实运行结果

不要把 `pb-metadata`、旧 `.hsbb`、旧 oracle/confidence/distill 产物当作新
DTC 的输入事实。PB task README/SPEC 可以作为初始公开文档，但不是 seed
truth；优先回到 source/grader/results。

## 同容器执行方案

PB reference probe 通常长这样：

```bash
timeout 6 docker exec -i pbref-real-<task> /workspace/executable "$@"
```

这类 wrapper 适合简单 argv/stdin/stdout 探测，但不适合当前 DTC：

- watcher 类 flow 需要 `hsbb` 创建的 `${WORK}` 文件被黑盒看见。
- HTTP client 类 flow 需要黑盒访问 `hsbb` 启动的本地 HTTP fixture。
- 现有 `pbref-real-*` 容器常是 `NetworkMode=none` 且没有 host mount。

因此当前标准测试方案是：把 Linux 版 `hsbb` 放进和
`/workspace/executable` 相同的 PB task 容器里执行。这样 fixture、trigger、
runtime、黑盒共享同一个文件系统和网络视角；不要把 bridge 问题混进业务
flow 评估。

### 标准入口

优先使用脚本，不要手工拼接 runner 容器命令：

```bash
scripts/pb-dtc-runner.sh --task=<owner__repo.commit> --mode=app -- --help
scripts/pb-dtc-runner.sh --task=<owner__repo.commit> -- \
  dtc run-binding --binding=/tmp/binding.json --app=/workspace/executable --out=/tmp/hsbb-dtc-run
```

脚本做三件事：

- 按 `owner__repo.commit` 推断 image：
  `programbench/<owner>_1776_<repo>.<commit>:task`。
- 复用 `/private/tmp/hsbb-linux-amd64`；缺失或传 `--build-hsbb` 时，复用
  `hsbb-pb-builder` 编译 Linux amd64 版 `hsbb`。
- 创建一次性 PB task container，注入 `hsbb`，运行 `/workspace/executable`
  或 `hsbb ...`，并把 stdout/stderr/exit code 和 DTC output 拷回 host。

示例：

```bash
scripts/pb-dtc-runner.sh --build-hsbb \
  --task=ariga__atlas.6d81150 \
  --mode=app \
  --out=/private/tmp/hsbb-pb-atlas-help \
  -- --help
```

`hsbb` 模式下，`--` 后面是传给容器内 `hsbb` 的参数：

```bash
scripts/pb-dtc-runner.sh \
  --task=eradman__entr.8e2e8b4 \
  --out=/private/tmp/hsbb-pb-entr \
  -- dtc run entr --app=/workspace/executable --out=/tmp/hsbb-dtc-run
```

如果 `run-binding` 需要 host 上的 binding 文件，用 `--copy=host:container` 显式
声明路径，不要临时手写 `docker cp`：

```bash
scripts/pb-dtc-runner.sh \
  --task=ariga__atlas.6d81150 \
  --copy=docs/pb/bindings/ariga__atlas.6d81150.json:/tmp/atlas-binding.json \
  --out=/private/tmp/hsbb-pb-atlas-dtc \
  -- dtc run-binding --binding=/tmp/atlas-binding.json --app=/workspace/executable --out=/tmp/hsbb-dtc-run
```

结果目录中固定包含：

- `runner.env`
- `stdout.txt`
- `stderr.txt`
- `exit_code`
- `container-out/`，仅当容器内 `--container-out` 路径存在时写出。

当前 Codex 人工替代 LLM 抽取的 atlas binding 样例在
`docs/pb/bindings/ariga__atlas.6d81150.json`。后续 DeepSeek 节点接入时，应
产出同构 JSON，并通过 `dtc validate-binding` / `dtc plan-binding` 验证。

### 手工编译 Linux hsbb

本机 macOS 产物是 Mach-O，不能直接进 Linux 容器。可以用 PB task image
起一个 builder 容器，在容器内装 ghcup/GHC/Cabal 并编译 Linux amd64 版
`hsbb`。这套流程已被 `scripts/pb-dtc-runner.sh --build-hsbb` 包装；下面命令
只作为排障参考：

```bash
docker rm -f hsbb-pb-builder >/dev/null 2>&1 || true
docker run -d --platform linux/amd64 \
  --name hsbb-pb-builder \
  -v /Users/kangxin/Documents/workspace/konceptosv18/hs-blackbox-agent:/hostrepo:ro \
  programbench/eradman_1776_entr.8e2e8b4:task \
  sleep infinity

docker exec hsbb-pb-builder sh -lc '
  apt-get update &&
  apt-get install -y curl ca-certificates build-essential libffi-dev libgmp-dev zlib1g-dev xz-utils git pkg-config python3
'

docker exec hsbb-pb-builder sh -lc '
  export BOOTSTRAP_HASKELL_NONINTERACTIVE=1
  export BOOTSTRAP_HASKELL_INSTALL_STACK=0
  export BOOTSTRAP_HASKELL_ADJUST_BASHRC=P
  export BOOTSTRAP_HASKELL_GHC_VERSION=9.6.7
  export BOOTSTRAP_HASKELL_CABAL_VERSION=3.12.1.0
  curl --proto "=https" --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
'

docker exec hsbb-pb-builder sh -lc '
  rm -rf /tmp/hsbb-src &&
  mkdir -p /tmp/hsbb-src &&
  cd /hostrepo &&
  tar --exclude=.git --exclude=dist-newstyle -cf - . | tar -C /tmp/hsbb-src -xf - &&
  cd /tmp/hsbb-src &&
  /root/.ghcup/bin/cabal build --with-compiler=/root/.ghcup/bin/ghc-9.6.7
'

docker cp \
  hsbb-pb-builder:/tmp/hsbb-src/dist-newstyle/build/x86_64-linux/ghc-9.6.7/hs-blackbox-agent-0.1.0.0/x/hsbb/build/hsbb/hsbb \
  /private/tmp/hsbb-linux-amd64
```

说明：

- 第一次装 GHC/Cabal 很慢，尤其 Apple Silicon 上跑 `linux/amd64` 容器。
- `cabal: Ticker: poll failed: Interrupted system call` 在该环境里是噪音；
  只要构建继续推进即可。
- 后续复用 builder 容器和 cabal cache，会快很多。

### 在 PB task 容器中运行

以 `entr` / `bat` 为例：

```bash
docker rm -f hsbb-pb-entr-runner hsbb-pb-bat-runner >/dev/null 2>&1 || true

docker run -d --platform linux/amd64 \
  --name hsbb-pb-entr-runner \
  programbench/eradman_1776_entr.8e2e8b4:task \
  sleep infinity

docker run -d --platform linux/amd64 \
  --name hsbb-pb-bat-runner \
  programbench/astaxie_1776_bat.17d1080:task \
  sleep infinity

docker cp /private/tmp/hsbb-linux-amd64 hsbb-pb-entr-runner:/usr/local/bin/hsbb
docker cp /private/tmp/hsbb-linux-amd64 hsbb-pb-bat-runner:/usr/local/bin/hsbb
docker exec hsbb-pb-entr-runner chmod +x /usr/local/bin/hsbb
docker exec hsbb-pb-bat-runner chmod +x /usr/local/bin/hsbb

docker exec hsbb-pb-entr-runner sh -lc \
  'hsbb dtc run entr --app=/workspace/executable --out=/tmp/hsbb-dtc-entr'

docker exec hsbb-pb-bat-runner sh -lc \
  'hsbb dtc run bat --app=/workspace/executable --out=/tmp/hsbb-dtc-bat'

docker cp hsbb-pb-entr-runner:/tmp/hsbb-dtc-entr /private/tmp/hsbb-dtc-in-docker-entr
docker cp hsbb-pb-bat-runner:/tmp/hsbb-dtc-bat /private/tmp/hsbb-dtc-in-docker-bat
```

## 已验证结果

最近一次同容器真实运行结果：

- `entr`: `9/9 Pass`
  - 结果：`/private/tmp/hsbb-dtc-in-docker-entr/entr/20260701-061958-628670417000/results.jsonl`
  - 覆盖：参数错误、stdin watch list、缺失文件、空输入、子进程 stdout、
    子进程 exit code、文件变更 trigger、evidence-stop、`/_` 替换、目录变更。
- `bat`: `11/11 Pass`
  - 结果：`/private/tmp/hsbb-dtc-in-docker-bat/bat/20260701-062001-112626085000/results.jsonl`
  - 覆盖：help、basic GET、default GET、default POST、query/header items、
    PUT JSON items、form body、raw body、non-2xx body、pretty=false JSON rendering。

这两个结果支撑当前判断：`entr` / `bat` 两个 archetype seed 已经达到可支撑
60-70% 等价行为实现复原的密度。这里说的是可观察业务行为和关键实现约束，
不是逐行源码结构。

## 下一步融合策略

1. 继续选 PB 任务时，先看 `tasks.md`，再优先选能代表新 archetype
   或能补齐现有 archetype 缺口
   的项目，不要只挑容易加分的单点。
2. 每个新项目先判断 coarse archetype，再跑 `requirements` 让 Haskell 给出
   binding 字段需求。
3. LLM/Codex 只能根据 `system-prepare` 的机械读取包生成 binding/评估结果，
   不能凭空猜参数。
4. 对 binding 缺失字段，优先回到 source/grader/results 增补证据；不要用
   旧 confidence/oracle loop。
5. 当一个项目暴露出可复用行为面，优先扩 `Archetype.*` flow builder；项目
   catalog 只填差异绑定。
6. `bat` 类 HTTP client 下一步应补 request artifact index，让结果文件能复盘
   fixture 实际收到的 path/header/body。
