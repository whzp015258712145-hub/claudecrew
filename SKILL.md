---
name: claudecrew
description: >
  面向 Claude Code 的多 Agent 编排器。当用户有一个可分解的大型任务时，使用此技能来：
  (1) 分析并分解为完全解耦的子任务，
  (2) 创建 SPEC 目录，包含 REQUEST.md、DISPATCH.md 和每个 Agent 的任务 spec，
  (3) 通过 Claude Code 内置 Agent 工具并行启动 Worker subagent，
  (4) 派遣 Reviewer subagent 验证结果并审计代码 bug，
  (5) 迭代 review→fix 循环直到所有工作通过，
  (6) 派遣 Chief Auditor subagent 检查跨模块集成和耦合，
  (7) 汇总最终交付物。
  触发关键词包括 "claudecrew"、"orchestrate"、"distribute this"、"parallelize"、"/claudecrew"，
  也适用于明显需要并行开发的大型多文件任务。
---
# ClaudeCrew — 多 Agent 编排器（Subagent 版）

## 🔴 激活前缀

本 skill 加载后，首行必须输出：

```
✅ claudecrew 已激活
```

然后进入母 Agent 工作流。

---

## 核心理念

**你是母 Agent（Mother Agent）——你只做编排，不写代码。** 所有实际工作通过 Claude Code 内置的 `Agent` 工具（subagent）完成。

---

## 母 Agent 工作流（9 阶段）

### 阶段 1：了解项目 & 保存请求

1. **快速了解项目结构**（必要时读关键文件，但控制在 5 个 Read 以内）
2. 创建 SPEC 目录：`SPEC/YYYY-MM-DD_slug/`
3. 写入 `REQUEST.md`：
   - 原始需求
   - 验收标准
   - 约束（技术栈、不可改的文件）
   - "完成"的定义
4. 如有歧义，现在问用户

### 阶段 2：分解任务

1. 识别**完全解耦**的子任务 — 改同一文件的任务必须合并
2. 写入 `DISPATCH.md`：
   - 分解理由
   - Agent 分配表
   - 执行顺序

### 阶段 3：编写 Task Spec

为每个 Worker 写自包含的 task spec（`tasks/worker-XX_<slug>.md`）。Worker 拿到 spec 后应能在零外部上下文下完成工作。

**Spec 模板：**
```markdown
# <任务标题>

## 你的角色
## 背景（项目是什么，相关文件有哪些）
## 任务（具体步骤，越详细越好）
## 约束
- 允许修改的文件：<明确列表>
- 禁止修改的文件：<明确列表>
- 其他约束
## 预期产出
### 结果文件：SPEC/<dir>/results/result-<id>.md
（必须写入此文件，包含修改摘要、功能清单、自测情况）
### 你的最终回复中必须包含"完成"二字
## 验收标准
```

### 阶段 4：并行启动 Worker（用 Agent 工具）

**关键：所有 Worker 在同一轮消息中并行启动。**

对每个 Worker，调用 `Agent` 工具：
```
subagent_type: "general-purpose"
description: "<简短描述>"
prompt: "你的任务是：读取并执行 SPEC 文件 SPEC/<dir>/tasks/worker-XX_<slug>.md 中的所有指令。仔细阅读该文件，按步骤逐一完成，最后将结果写入指定的 result 文件并在回复中说明'完成'。"
run_in_background: true
```

### 阶段 5：等待 Worker 完成

用 `TaskOutput` 工具逐一等待每个 Worker（block=true）。

全部完成后的检查：
- 读取每个 Worker 的 result 文件，做合理性检查
- Worker 的 task_id 记入 DISPATCH.md

### 阶段 6：派遣 Reviewer

为每个 Worker 写 review spec（`tasks/review-XX_<slug>.md`），然后并行启动 Reviewer subagent（同样用 `Agent` 工具，`run_in_background: true`）。

Reviewer spec 模板：
```markdown
# Review-XX：审查 <模块名>

## 你的角色：代码审查专家

## 审查对象
- Worker spec：SPEC/<dir>/tasks/worker-XX_<slug>.md
- Worker 结果：SPEC/<dir>/results/result-worker-XX.md
- 实际代码变更：（列出文件路径）

## 审查步骤
1. 对照 spec 验收标准逐项检查
2. 审计代码 bug（逻辑错误、边界条件、内存安全、线程安全）
3. 评估代码质量

## 输出
### 结果文件：SPEC/<dir>/results/result-review-XX.md

格式：
## 裁决：PASS / NEEDS_FIX / FAIL
## 验收清单（表格）
## Bug 发现（编号+严重程度+位置+描述+修复建议）
## 代码质量评估
## 总结

## 约束
- 只读审查，不修改代码
- PASS: 无 Critical/High bug，验收项全部通过
- NEEDS_FIX: 存在可修复的 bug
- FAIL: 需要重新设计
```

### 阶段 7：迭代修复

- **全部 PASS** → 进入阶段 8
- **有 NEEDS_FIX** → 写 fix spec → 启动 fix Worker → 重新 Review
  - 简单修复（≤3 行，不改逻辑结构）可直接入 CA
- **有 FAIL** → 重新设计 task spec，从头来

### 阶段 8：Chief Auditor 跨模块审计

仅在全部单独审查 PASS 后触发。

写 `tasks/chief-auditor_<slug>.md`，启动 CA subagent。

CA spec 核心维度：
- 接口兼容性（协议遵循、数据模型字段使用一致性）
- 数据流一致性（从格式检测到渲染的完整链路）
- 耦合检查（重复代码、共享可变状态、Error 模式一致性）
- 跨模块 bug（不同模块的 HTML 结构是否与 WebViewRenderer 兼容等）

### 阶段 9：交付

向用户汇报：
- 完成摘要
- 参与的 Agent 及其产出
- 审查结果
- 交付物位置

---

## SPEC 目录结构

```
SPEC/
└── YYYY-MM-DD_short-slug/
    ├── REQUEST.md
    ├── DISPATCH.md
    ├── tasks/
    │   ├── worker-01_<slug>.md
    │   ├── worker-02_<slug>.md
    │   ├── review-01_<slug>.md
    │   ├── review-02_<slug>.md
    │   ├── chief-auditor_<slug>.md
    │   └── fix-XX_<slug>.md
    └── results/
        ├── result-worker-01.md
        ├── result-review-01.md
        └── result-chief-auditor.md
```

---

## 调度速查表

| 阶段 | 工具 | 方式 |
|------|------|------|
| 启动 Worker | `Agent` subagent_type="general-purpose" | run_in_background: true, 同一轮并行 |
| 等待 Worker | `TaskOutput` | block=true, 对每个 task_id |
| 启动 Reviewer | `Agent` subagent_type="general-purpose" | run_in_background: true, 同一轮并行 |
| 启动 CA | `Agent` subagent_type="general-purpose" | run_in_background: true |
| 启动 Fix | `Agent` subagent_type="general-purpose" | run_in_background: true |

---

## 反模式

- ❌ 母 Agent 自己写代码 — 始终通过 subagent 执行
- ❌ 两个 Worker 改同一文件
- ❌ 让 Worker 之间协调
- ❌ 母 Agent 自己审查 — 始终派 Reviewer subagent
- ❌ 跳过 Chief Auditor
- ❌ Spec 少于 20 行
- ❌ Worker 没完成就启动 Reviewer
- ❌ 单独审查未全部 PASS 就启动 CA
- ❌ 忘记先写 REQUEST.md
- ❌ 用英文写 spec（DeepSeek 中文优化更好）
