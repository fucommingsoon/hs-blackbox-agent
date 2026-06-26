# AGENTS.md

给 agent / 开发者的操作手册。不重复 README/FLOW/SHAPES 的架构描述，只补"怎么干活"。

## 构建

必须用 ghcup 的 GHC 9.6.7，Homebrew 的 GHC 9.14.x 有 ffi.h 兼容问题会编译失败：

```bash
cd /Users/kangxin/Documents/workspace/konceptosv18/hs-blackbox-agent
/Users/kangxin/.ghcup/bin/cabal build --with-compiler=/Users/kangxin/.ghcup/bin/ghc-9.6.7 2>&1 | tail -10
```

二进制路径：

```bash
BIN=$(find dist-newstyle -name hsbb -type f -perm +111 | head -1)
```

环境变量：`DEEPSEEK_API_KEY` 必须在环境中。沙箱默认阻断 DNS，step-snap / loop 需要 `require_escalated`。

## 调试流程：step-snap

这个项目的核心开发循环是"改 prompt → 在 step 副本上验证 → 确认不退步 → 推进"。step-snap 模式让每一步可观测、可回滚。

```bash
# 1. 从 pb28easy 复制一个任务到 tests/ 下作为 step_0
cp -R ../pb28easy/eradman__entr.8e2e8b4 tests/entr-snap/step_0

# 2. 逐步推进，每次 cp 上一步 → 跑一步
DEEPSEEK_API_KEY=... $BIN step-snap tests/entr-snap

# 3. 检查产物
#    oracle.yaml — 7 槽 confidence + content
#    probes.jsonl — 每发 probe 的全量 stdout/stderr
#    trace.jsonl — LLM 请求/响应/工具调用全量事件流
```

改了 prompt 后：删掉受影响的 step_N 副本，从更早的 step 重新跑，在相同输入下对比 LLM 行为变化。tests/ 已 gitignore，不进版本控制。

**读 trace 的方式**：trace.jsonl 每行一个 JSON 事件。关键 type：`llm_request`（含完整 prompt + messages）、`llm_response`（含 content + tool_calls）、`tool_dispatch_start`（含 writeSlot 参数）、`gate_heuristic`（含各槽 confidence）。用 `python3 -c` + `json.loads` 逐行解析比直接 cat 可读得多。

## 测试目录

- `../pb28easy/` — 28 个简单 ProgramBench 任务（黑盒探测目标），每个子目录含 README/SPEC/man/probe
- `../pb120medium/` — 120 个中等难度任务
- `tests/` — 本地 step-snap 副本，已 gitignore，删了重来不心疼

从 pb 目录复制任务到 tests/ 开始调试，不要直接在 pb 目录上跑。

## Docker 桥接

PB task 的 `./probe` 是 docker exec wrapper，形如：

```
timeout 6 docker exec -i <container> /workspace/executable "$@"
```

harness 检测到 wrapper 后会重写 cmd：把 `./probe` 替换为容器内 binary 路径，整条 cmd 用 `docker exec <c> bash -c '<rewritten>'` 进容器跑，容器内 `timeout 5` 防卡，host 侧再包 30s 兜底。

关键点：fixture 路径（`/tmp/xxx`）在 host 和 container 里是同一个 `/tmp`——Docker 共享了 tmp。所以 LLM 写 `touch /tmp/test` 在 host 跑还是 container 跑都能被 entr 看到。但只有含 `./probe` 的 cmd 会进容器，纯 host 操作（`grep`/`ls`）留在 host shell。

## 当前优化焦点

confidence 增量语义是当前最核心的调优点。问题本质：integration LLM 倾向于"probe 成功了就给所有目标槽加分"，而不是"只给真正获得新事实的槽加分"。这会导致已验证槽被反复刷分，gate 虚假提前收敛。

具体机制和 TODO 状态见 TODO.md。不在这里重复，避免文档跟代码脱节。

## 文档分工

| 文件 | 给谁 | 写什么 |
|---|---|---|
| README.md | 想理解项目的人 | 系统概览、五阶段、持久层、子命令、关键机制 |
| FLOW.md | 想看流程的人 | mermaid 流程图、阶段细节、设计决策 |
| SHAPES.md | 改代码的人 | 数据 shape、Oracle API、各阶段 I/O |
| AGENTS.md | 动手干活的人/agent | 构建、调试、测试、当前焦点 |
| TODO.md | 所有人 | 已知问题 + 方案 + 优先级 |
