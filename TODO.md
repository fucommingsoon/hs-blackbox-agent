## TODO

### evidence harness 侧 auto-merge (低优先级)

**现状**: `writeSlotRaw` 全量替换 evidence 数组, LLM 回写时可能丢失旧条目 (如 round 2 丢了 `probe_init_h`).
根因: `slotLine` 不渲染 evidence → LLM 看不到旧 evidence → 无法 merge. prompt 要求 merge 但 LLM 无从执行.

**为什么暂时不修**: evidence 是纯审计元数据, 不进任何 prompt, 不参与决策/gate/confidence 计算.
content 里的 inline `← probe_id` 标记已覆盖 LLM 需要的溯源信息. probes.jsonl + trace.jsonl 有完整审计链.
实际影响: 仅 oracle.yaml 作为审计产物时 evidence 链不完整, 不影响 LLM 推理正确性.

**方案** (后续做): `writeSlotRaw` 里 harness 侧 auto-merge evidence (读旧数组 → 合并 LLM 给的新条目 → dedup).
和 confidence/write_count/last_round 一样由 harness 计算, LLM 不操心. prompt 删掉 evidence 管理指令.
