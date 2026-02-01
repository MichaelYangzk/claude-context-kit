---
name: context-optimizer
description: Context window 优化与防腐策略。在长会话、大文件处理、或 compact 后自动触发。当用户说 "optimize context"、"recite rules"、"/context-check" 时使用。也在每次 compact 后自动执行双端注入。
---

# Context Optimizer Skill

基于 Anthropic 工程博客、Chroma context-rot 研究、Du et al. (EMNLP 2025) Recite-then-Solve 论文的 5 项上下文优化策略。

---

## Strategy 1: Sub-Agent Delegation (最高收益)

**原理:** 大文件直接读入主 agent 上下文会加速 sigmoid 衰退。用 sub-agent 处理大文件，只返回压缩摘要。

**规则:**
- 文件 > 30KB → **必须**用 `Task` tool 启动 sub-agent 处理，不要直接 Read
- PDF 文件 → **始终**用 sub-agent，无论大小
- 搜索结果超过 50 行 → sub-agent 筛选后返回摘要

**执行模板:**
```
当需要处理大文件时:
1. 用 Task tool 启动 Explore 或 general-purpose sub-agent
2. sub-agent 读文件、提取关键信息
3. sub-agent 返回 < 2000 token 的压缩摘要
4. 主 agent 只使用摘要，从不接触原始内容
```

**示例 prompt 给 sub-agent:**
```
读取 [文件路径]，提取以下信息：
1. [具体需要的信息]
2. [具体需要的信息]
返回结构化摘要，不超过 1500 tokens。只返回关键事实和数据。
```

---

## Strategy 2: Tool Result Clearing (轻量级 Compaction)

**原理:** 每次工具调用的 raw output 留在上下文里会加速衰退。主动提炼结论，减少上下文膨胀。

**规则:**
- 每次工具调用后，立即在回复中总结结论（1-3 句话）
- 不要在后续回复中引用工具的 raw output，只引用你提炼的结论
- `ls` / `tree` 输出 → 提炼为 "该目录包含 X 个文件，关键文件是 A, B, C"
- `grep` 搜索结果 → 提炼为 "找到 N 处匹配，最相关的在 file:line"
- 文件读取 → 提炼为 "该文件实现了 X 功能，关键逻辑在 line N-M"

**注意:** 这不是说不用工具，而是用完后主动做信息压缩。

---

## Strategy 3: Recite-then-Solve (Du et al.)

**原理:** 在执行关键操作前，先复述相关规则。强制刷新模型对指令的 attention，延缓上下文衰退。

**触发时机:**
- 上下文使用超过 40% 时（对话明显变长时）
- 执行文件修改/删除操作前
- 用户说 "recite rules" 或 `/recite` 时
- 感觉自己开始忘记规则时

**执行:**
运行 `scripts/recite.py` 或手动复述:
```
[Context Health Check]
1. Safety: 不用 rm/rmdir，用 mv ~/.Trash/
2. Communication: 先说 ///，再说 [•]
3. Style: No emojis except check/cross, Elon style
4. Action: 直接做，少问多做
5. Canary: [检查金丝雀是否还在上下文中]
```

**用户可手动触发:** `/recite` 或 "recite your rules"

---

## Strategy 4: Dual-End Safety Injection (U 形曲线)

**原理:** Lost-in-the-Middle 研究证明上下文开头和结尾的 attention 最强。安全规则只在开头（CLAUDE.md）注入不够，需要在每次 compact 后在结尾也重申。

**规则:**
- 每次 compact/summarize 后，在下一条回复末尾追加:

```
---
[Context Refresh]
Safety: No rm/rmdir. Trash only.
Style: /// then [•]. No emojis. Direct action.
```

- 这段不需要很长，3-5 行核心规则即可
- 目的是利用 recency bias 加强对规则的记忆

---

## Strategy 5: Index Refinement (已在实践)

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
| 读取 > 30KB 文件 | Strategy 1 (Sub-Agent) |
| 任何工具调用后 | Strategy 2 (Result Clearing) |
| 对话超过 ~20 轮 | Strategy 3 (Recite) |
| Compact 后 | Strategy 4 (Dual-End Inject) |
| 浏览目录/文件 | Strategy 5 (Index Only) |

---

## Manual Commands

| 命令 | 作用 |
|------|------|
| `/recite` | 触发 Strategy 3，复述所有核心规则 |
| `/context-check` | 运行全部 5 项检查，报告上下文健康状态 |
| `optimize context` | 同 `/context-check` |

---

## /context-check 输出模板

```
[Context Health Report]
1. Sub-Agent: [是否有大文件直接读入?] ✅/❌
2. Result Clearing: [最近的工具结果是否已提炼?] ✅/❌
3. Rule Recitation: [能否完整复述核心规则?] ✅/❌
4. Dual-End Inject: [上次 compact 后是否重申了规则?] ✅/❌
5. Index Hygiene: [上下文中是否有不必要的长文?] ✅/❌
Canary: [金丝雀 token 是否还存在?] ✅/❌
```
