
## Context Hygiene Rules (auto-injected by context-optimizer skill)

**来源:** Anthropic Engineering Blog + Chroma context-rot research

### 大文件处理
- 文件 > 30KB → 默认用 Task sub-agent 处理，返回 < 2000 token 摘要
- PDF → 默认用 sub-agent，无论大小
- 例外: 用户要求读全文、或任务需要完整内容（code review、diff、翻译）时，直接 Read

### 工具结果压缩
- 每次工具调用后，默认提炼为 1-3 句结论
- ls/tree → "N 个文件，关键: A, B, C"
- grep → "N 处匹配，最相关: file:line"
- 例外: 用户要求完整输出、或输出本身很短（< 20 行）时，直接展示

### Context Refresh 触发
- Compact 后 → CLAUDE.md 自动从磁盘重载，无需手动追加规则
- 如果指令遵从率下降 → 主动重新 Read CLAUDE.md
- 可手动触发: `/context-check`

### Compact Instructions (建议添加到 CLAUDE.md)
在 CLAUDE.md 中加入此段落，compact 时会优先保留:
```
## Compact Instructions
以下规则在 compact 后必须保留:
- [核心安全规则]
- [关键行为规则]
```

### 索引原则
- CLAUDE.md 当指针用，不是完整手册
- 先 ls 了解结构，确认需要再 Read
- 不把完整文档复制进上下文
