---
name: context-optimizer
description: Context window 优化与防腐策略。在长会话、大文件处理、或 compact 后自动触发。当用户说 "optimize context" 或 "/context-check" 时使用。
---

# Context Optimizer Skill

基于 Anthropic 工程博客、Chroma context-rot 研究的 4 项上下文优化策略。

---

## Strategy 1: Sub-Agent Delegation (最高收益)

**原理:** 大文件直接读入主 agent 上下文会加速 sigmoid 衰退。用 sub-agent 处理大文件，只返回压缩摘要。

**默认规则:**
- 文件 > 30KB → 优先用 `Task` tool 启动 sub-agent 处理
- PDF 文件 → 优先用 sub-agent，无论大小
- 搜索结果超过 50 行 → sub-agent 筛选后返回摘要

**例外 — 允许直接 Read 的场景:**
- 用户明确要求读全文（如 "读完整文件"、"show me the whole file"）
- 任务本身需要完整内容（如逐行 code review、应用 diff、全文翻译）
- 文件虽然 > 30KB 但用户指定了具体行范围（用 Read offset/limit）

**判断原则:** Sub-agent 是默认优化手段，不是硬性限制。当完整内容对任务有实际价值时，直接读取是正确选择。

**执行模板:**
```
当需要处理大文件时:
1. 先判断: 任务是否需要完整内容?
   - 需要 → 直接 Read（可用 offset/limit 分段读）
   - 只需要部分信息 → 用 Task sub-agent
2. sub-agent 读文件、提取关键信息
3. sub-agent 返回 < 2000 token 的压缩摘要
4. 主 agent 使用摘要继续工作
```

---

## Strategy 2: Tool Result Clearing (轻量级 Compaction)

**原理:** 每次工具调用的 raw output 留在上下文里会加速衰退。主动提炼结论，减少上下文膨胀。

**默认规则:**
- 每次工具调用后，立即在回复中总结结论（1-3 句话）
- 不要在后续回复中引用工具的 raw output，只引用你提炼的结论
- `ls` / `tree` 输出 → 提炼为 "该目录包含 X 个文件，关键文件是 A, B, C"
- `grep` 搜索结果 → 提炼为 "找到 N 处匹配，最相关的在 file:line"
- 文件读取 → 提炼为 "该文件实现了 X 功能，关键逻辑在 line N-M"

**例外 — 允许展示完整输出的场景:**
- 用户明确要求完整输出（如 "show full tree"、"列出所有文件"、"show all results"）
- 任务需要完整列表才能做决策（如选择文件、对比差异、审查目录结构）
- 输出本身就很短（< 20 行），压缩反而增加复杂度

**判断原则:** 提炼是默认行为，但用户有权看到完整信息。当用户需要全貌来做判断时，完整展示优于过度压缩。

---

## Strategy 3: CLAUDE.md Re-Read (Compact 后规则恢复)

**原理:** Claude Code 在 compact 后会自动从磁盘重新读取所有层级的 CLAUDE.md 文件。安全规则和项目指令本身已内建在 compact 流程中。关键不是在回复里硬编码规则，而是确保 CLAUDE.md 被正确读取和遵守。

**Claude Code compact 行为（已验证）:**
- Compact = 上下文摘要 + 重新开始，CLAUDE.md 自动从磁盘重新加载
- 可在 CLAUDE.md 中添加 `## Compact Instructions` 段落，自定义 compact 时保留的信息
- `PreCompact` hook 可在 compact 前触发自定义逻辑
- `SessionStart` hook (`source: "compact"`) 可检测 compact 后状态

**规则:**
- Compact 后**不需要**在回复末尾追加硬编码规则 — CLAUDE.md 会自动重载
- 如果感觉指令遵从率下降 → 主动重新读取 CLAUDE.md（用 Read tool）
- 可以在 CLAUDE.md 中加 `## Compact Instructions` 段落，指定 compact 摘要中必须保留的关键规则
- Canary 检测机制会独立监控指令遵从率，不依赖回复末尾的硬编码

**建议在 CLAUDE.md 中添加:**
```markdown
## Compact Instructions
以下规则在 compact 后必须保留:
- [你的核心安全规则]
- [你的关键行为规则]
```

---

## Strategy 4: Index Refinement (已在实践)

**原理:** Chroma 研究发现结构化长文的 context rot 比碎片化内容更严重。给 agent 的应该是指针和关键词，不是整理好的长篇文档。

**规则:**
- CLAUDE.md 保持精简，当指针用
- 不要把完整文档内容复制进上下文，用文件路径 + 摘要
- 优先用 `ls` 了解结构，确认需要再 Read 具体文件
- 索引格式: `文件路径 → 一句话说明`，不要给大段原文

---

## Auto-Trigger Rules

| 场景 | 自动执行 |
|------|----------|
| 读取 > 30KB 文件（用户未要求全文） | Strategy 1 (Sub-Agent) |
| 任何工具调用后（用户未要求完整输出） | Strategy 2 (Result Clearing) |
| Compact 后指令遵从下降 | Strategy 3 (Re-Read CLAUDE.md) |
| 浏览目录/文件 | Strategy 4 (Index Only) |

---

## Manual Commands

| 命令 | 作用 |
|------|------|
| `/context-check` | 运行全部 4 项检查，报告上下文健康状态 |
| `optimize context` | 同 `/context-check` |

---

## /context-check 输出模板

```
[Context Health Report]
1. Sub-Agent: [是否有大文件直接读入?] ✅/❌
2. Result Clearing: [最近的工具结果是否已提炼?] ✅/❌
3. CLAUDE.md Loaded: [CLAUDE.md 规则是否已加载/遵守?] ✅/❌
4. Index Hygiene: [上下文中是否有不必要的长文?] ✅/❌
Canary: [金丝雀 token 是否还存在?] ✅/❌
```
