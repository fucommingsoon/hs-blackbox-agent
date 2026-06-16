# hs-blackbox-agent

Haskell-native black-box probe agent for ProgramBench (PB) tasks.

Produces `belief.md` per task by probing the reference binary via `./probe`
(docker exec wrapper) and reading upstream documentation.

## Anti-cheating manifest

This agent's input is bounded to **probe output + upstream documentation +
methodology corpus**. The methodology corpus (`data/methodology.md`,
copied from `../meta/probe-methodology.md`) contains **no PB grader data**
—— only generic probe technique distilled from 12 CC probe sessions.

### Legal data sources (green)

- `./probe <args>` output (stdout / stderr / exit code)
- `binary's --help / --version / error messages`
- upstream repo @ pinned commit (`README` / `*.1 man` / `CHANGELOG`)
- container-internal non-grader resources (`/usr/local/<lang>/src` etc.)
- this repo's `data/methodology.md` (元方法学，不含 grader 数据)

### Forbidden data sources (red)

- `programbench/data/tasks/*/tests.json` (grader-private test list)
- HF `ProgramBench-Tests` tarball pytest 源码
- `distill_out/{summaries,features,task_archetypes}.jsonl` (派生自 tests.json)
- 老 `haskell-tester/data/{playbooks,archetype_taxonomy,fewshot_examples}` (反推 grader)

### Decision rule

> Is this info about "the program's behavior" or "how grader tests it"?
> The former is legal; the latter is contamination.

## Build & run

```bash
cabal build
cabal run hsbb -- agent /path/to/task_dir
```

Need `DEEPSEEK_API_KEY` in env.

## Layout

```
hs-blackbox-agent/
├── README.md
├── hs-blackbox-agent.cabal
├── data/
│   └── methodology.md        ← distill v1, embed via TH
├── src/Blackbox/
│   ├── Types.hs              ← BlackBoxType, Idiom, PlanStage, Belief
│   ├── Classifier.hs         ← Detection rules → BlackBoxType
│   ├── Plan.hs               ← Per-type stage templates
│   ├── Probe.hs              ← `./probe` subprocess wrapper
│   ├── LLM.hs                ← Deepseek HTTP client
│   ├── InnerLoop.hs          ← LLM-driven probe → observe → next
│   └── Belief.hs             ← belief.md writer
├── app/Main.hs               ← `hsbb agent <task_dir>`
└── test/Spec.hs              ← smoke test
```
