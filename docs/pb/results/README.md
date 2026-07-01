# PB DTC Result Evidence

本目录保存小体积、可复核的 DTC `results.jsonl` 快照。这里只放 reference
executable 的精简 step 结果，不放完整容器输出、构建产物或大 artifact。
runner/host/container 路径语义见 `docs/pb/README.md`。

这些结果只能证明对应 DTC plan 的 expectation 成立，不证明项目完整可用，也不
证明 PB grader 完整覆盖。

| Task | Archetype | Result | Source Run Note |
|---|---|---|---|
| `eradman__entr.8e2e8b4` | `WatcherCli` | `entr-20260701-061958-results.jsonl` | copied from a same-container PB run |
| `astaxie__bat.17d1080` | `HttpClientCli` | `bat-20260701-080127-results.jsonl` | copied from a same-container PB run |
| `ariga__atlas.6d81150` | `StructuredSubcommandCli` | `atlas-20260701-083041-results.jsonl` | copied from a same-container PB run |
| `wfxr__csview.8ac4de0` | `TabularRenderCli` | `csview-20260701-114812-results.jsonl` | copied from a same-container PB run |

新窗口复核时优先看本目录，再结合：

- `STATUS.md`
- `docs/pb/README.md`
- `docs/pb/codex-llm-runbook.md`
- `docs/pb/bindings/*.json`
