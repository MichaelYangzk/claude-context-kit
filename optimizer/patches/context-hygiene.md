
## Context Hygiene Rules (auto-injected by context-optimizer skill)

**来源:** Anthropic Engineering Blog + Chroma context-rot research + Du et al. EMNLP 2025

### 大文件处理
- 文件 > 30KB → 必须用 Task sub-agent 处理，不直接 Read
- PDF → 始终用 sub-agent，无论大小
- Sub-agent 返回 < 2000 token 摘要，主 agent 不接触原始内容

### 工具结果压缩
- 每次工具调用后，立即提炼为 1-3 句结论
- 不引用 raw output，只引用提炼后的结论
- ls/tree → "N 个文件，关键: A, B, C"
- grep → "N 处匹配，最相关: file:line"

### Context Refresh 触发
- 长对话 (~20+ 轮) → 主动复述核心规则 (Recite-then-Solve)
- Compact 后 → 在回复末尾追加 [Context Refresh] 安全规则摘要
- 可手动触发: `/recite` 或 `/context-check`

### 索引原则
- CLAUDE.md 当指针用，不是完整手册
- 先 ls 了解结构，确认需要再 Read
- 不把完整文档复制进上下文
