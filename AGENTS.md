# AGENTS.md

给 agent / 开发者的操作手册。不重复 README/FLOW 的架构描述，只补怎么干活。

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

优先修改 `src/Blackbox/DTC.hs` 及后续 DTC runtime 模块。默认命令：

```bash
$BIN dtc plan entr
$BIN dtc plan bat
$BIN dtc flow
```

DTC 计划语言里目标程序统一写 `app 参数1 参数2 ...`。不要在 DTC plan 里使用 `./probe` 作为抽象。

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

1. 实现 DTC runtime：HTTP fixture、result JSONL、fixture workspace isolation。
2. 从 `entr` 和 `bat` 的 source/grader 中提取更多 flow archetype。
3. 增加 result JSONL、fixture 工作目录隔离和 structured command。

不要继续调旧 confidence / gate prompt。
