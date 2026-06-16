# 黑盒探测方法学 — distill v1

> **来源**：`cc_jsonl/2026-06-14 ~ 2026-06-16` 的 12 份案例报告
> **用途**：给新 Haskell 黑盒探测 agent 当 embedded reference
> **合法性**：本文档只 distill **如何探测黑盒** 的元方法（probe 技巧、形态判定、idiom 库）。**不**包含任何 PB grader 内部数据（tests.json / summaries.jsonl / archetypes 等）。新 agent 嵌入本文件**不构成作弊**。

---

## 目录

- [0. 元规律（cross-case）](#0)
- [1. 黑盒形态分类（10 类）](#1)
- [2. Detection rules — 怎么判型](#2)
- [3. Plan templates 按形态](#3)
- [4. Idiom 库（34 条）](#4)
- [5. Library fingerprint 反查表](#5)
- [6. Bug-as-contract 复刻原则](#6)
- [7. Self-describe API 大全](#7)
- [8. Output format wire reference](#8)
- [9. Anti-cheating manifest](#9)
- [10. Agent 行为约束](#10)

---

<a id="0"></a>

## 0. 元规律（跨案例确认）

### 0.1 策略选择 — 看文档体量

```
wc -l README* GUIDE* FAQ* *.md *.6 *.1 | tail -1  # 估算文档总量
./probe --help 2>&1 | wc -l                       # 估算 help 长度
```

| 文档 + help 总行数 | 策略 | 案例 |
|---|---|---|
| **≥ 1000** | **landscape-driven**：读完 doc 再开 plan，refinement 通常不需要 | ripgrep (2609), dupl (1288) |
| **200 ~ 1000** | **hybrid**：README 全读 + 1-2 发 probe 再 plan | entr (303), figlet (~600) |
| **< 200** | **discovery-driven**：直接 probe，撞独立子系统 refine plan | chroma (85), bat (21) |

**经验数据**（plan refinement 频率 ∝ 1/文档量）：

```
ripgrep 2609 → 0 refine
dupl    1288 → 0 refine
yj       62  → 0 refine（探测空间天然有限）
chroma   85  → 2 refine
json-tui 71  → 2 refine
```

### 0.2 Plan refinement 触发条件

任一条满足 → 当场 `TodoWrite` 拆 todo（不等到 stage 结束）：

1. 撞见**独立 wire / wire protocol**（entr `-x` awk 子进程、zstd gzip frame、chroma SVG）
2. 撞见**自动创建文件**（entr `~/.entr/status.awk`、dupl 不会，但 chroma 类似）
3. 撞见**新一类渲染规则**（json-tui collapse depth、chroma color-per-type）
4. 撞见 ≥ 3 个**新概念 / 子机制**集中在一个 todo 里
5. 撞见**多个变体的 formatter family**（chroma 5 个 terminal、zstd gzip vs zstd）

### 0.3 0 TodoWrite 的合理情形

短 session + 小表面 + 单一模式 → 直接 free-form。判定：

```
expected_session_duration < 15 min
  AND surface_size < 15 flags
  AND no_mode_switching
→ SKIP TodoWrite
```

唯一案例：errcheck（silent + 9 min + 12 flag）。其它 11 道都用了 plan tracking。

### 0.4 Bug-as-contract 是普适规律

**12 道里 7 道遇到 doc-vs-probe 不一致 / reference bug**：

| 案例 | bug 形态 |
|---|---|
| cmatrix | `-f` 单跑 segfault (exit 139) |
| entr | `ENTR_RESTART_SIGNAL` 拒绝所有值（含空槽 `<>`） |
| yj | `-k` + JSON 输入 → Go reflect crash |
| zstd | `--format=xz/lz4` 文档说支持，实际 reject |
| chroma | swapoff 默认 style 实际打不开 |
| dupl | `-t 0` / `-t -5` 不验证、产出爆炸 |
| figlet | `-w 0` / `-w -5` 不验证 fallback；`-foo` getopt 吃 → `-f oo` |

**复刻原则**：reference 二进制的所有可观察 bug **必须 byte-faithful 复刻**。reimplementation 不能"修"，因为 grader 测的是 reference 行为。

**判定 "这是 bug 不是 feature"**：
- 输入合法但产生 exit ≥ 128（信号）
- doc 写支持但实际拒绝
- 错误信息含空槽 / 拼错（`sytactic` 而非 `syntactic`）
- 越界值不验证默默接受

→ 全部按字面复刻。

### 0.5 Doc trust hierarchy

```
probe output  >  -h / --help output  >  man page  >  README
```

任一冲突时，**下游胜上游**。具体规则：

- README/help 说"支持 X"，probe 跑不通 → 按 probe 实测
- README 列 flag A，help 没列 → 按 help（probe 验证）
- man page 说默认值 V，`-I 2` / 等价查询返回 W → 按查询接口

12 道里至少 5 道（cmatrix 7 处差异、yj quoting、zstd format=xz、chroma swapoff、json-tui `-key`）出现 README 错。

### 0.6 Asset 容器化的常态

PB cleanroom 镜像里**编译期硬编码的默认路径常常不存在**：
- figlet `-I 2` = `/usr/local/share/figlet`（容器无此目录）
- 类似情况：cache dir / config dir / temp dir

reimpl 必须：
- 自我描述接口返回**字面字符串**（不需要保证路径有效）
- 默认行为（不带路径 flag）**复刻失败**

---

<a id="1"></a>

## 1. 黑盒形态分类（10 类）

每种形态 = 一种 plan template + 一组主推 idiom。形态轴**正交于** PB 老 archetype（ByteExact/CliSurface/...），按"探测策略"切分。

| ID | 形态 | 探测空间维度 | 代表案例 |
|---|---|---|---|
| **F1** | Pure stdin → stdout 函数 | 1D | shellharden, errcheck, yj 单 mode |
| **F2** | Stateful daemon + 异步事件 | 1D + time | entr |
| **F3** | TUI ncurses-locked（不可探） | 0D | cmatrix |
| **F4** | TUI stdout-emitting（可探） | 1D + ANSI | json-tui |
| **F5** | HTTP client / 网络客户端 | 1.5D + reflect target | bat |
| **F6** | Silent static analyzer（"无输出 = clean"） | "0D"（必须倒探） | errcheck |
| **F7** | Format converter（N×N input × output） | 2D | yj |
| **F8** | Binary byte-exact | 1D + byte-level | zstd |
| **F9** | Multi-stage pipeline | 3 阶段串联 | chroma |
| **F10** | Large flag space + 厚文档 | 1D × 30+ flag | ripgrep |
| **F11** | Structured LinterDiagnostic | 1D + 3 output modes | dupl |
| **F12** | Asset-dependent renderer | 1D + 外部资产矩阵 | figlet |

（实际 12 种，标 F1–F12 便于代码引用。F3 与 F4 经常合并讨论但探测路径**完全不同**，必须区分。）

---

<a id="2"></a>

## 2. Detection rules — 怎么判型

**头 1-3 个 probe 决定后续走哪条路径**。判定顺序（从特异到通用）：

### 2.1 Asset-dependent 检测（最先）

```
ls <task_dir>/{assets,fonts,data,templates,dict,examples}/ 2>/dev/null

if 任一目录存在 + 含 ≥ 5 个非文档文件:
    → F12 asset-dependent
    第一发 probe 不带 flag，验证默认行为是否失败
```

### 2.2 TUI 检测（第二）

```
echo "x" | ./probe                              # 简单输入
out=$(./probe 2>/dev/null)                      # 拿 stdout
err=$(./probe 2>&1 1>/dev/null)                 # 拿 stderr

if "unable to get terminal" / "Error opening terminal" in err:
    → F3 TUI ncurses-locked
elif "\x1b" in out (含控制字节):
    → F4 TUI stdout-emitting
```

### 2.3 Binary output 检测

```
./probe <reasonable_input> 2>/dev/null | xxd | head -2

if 输出 byte 中含 ≥ 30% 非 ASCII printable:
    → F8 binary byte-exact
```

### 2.4 Silent 检测

```
./probe                                         # 无参
./probe <plausible_input>                       # 合理输入
./probe <pattern_input>                         # 模式输入

if 三次都 stdout/stderr 全空 + EXIT=0:
    → F6 silent → 倒探（故意造错误）
```

### 2.5 网络 client 检测

```
grep -iE "http|url|request|fetch" --help 2>/dev/null | head

if help 含 URL/HTTP 关键字:
    → F5 HTTP client → 容器内搭 echo server 当 reflect target
```

### 2.6 多阶段 pipeline 检测

```
./probe --help | grep -cE "^\s*-l |^\s*-s |^\s*-f |^\s*--lexer|--style|--formatter"

if 找到 ≥ 3 个"选择类" flag:
    → F9 multi-stage pipeline
    立刻找 intermediate dump 接口（-f tokens 类）
```

### 2.7 大 flag 空间检测

```
flag_count=$(./probe --help 2>&1 | grep -cE "^\s*-")
doc_lines=$(wc -l README* GUIDE* FAQ* *.md 2>/dev/null | tail -1 | awk '{print $1}')

if flag_count >= 20 AND doc_lines >= 1000:
    → F10 厚文档 + large flag space
    landscape-driven，先读全 doc 再开 plan
```

### 2.8 Format converter 检测

```
./probe --help | grep -iE "convert|format|encode|decode|transform"

if help 列出 ≥ 3 个 input/output 格式 + 在 flag 里同时出现:
    → F7 format converter（N×N 探测）
```

### 2.9 LinterDiagnostic 检测

```
./probe . 或 ./probe <some_file>

if 输出含 file:line:col 类格式:
    → F11 structured linter
elif 输出 silent + EXIT=0:
    → F6 silent linter（倒探）
```

### 2.10 Stateful daemon 检测

```
./probe --help | grep -iE "watch|listen|event|trigger|monitor"

if help 提到 watch/listen/event:
    → F2 stateful daemon
    准备 async event trigger idiom
```

### 2.11 Default fallback

如果以上都不匹配 → **F1 pure function**。最常见，最简单。

### 2.12 多形态共存

工具可能同时占多个轴：
- shellharden = F1 + F8（pure func + byte-exact）
- ripgrep = F10 + F11（large flag + structured diagnostic）
- chroma = F9 + F12（pipeline + asset-dependent）

按主导轴选 plan，其它轴按 idiom 补充。

---

<a id="3"></a>

## 3. Plan templates 按形态

每个形态一个 stage 列表。stage 名是 todo content。

### 3.1 F1 Pure function plan

```
1. identity (--version / -h)
2. default_behavior (no args / empty stdin)
3. matching_modes (case / word / line / fixed / invert)
4. input_shape_matrix (stdin / arg / mixed)
5. output_format (line numbers / heading / color)
6. exit_codes
7. edge_cases (empty / unicode / binary input / CRLF)
8. summarize
```

### 3.2 F2 Stateful daemon plan

```
1. identity
2. io_model (stdin/arg/env 三通道)
3. tty_dependency_check (no -n / -q flag 默认报错?)
4. async_event_idiom (sleep N && trigger) & ; wait
5. per_flag_with_state (-r restart, -d dir, etc.)
6. spawn_child_inspection（看是否 fork awk/sh 等）
7. env_vars (docs + DEBUG/VERBOSE/*_TRACE 嗅探)
8. signal_handling (SIGINT / SIGUSR1 if relevant)
9. edge_cases (file 删除 / unstat / signal)
10. summarize_with_known_unknown
```

### 3.3 F3 TUI ncurses-locked plan

```
1. identity (--version / -h)
2. cli_only_probe (flag 解析 / exit code / error format)
3. doc_vs_help_diff (probe -h 字面 vs README 列对比)
4. error_path_inversion (-foo / 缺参 / 坏值)
5. bug_repro_3x (撞见崩溃 3 次确认)
6. summarize + 显式列 TUI unprobeable surface
```

### 3.4 F4 TUI stdout-emitting plan

```
1. identity
2. tui_type_detection (od -c first probe → 含 \x1b → 走 F4)
3. ansi_strip_setup (双层 sed: CSI + DCS)
4. render_matrix (input × format)
5. color_per_type / per_token (固定 input × style 变化)
6. default_state (collapse depth / sort / wrap rules)
7. control_seq_trace (startup / teardown SGR)
8. library_fingerprint (FTXUI / ratatui / blessed / curses)
9. summarize
```

### 3.5 F5 HTTP client plan

```
1. identity
2. find_test_target (容器有 nc / python3?)
3. build_echo_server (Python http.server reflect JSON ~25 行)
4. request_construction_matrix (method / URL / headers / body)
5. ouput_modes (是否 TTY-gated -print 类?)
6. input_syntax (ITEM 解析 / separator)
7. error_format (log-style / file:line)
8. cleanup (pkill echo server)
9. summarize
```

### 3.6 F6 Silent linter plan

```
1. identity (+ --version 失败也 ok)
2. silent_confirm (probe 多种合理输入 → 都 EXIT=0 silent)
3. SKIP TodoWrite (短 session)
4. invert_probe_error_paths:
   - unknown_flag → 拿 CLI library fingerprint
   - missing_arg → 拿 flag 类型
   - bad_value → 拿合法 enum 值
   - bad_regex → 拿哪些 flag 接受 regex
   - nonexistent_input → 拿底层 loader 错误格式
   - leading_dash → 拿路径校验细节
5. exit_code_semantics (0 / 1 / 2 / 124 各自含义)
6. error_message_bucketing (3-5 桶按 prefix / banner / EXIT)
7. summarize + workaround 建议
```

### 3.7 F7 Format converter plan

```
1. identity
2. matrix_axis_discovery (从 help 抽 N 种 input/output 格式)
3. minimal_input_across_all_cells (用 {"a":1} 跑全 N×N + xxd)
4. per_format_edge_cases (歧义类型、特殊浮点、字面值)
5. modifier_flag_compat (-e/-i/-k 等 × 输出格式 兼容矩阵)
6. round_trip_identity (-yy / -jj / 自转探归一化)
7. type_ambiguity_matrix (bool/null/number 字面穷举)
8. quoting_heuristics (字符值域 × 输出 quoting)
9. error_paths_per_format (各 input 喂坏值)
10. library_fingerprint
11. summarize
```

### 3.8 F8 Binary byte-exact plan

```
1. identity
2. binary_detection (xxd 第一发输出，含 \xff 等 → binary)
3. round_trip_equivalence (cmp 必探无损工具)
4. determinism_check (双跑 cmp)
5. matrix_byte_diff (level / flag matrix × xxd)
6. fixed_offset_field_id (file vs stdin 跑同输入 → byte diff = 协议字段)
7. format_variant_compat (--format=X 矩阵 + 真假支持)
8. kat_generation (≥ 1 个 KAT 落档)
9. error_path_format
10. container_workdir_pipeline (docker exec sh -c 多步串)
11. summarize_to_markdown (大 spec 落档)
```

### 3.9 F9 Multi-stage pipeline plan

```
1. identity
2. inventory_via_list (--list 找可配置空间)
3. intermediate_dump_discovery (-f tokens / --ast / --dump)
4. if intermediate exists:
     stage1_isolation (固定 stage 2/3 变化 stage 1 输入)
     stage2_isolation
     stage3_isolation
   else:
     整体黑盒探（-50% 效率）
5. domain_catalogue (多 domain × 至少 1 sample)
6. variant_byte_diff (同 family 不同变体)
7. stage_interaction (跨 stage flag 如 prefix)
8. error_paths
9. library_fingerprint
10. summarize_to_markdown
```

### 3.10 F10 Large flag + 厚文档 plan

```
1. doc_skim_and_landscape (Read README + GUIDE + FAQ + --help 全文)
2. sandbox_basics (exit codes / no-args / unknown flag / regex error)
3. feature_group_1: matching        # 一组 = 一个 bash batch 跑 10 flag
4. feature_group_2: output_formatting
5. feature_group_3: filtering
6. feature_group_4: output_modes
7. feature_group_5: context
8. feature_group_6: edge_cases
9. feature_group_7: error_paths
10. harvest_self_describe (--generate=man / --type-list / 等)
11. summarize_to_markdown
```

### 3.11 F11 Structured linter plan

```
1. identity_and_inventory
2. find_test_inputs:
   - Tier 1: 扫容器现成源 (/usr/local/go/src, /usr/share/doc 等)
   - Tier 2: synthetic via /dev/stdin
3. default_output_format (text wire byte-level)
4. alternative_output_modes (-plumbing / -json / -html)
5. output_mode_mutual_exclusivity (2-组合 flag 互斥性)
6. threshold_or_config_matrix (数值边界: 小/大/负/0/非数字)
7. synthetic_delta_matrix (rename / literal / op / structure / type)
8. stderr_stdout_routing
9. edge_cases
10. summarize
```

### 3.12 F12 Asset-dependent plan

```
1. list_task_dir_assets (ls assets/ fonts/ data/ templates/)
2. probe_default_behavior (./probe 不带 flag → 多半失败)
3. find_required_path_flag (-d / --asset-dir / --font-path)
4. infocode/list_enumeration (-I N 矩阵 / --list-X)
5. asset_format_matrix (.flf/.flc/.tlf 各种)
6. layout_or_render_matrix
7. control_files_or_modifier_flags
8. getopt_old_quirks (-foo / option-after-msg / -h)
9. stream_routing
10. summarize (写到 /tmp，**不**写进 task dir)
```

---

<a id="4"></a>

## 4. Idiom 库（34 条）

每条 idiom = `(条件 → bash 模板 → 用途)`。Agent 在每步 plan 时按条件选用。

### 4.1 通用基础（无条件可用）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 1 | exit_capture | `{cmd}; echo "EXIT=$?"` | 抓 exit code，必加 |
| 2 | stream_split | `{cmd} 2>/tmp/err 1>/tmp/out` | 确认错误走哪个 stream |
| 3 | visible_bytes | `{cmd} \| cat -v` (host) / `{cmd} \| od -c` (容器) | 揭示不可见字节 |
| 4 | set_x_loop | `set -x; for x in ...; do ...; done` | 循环输入自动标注 |
| 5 | safe_printf | `printf '%s\n' "$x"` 替代 `echo` | 跨 shell 安全 |
| 6 | empty_literalize | `out=$({cmd}); echo "out='$out'"` | 把"空"字面化 |

### 4.2 状态 / 异步（F2 daemon）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 7 | async_trigger | `( sleep N && {trigger} ) & ; {probe}; wait` | 异步事件 idiom |
| 8 | timeout_124_as_signal | `EXIT=124 ≠ 失败`，对 reactive 工具是"还在监听" | 状态机正常信号 |
| 9 | container_redirect | `docker exec <ctr> bash -c '{cmd} 2>/tmp/err 1>/tmp/out; cat /tmp/out; cat /tmp/err'` | 绕过 probe wrapper 流失真 |
| 10 | proc_scan_no_pgrep | `for p in /proc/[0-9]*/comm; do echo $(basename $(dirname $p)) $(cat $p); done \| grep <name>` | busybox fallback 找 pid |
| 11 | env_matrix | `for v in TERM SIGUSR1 15 usr1; do {cmd_with_env=$v}; done` | 环境变量批量探 |
| 12 | debug_env_sniff | `for var in DEBUG VERBOSE *_TRACE *_DEBUG; do {cmd_with_$var=1}; done` | 嗅探隐藏 debug var |

### 4.3 字节 / 字符级（F3-4, F8）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 13 | repeat_2x_const_check | `out1=$({cmd}); out2=$({cmd}); [ "$out1" = "$out2" ]` | 检测编译期 literal vs 运行时戳 |
| 14 | ansi_csi_strip | `... \| sed 's/\x1b\[[0-9;]*m//g'` | 单层剥色看文本语义 |
| 15 | ansi_csi_dcs_strip | `... \| sed -E 's/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\x1bP[^\x1b]*\x1b\\\\//g'` | 双层剥 CSI + DCS |
| 16 | row_width_quant | `... \| awk '{printf "[%d] >%s<\n", length($0), $0}'` | 量化行宽探对齐规则 |

### 4.4 Silent 倒探（F6）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 17 | error_path_inversion | `./probe -<bad>; ./probe -<known> 缺参; ./probe -<enum>=bogus` | 故意制造错误反推 CLI 表面 |
| 18 | silent_exit_semantics | 0=silent acceptance / 1=found / 2=usage / 124=timeout（or actually working） | silent 黑盒 EXIT 主信号 |

### 4.5 矩阵 / 对照（F1, F7, F12）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 19 | minimal_input_cross_cells | `for in_f in ...; for out_f in ...; do {probe -${in_f}${out_f}} \| xxd; done` | 同 input 跨 N×N cell + byte diff |
| 20 | round_trip_identity | `./probe -${fmt}${fmt} <<< '{value}'` | 探归一化 drift（非保真行为） |
| 21 | type_ambiguity_for | `for v in {bool_variants}; do echo "$v -> $({cmd} <<<\"a: $v\")"; done` | 类型字面值域穷举 |

### 4.6 Binary byte-exact（F8）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 22 | binary_visualize | host: `xxd`；容器: `od -An -t x1` | binary 强制 byte 可视化 |
| 23 | cmp_round_trip | `cmp <orig> <decoded> && echo "roundtrip OK"` | 无损工具 byte-exact 等价 |
| 24 | determinism_2x | `./probe x -o A; ./probe x -o B; cmp -s A B && echo "deterministic"` | 双跑测确定性 |
| 25 | kat_record | 最简输入 + 默认 flag → 记 hex 序列作 reimpl 回归 test | Known-Answer Test 落档 |

### 4.7 Pipeline 拆解（F9）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 26 | intermediate_dump_discovery | 试 `-f tokens` / `--ast` / `--dump-ir` / `--print-stage=N` / `--trace` | 找中间产物接口 |
| 27 | list_enumeration | `--list` / `--list-lexers` / `--list-styles` / `--type-list` / `--show-all` | 枚举可配置单元 |

### 4.8 大空间 + 自我描述（F10）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 28 | pipeline_exit_pitfall | `set -o pipefail` 或 `${PIPESTATUS[0]}` 或独立运行捕获 | pipeline 改变 exit code 的坑 |
| 29 | self_describe_harvest | `--generate=man` / `--generate=complete-bash` / `--show-default` / `--print-defaults` | 工具自带文档 |

### 4.9 容器 / 文件系统（F11）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 30 | container_data_scan | `for d in /workspace /usr/local/<lang>/src /usr/share/doc /etc /var/log; do ./probe -v $d 2>&1; done` | 找容器自带的测试数据 |
| 31 | stdin_as_path | `printf '<content>' \| ./probe [flags] /dev/stdin` | 工具只收路径不收 stdin 数据时 |
| 32 | controlled_delta_synthetic | 造一对 `(base, delta)` 测算法 normalization | 反推静态分析器规则 |

### 4.10 Asset 依赖（F12）

| # | 名字 | bash 模板 | 用途 |
|---|---|---|---|
| 33 | task_dir_asset_ls | `ls <task_dir>/{assets,fonts,data,templates,dict}/` | 第一发看资产清单 |
| 34 | literal_default_value | 工具自报默认值（-I 2 / --print-defaults）按**字符串**对待，**不**验证 | reimpl 字面复刻 |

---

<a id="5"></a>

## 5. Library fingerprint 反查表

错误字符串 / 输出形状 → 反查底层库 → reimpl 直接复用 → byte-exact 复刻成本骤降。

### 5.1 JSON / YAML / TOML / HCL parser

| 错误格式 | 库 |
|---|---|
| `[json.exception.parse_error.101] parse error at line X, column Y` | **nlohmann/json**（C++） |
| `Error parsing JSON: invalid character 'X' looking for ...` | **encoding/json**（Go std） |
| `toml: line N (...): expected value but found '\n' instead` | **BurntSushi/toml**（Go） |
| `yaml: <line N>: <msg>` | **gopkg.in/yaml.v2**（Go） |
| `Error parsing HCL: expected: STRING got: LBRACE` | **HashiCorp hcl**（Go） |
| `Error writing YAML: reflect: call of reflect.Value.Set on zero Value` | yaml.v2 + `interface{}` reflect 滥用 |

### 5.2 TUI / 渲染库

| 信号 | 库 |
|---|---|
| `\eP$q q\e\\`（DECRQSS）+ mouse tracking `[?1000h [?1003h [?1015h [?1006h` + box-drawing | **FTXUI**（C++，Arthur Sonzogni） |
| `\e[?1049h` 备用屏切换 + `\e[?25l` 隐光标 | 任何 alt-buffer TUI |
| ncurses init fail: `Error opening terminal: unknown.` | **ncurses**（必须 `TERM` env 或 termcap DB） |
| 标志性渲染 ANSI 256 / truecolor `\e[38;5;N` / `\e[38;2;R;G;B` | terminal16m / 不限库 |

### 5.3 CLI parser

| 错误 / 形态 | 库 |
|---|---|
| `flag provided but not defined: -X` + `Usage of <binary>:` | **Go flag**（std） |
| `flag needs an argument: -X` | Go flag |
| `invalid value "X" for flag -Y: parse error` | Go flag |
| `error: unexpected argument '--X' found` | **Rust clap** |
| `invalid arguments` + synopsis `<cmd> {OPTIONS} [file]` | **args by Taywee**（C++） |
| `Incorrect parameter: <X>` + short usage | zstd-style |
| getopt 风格 `cklnoprstvxDELNRSWX` 单字母集 + `-foo` → `-f oo` | **POSIX getopt**（1980s C） |
| `Usage: cmd [flags]` + cobra-style `Available Commands:` | **cobra**（Go） |

### 5.4 Hash / 校验 / 压缩

| 信号 | 库 |
|---|---|
| `Check: XXH64 <hex>` | **xxHash**（zstd 集成） |
| 压缩流 magic `28 b5 2f fd` | **Zstandard**（zstd 自家） |
| 压缩流 magic `1f 8b 08 00 ...` + OS byte | **gzip / zlib** |
| 压缩流 magic `fd 37 7a 58 5a 00` | **xz / liblzma** |
| 压缩流 magic `04 22 4d 18` | **LZ4** |

### 5.5 Logging / time

| 格式 | 库 |
|---|---|
| `2026/06/14 09:00:28 <msg>` | **Go std log**（默认格式） |
| `<file>.go:<line>:` 嵌入 error | Go log + runtime.Caller |
| `[2026-06-14T10:00:00Z] level=INFO msg=...` | structured logging (logrus / slog) |
| `Mon, 15 Jun 2026 11:09:28 GMT` | HTTP date (BaseHTTPServer 风格) |

### 5.6 Static analysis / dupl-style

| 信号 | 库 / 算法 |
|---|---|
| suffix tree + token normalization | **dupl / PMD / CCFinder** 算法族 |
| AST node 序列 + identifier IDENT / literal LIT 匿名化 | 标准 clone detection |
| `<file>:<line>:<col>: <severity>: <msg>` | **gcc / clang / Go vet** 风格 |

### 5.7 网络 / HTTP

| 信号 | 库 |
|---|---|
| `User-Agent: curl/<version>` | curl |
| `User-Agent: bat/0.1.0` 类自定义 | 不是 curl，自家 HTTP 客户端 |
| `Server: BaseHTTP/0.6 Python/3.10.12` | Python `http.server` |
| `Server: ...` 含 nginx / apache / gunicorn | 对应库 |

---

<a id="6"></a>

## 6. Bug-as-contract 复刻原则

12 道 corpus 里 7 道遇到 reference bug。统一处理原则：

### 6.1 判定"这是 bug 不是 feature"

任一条满足 → 当作 bug，**复刻**：

1. **EXIT ≥ 128**（信号杀死）：cmatrix `-f` segfault → EXIT 139 (SIGSEGV)
2. **doc 写支持但实际拒绝**：zstd `--format=xz` reject、json-tui `-key` long form 不工作
3. **错误信息有空槽 / 拼错**：entr `<>` 空槽、shellharden `sytactic` 拼写、yj `reflect: call of reflect.Value.Set on zero Value`
4. **越界值不验证默默接受**：dupl `-t 0` / `-t -5` 不报错、figlet `-w -5` 不报错
5. **默认值字符串与实际状态不符**：figlet `-I 2` = `/usr/local/share/figlet`（容器无）

### 6.2 复刻策略

| Bug 类型 | 复刻怎么做 |
|---|---|
| Segfault | reimpl 在等价输入处 `kill(getpid(), SIGSEGV)` 或 ` abort()` |
| Doc 假支持 | reimpl 拒绝该 flag，error 字面复刻 |
| 拼错字符串 | reimpl error message 必须 byte-exact 复刻拼错 |
| 不验证越界 | reimpl 也不验证，fallback 到默认或产生爆炸输出（按观察） |
| 字面默认值 | reimpl 自我描述接口返回同字符串，不验证 |

### 6.3 KAT（Known-Answer Test）作 reimpl 回归 test

byte-exact 工具必须落 ≥ 1 个 KAT：

```
# 模板
input: <最简输入>
flags: <默认或具体>
expected_output: <byte 序列 hex>
exit_code: 0
```

zstd 案例：
```
echo "hello world" > kat.txt
executable kat.txt -o kat.zst -f
# expected kat.zst = 28 b5 2f fd 24 0c 61 00 00 68 65 6c 6c 6f 20 77 6f 72 6c 64 0a 8c 6d 7d 20
```

cmatrix 案例：
```
executable -V
# expected stdout = " CMatrix version 2.0 (compiled 19:59:42, Apr 17 2026)\nEmail: ...\n"
```

---

<a id="7"></a>

## 7. Self-describe API 大全

工具自带的"inventory / 文档生成"接口 = 免费的 reimpl spec。优先级 try：

```
# 枚举可配置单元
--list / --list-all / --list-X / -L

# 类型 / 格式
--type-list / --list-formats / --list-codecs / --supported

# 默认值查询
--show-defaults / --print-defaults / --defaults
-I N（infocode 风格）

# 文档生成
--generate=man / --generate=html / --generate=json-schema
--generate complete-bash / -zsh / -fish
--help-all / --long-help

# 调试 / 内部状态
--trace / --debug / --verbose
*_TRACE env / DEBUG=1

# 配置文件路径
--show-config / --config-path
```

每条 try 都可能拿到**结构化 inventory** 或 **完整 man page 源**。

---

<a id="8"></a>

## 8. Output format wire reference

### 8.1 ANSI SGR codes 速查

| 用途 | code | 案例 |
|---|---|---|
| 重置 | `\e[0m` 或 `\e[m` | 所有 |
| 8 色 fg | `\e[30m`–`\e[37m` | shellharden, ripgrep |
| 8 色 bright fg | `\e[90m`–`\e[97m` | json-tui keys |
| 8 色 bg | `\e[40m`–`\e[47m` | shellharden suggest |
| 256-palette | `\e[38;5;Nm` | chroma terminal256 |
| Truecolor | `\e[38;2;R;G;Bm` | chroma terminal16m, shellharden |
| 粗体 | `\e[1m` | ripgrep match |
| 反显 | `\e[7m` | json-tui focused brace |
| 备用屏开 | `\e[?1049h` | TUI（cmatrix / ngrrram） |
| 鼠标 tracking | `\e[?1000h \e[?1003h \e[?1015h \e[?1006h` | FTXUI |
| DECRQSS query cursor | `\eP$q q\e\\` | FTXUI startup |

### 8.2 box-drawing chars (常见)

```
┌ ┐ └ ┘ ─ │ ├ ┤ ┬ ┴ ┼  (轻框)
┏ ┓ ┗ ┛ ━ ┃              (粗框)
╔ ╗ ╚ ╝ ═ ║              (双线)
```

→ 反查 FTXUI / textual / blessed / cli-table 等。

### 8.3 常见 wire format 结构

**JSON event stream**（ripgrep --json / 类似）：
```jsonl
{"type":"begin","data":{"path":{"text":"..."}}}
{"type":"match","data":{...,"absolute_offset":N,"submatches":[...]}}
{"type":"end","data":{...,"stats":{...}}}
{"type":"summary","data":{...}}
```

**字段分隔符约定**：
- match field: `:`（ripgrep / dupl text）
- context field: `-`（ripgrep -A/-B/-C）
- range: `,` vs `-`（dupl text 用 `,`，plumbing 用 `-`）
- 多 context 段间: `--`（ripgrep）

**JSON 缩进 / 紧凑约定**：
- 紧凑：`{"a":1}\n`（yj 默认 / zstd N/A）
- pretty：2 空格缩进（yj `-i`、ripgrep --json）

**HCL 输出特点**：
- 末尾**无换行**（其它 3 格式都有）
- 所有键加双引号 `"k" = v`
- 字段间空一行

---

<a id="9"></a>

## 9. Anti-cheating manifest

### 9.1 合法数据源（绿色）

| 类别 | 数据 | 理由 |
|---|---|---|
| ✅ | 本 distill 文档 | 元方法，跟具体题无关 |
| ✅ | 上游 repo @ pinned commit 的 README / man / CHANGELOG | PB 官方明确允许 "documentation" |
| ✅ | 真实 `./probe` 调用的 stdout/stderr/exit | 黑盒探测本身 |
| ✅ | binary 自己的 `--help` / `--version` / error 信息 | 等同 probe |
| ✅ | 容器内自带的非 grader-private 数据（`/usr/local/go/src` 类） | 操作系统/语言运行时的标准内容 |
| ✅ | 上游 repo `tests/` 原生测试（**不**是 PB grader 的 tests.json） | 公开物 |

### 9.2 禁止数据源（红色）

| 类别 | 数据 | 理由 |
|---|---|---|
| ❌ | `programbench/data/tasks/*/tests.json` | grader 私有测试清单 |
| ❌ | HF `ProgramBench-Tests` tarball 里的 pytest 源码 | 测试答案 |
| ❌ | `distill_out/summaries.jsonl` | 派生自 tests.json |
| ❌ | `distill_out/features.all.jsonl` | 派生自 tests.json |
| ❌ | `distill_out/task_archetypes.jsonl` | ground truth 标签 |
| ❌ | 老 `haskell-tester/data/playbooks/*.md` | 基于 grader 断言反推 |
| ❌ | 老 `haskell-tester/data/archetype_taxonomy.json` | 同上 |
| ❌ | 老 `haskell-tester/data/fewshot_examples.json` | 同上 |

### 9.3 判断标准

> **这条信息是"程序行为本身"还是"grader 怎么测它"？前者合法，后者污染。**

边界情况：
- 上游 `tests/` 目录：合法（这是开发者自己写的测试，不是 grader 的）
- 上游 `.github/workflows/*.yml`：合法（公开 CI 配置）
- PB tests.json 哪怕只是看一眼断言名 → ❌（已污染）
- HF tarball ATTRIBUTION.md：合法（只是出处声明）
- HF tarball 里的 `tests/*.py`：❌（grader 的实际 pytest 实现）

---

<a id="10"></a>

## 10. Agent 行为约束

### 10.1 Probe wrapper 边界

每个 PB 任务环境有 `./probe`，形如：

```bash
#!/bin/bash
timeout 6 docker exec -i pbref-real-<task> /workspace/executable "$@"
```

Agent 跑 `./probe` 时**不能**：
- 改 timeout（容器规定）
- 改 docker exec 参数（除非用 `docker exec -t` 切 PTY，仍属合法）
- 进容器查看 `/workspace/executable` 内容（execute-only）
- 反编译 binary（`strings` / `objdump` / `hexdump` / `nm` 全禁）
- 联网获取上游源码（cleanroom 沙盒规则）

Agent 跑 `./probe` 时**可以**：
- 任意 `--flag` 组合
- pipe 任何 input
- 多次重跑同样 probe
- 解析 stdout / stderr / exit code
- 写文件到 `/tmp/<self>/`（自己的 workdir，不影响容器）
- `docker exec -t` 切 PTY（合法绕开 wrapper）

### 10.2 Summary 落档位置

正确：写到 `/tmp/<probe_name>/REQUIREMENTS.md` 或同等位置
错误：写到 `<task_dir>/NOTES_blackbox.md`（agent reimpl 可能误读，属边界违规）

### 10.3 Plan tracking 决策

```
if (probable_duration > 15 min) OR
   (surface_size > 15 flags) OR
   (multiple_output_wires) OR
   (need_to_track_subsystem_refinement):
    use TodoWrite
else:
    free-form probe
```

### 10.4 Stop 条件

任一触发 → 进 summarize stage：

1. plan 所有 todo completed
2. 连续 3 个 probe 没新事实
3. 已知未知清单完备（physical_unprobeable / observed_but_unresolved 两类）
4. summary 可写出（要素齐：CLI / output / error / exit / bug）

### 10.5 Cleanup 义务

session 起的长期态必须 summary 之前清理：
- 容器内长进程：`pkill -f <name>`
- 临时文件：`rm -f /tmp/<...>`
- 端口绑定：自然解绑（杀进程就好）

### 10.6 KAT 落档（byte-exact 工具）

F8 binary 类必须落 ≥ 1 KAT：

```yaml
case_id: <task>__<scenario>
input: <minimal byte sequence>
flags: [<...>]
expected_stdout_hex: <bytes>
expected_stderr_hex: <bytes>
expected_exit: <N>
notes: <why this is canonical>
```

---

## 附录 A：12 道案例索引

| 案例 | 报告路径 | 主形态 |
|---|---|---|
| shellharden | `cc_jsonl/2026-06-14/anordal__shellharden.6a6ffd4_report.md` | F1 |
| entr | `cc_jsonl/2026-06-14/eradman__entr.8e2e8b4_report.md` | F2 |
| cmatrix | `cc_jsonl/2026-06-15/abishekvashok__cmatrix.5c082c6_report.md` | F3 |
| bat | `cc_jsonl/2026-06-15/astaxie__bat.17d1080_report.md` | F5 |
| json-tui | `cc_jsonl/2026-06-15/arthursonzogni__json-tui.17a22b6_report.md` | F4 |
| errcheck | `cc_jsonl/2026-06-16/kisielk__errcheck.dacab89_report.md` | F6 |
| yj | `cc_jsonl/2026-06-16/sclevine__yj.8016400_report.md` | F7 |
| zstd | `cc_jsonl/2026-06-16/facebook__zstd.1168da0_report.md` | F8 |
| chroma | `cc_jsonl/2026-06-16/alecthomas__chroma.8d04def_report.md` | F9 |
| ripgrep | `cc_jsonl/2026-06-16/burntsushi__ripgrep.3b7fd44_report.md` | F10 |
| dupl | `cc_jsonl/2026-06-16/mibk__dupl.1bf052b_report.md` | F11 |
| figlet | `cc_jsonl/2026-06-16/cmatsuoka__figlet.202a0a8_report.md` | F12 |

## 附录 B：版本与维护

- **v1**: 2026-06-16，distill from 12 cases
- 后续每加 1 道 case → run distill diff pass → append net-new idiom / fingerprint / rule
- 不删旧条目，idiom 库一直净增（token cost 缓慢上升可接受）
- 当 v1.5 / v2 重组时再重新分类
