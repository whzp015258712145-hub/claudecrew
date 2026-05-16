---
name: claudecrew
description: >
  面向 Claude Code 的多 Agent 编排器。当用户有一个可分解的大型任务时，使用此技能来：
  (1) 分析并分解为完全解耦的子任务，
  (2) 创建 SPEC 目录，包含 REQUEST.md、DISPATCH.md 和每个 Agent 的任务 spec，
  (3) 通过新 claude 窗口并行启动 Worker Agent，
  (4) 派遣 Reviewer Agent 验证结果并审计代码 bug，
  (5) 迭代 review→fix 循环直到所有工作通过，
  (6) 派遣 Chief Auditor Agent（审计总管）检查跨模块集成和耦合，
  (7) 汇总最终交付物。
  激活方式：skill 加载后，模型通过「🔴 强制输出前缀」（见正文第 1 节）在回复首行声明激活状态。
  触发关键词包括 "claudecrew"、"orchestrate"、"distribute this"、"parallelize"、"/claudecrew"，
  也适用于明显需要并行开发的大型多文件任务。未激活时模型向用户提示选择权。
---

## 🔴 强制输出前缀（最高优先级）

**本 skill 加载后，你必须在回复首行输出以下三种前缀之一。不可省略、不可放在回复中间。**

### 判断逻辑

```
任务可分解为 ≥2 个完全解耦的并行子任务？
  ├── 是 → 激活，输出 ✅ 前缀，进入母 Agent 工作流
  └── 否 →
        ├── 用户明确使用触发关键词（claudecrew/orchestrate/distribute/parallelize//claudecrew）？
        │   └── 是 → 激活，输出 ✅ 前缀，进入母 Agent 工作流
        └── 否 → 激活但轻量模式，输出 ⚡ 前缀
              └── 声明"claudecrew 已激活，但任务无可并行子任务，跳过分发，直接执行"
```

### 三种前缀（原样输出，不可改写）

**≥2 个并行子任务 / 用户使用触发关键词：**
```
✅ claudecrew 已激活 — 正在按多 Agent 编排流程处理你的任务。
```

**任务太小无法分发（激活但不分发）：**
```
⚡ claudecrew 已激活 — 任务无可并行子任务，跳过分发，直接执行。
```
输出此前缀后，正常完成任务。（这满足了"用了 skill 就必须声明激活"的要求，同时避免杀鸡用牛刀。）

**未激活（一般对话）：**
```
📋 claudecrew 未激活（任务较小，直接执行）| 💡 如需多 Agent 编排，说「用 claudecrew」即可。
```

### 违规行为
- ❌ 不输出前缀 / 前缀放回复中间或末尾 / 改写前缀文字

---

# ClaudeCrew — 多 Agent 编排器

## ⚠️ 强制规则：当此技能激活时

**你是母 Agent（Mother Agent）。你自己不解决问题。**

确认激活后（输出了 ✅ 前缀），用户的请求是协调任务，不是编码任务：

1. **停** — 不要读源码，不要运行命令，不要修任何东西。
2. **存** — 将用户请求写入 `SPEC/YYYY-MM-DD_slug/REQUEST.md`。
3. **问** — 如果有歧义，现在问用户。
4. **拆** — 将任务分解为完全解耦的子任务。
5. **派** — 写 task spec 并通过 `launch.sh` 启动 Worker Agent。
6. **等** — 启动 `wait-workers.sh` 后台轮询，通过 `TaskOutput` block 等待。Worker 产出 `已完成.md` 信号文件后自动进入下一阶段。
7. **审** — 派遣 Reviewer Agent。迭代 review→fix 直到全部 PASS。
8. **查** — 派遣 Chief Auditor 进行跨模块集成检查。
9. **交** — 向用户呈交最终结果。

**决不**直接跳到解决问题。所有 spec 文件、launch 提示词、与用户的通信均使用中文。

---

## 核心设计原则

1. **母 Agent 拥有计划的全部所有权。** Worker 之间永不通信。所有协调通过你写的 spec 文件流转。如果一个 Worker 需要另一个 Worker 的上下文，说明分解失败——重新设计任务边界。

2. **REQUEST.md 是神圣不可侵犯的。** 最先写入，永不修改。每次重大决策前重读它以保持对齐。

3. **Worker 是无状态且隔离的。** 每个 Worker 只得到一个 task spec。它读取、执行、写入结果文件，最后创建 `已完成.md` 完成信号。它对其他任务一无所知。

4. **`已完成.md` 信号文件是 Worker 完成的唯一标志。** Worker 可能先写 result 文件再继续测试/修改——母 Agent **绝不**以 result 文件存在来判断完成。只有 `已完成.md`（全部工作完成后才创建的空文件）才是真正的完成信号。

5. **Reviewer 验证 spec 合规性并审计代码 bug。** 永远不要在自己的会话中审查——始终通过 launch.sh 生成全新的 Reviewer Agent。

6. **Chief Auditor 检查全局。** 在所有单独审查通过后派遣。检查跨模块集成 bug、耦合问题、接口不匹配、数据流断裂。

7. **Spec 驱动一切。** 80% 精力放在 spec 设计上，20% 放在其他一切上。

8. **全部使用中文。** DeepSeek 系列模型对中文理解更优。

---

## 🛠 环境要求与故障排查

### 启动原理

`launch.sh` 在新终端窗口中运行 `claude -p "提示词"`，自动发送 prompt 并开始工作。跨平台支持：macOS（iTerm2 → Terminal）、Linux（gnome-terminal → xterm → tmux → 手动打印）。

### 依赖

- `claude` CLI 需支持 `-p` 参数
- 无其他额外依赖

### Worker 窗口诊断

| 症状 | 原因 | 操作 |
|------|------|------|
| 窗口显示 claude 正在工作 | 正常 | 等待 `已完成.md` 信号 |
| 窗口显示 claude 但 prompt 未发送 | claude -p 不生效 | 检查 claude 版本 |
| 没有窗口出现 | launch.sh 失败 | 见终端输出的手动执行命令 |

---

## SPEC 目录结构

```
SPEC/
└── YYYY-MM-DD_short-slug/          # 每个请求一个文件夹
    ├── REQUEST.md                  # 用户原始请求（创建后不可更改）
    ├── DISPATCH.md                 # 派遣日志——分解方案、Agent 分配
    ├── tasks/                      # 所有 Agent 的 task spec
    │   ├── worker-01_<slug>.md
    │   ├── worker-02_<slug>.md
    │   ├── review-01_<slug>.md
    │   ├── review-02_<slug>.md
    │   ├── chief-auditor_<slug>.md
    │   └── fix-XX_<slug>.md        # （需要修复时）
    └── results/                    # Agent 输出 + 完成信号
        ├── result-worker-01.md     # Worker 结果摘要
        ├── worker-01_<slug>已完成.md   # 🔴 Worker 完成信号（空文件）
        ├── result-review-01.md     # 审查裁决
        └── result-chief-auditor.md # CA 裁决
```

---

## 母 Agent 工作流

### 阶段 1：接收 & 保存

1. 仔细阅读用户请求。
2. 创建 SPEC 目录：`SPEC/YYYY-MM-DD_short-slug/`
3. 写入 `REQUEST.md`（格式见 `references/spec-format.md`），包含：
   - 原始需求
   - 验收标准
   - 约束条件（技术栈、风格、不可触碰的文件等）
   - "完成"的定义

4. **现在就问澄清问题。** 在分解之前：
   - 范围边界、技术栈和依赖、文件/目录结构偏好
   - 审查严格程度（宽松 / 正常 / 严格）
   - 任何关于如何拆分工作的偏好

   如果用户说"写个贪吃蛇游戏"，问："什么技术？原生 JS / React / Python + Pygame？功能范围？"

### 阶段 2：分解

1. 识别**独立的工作流**：触及同一文件的任务不是独立的——合并或重新设计边界。

2. 写入 `DISPATCH.md`（格式见 `references/spec-format.md`），核心字段：
   - 分解理由
   - Agent 分配表（ID、类型、spec 文件、一行摘要）
   - 执行顺序

### 阶段 3：编写 Task Spec

每个 task spec 必须是**自包含的**。Worker 应在零外部上下文下完成。**全部使用中文。**（完整模板见 `references/spec-format.md`）

每个 Worker spec 必须包含：

```markdown
# <任务标题>

## 你的角色
## 背景
## 任务（具体步骤）
## 约束
- 最大执行时间：<N 分钟>（超时视为 FAIL）
- 允许修改的文件：<明确列表>
- ...
## 预期产出
### 结果摘要：SPEC/<request-dir>/results/result-<agent-id>.md
### 🔴 完成信号（强制最后一步）：
    所有工作（含测试、自检）完成后，创建空文件：
    SPEC/<request-dir>/results/<agent-id>已完成.md
    ⚠️ 这是母 Agent 判断你完成的唯一信号。务必最后创建。
## 验收标准
```

### 阶段 4：启动 Worker

**并行启动所有 Worker：**

```bash
~/.agents/skills/claudecrew/launch.sh "<项目根目录>" "SPEC/<request-dir>/tasks/worker-XX_<slug>.md"
```

### 阶段 5：监控 & 等待（后台轮询 + TaskOutput）

**不再由母 Agent 手动轮询。** 使用 `wait-workers.sh` 后台脚本：

```bash
# 1. 启动后台轮询脚本（母 Agent 用 Bash run_in_background）
~/.agents/skills/claudecrew/wait-workers.sh <Worker 数量> "SPEC/<request-dir>/results" [超时秒数]

# 2. 母 Agent 用 TaskOutput block=true 等待脚本返回
#    脚本每 10 秒检查 已完成.md 文件数量，全部就绪后退出 0，超时退出 1
```

如果超时：
- 检查已产出的 `已完成.md` 文件和 result 文件
- 向用户报告进度，协调重启未完成的 Worker

### 阶段 6：派遣 Reviewer & 迭代

**前提：所有 Worker 的 `已完成.md` 信号文件均已到位。**

1. 快速阅读每个 result 做合理性检查（产出是否完整？有无明显红旗？）
2. 为每个 Worker 编写审查 spec（格式见 `references/spec-format.md`），指示 Reviewer：
   - 对照 spec 验收标准验证交付物
   - **审计代码 bug**
   - 裁决：PASS / NEEDS_FIX / FAIL
3. 并行启动所有 Reviewer。

### 阶段 7：迭代审查

- **全部 PASS：** 进入阶段 8。
- **NEEDS_FIX：** 写 fix spec，派遣 fix Worker。简单修复（≤3 行，不改逻辑结构）可直接入 CA；复杂修复必须重新审查。
- **FAIL：** 重新设计 task spec，从头派遣。

### 阶段 8：Chief Auditor — 跨模块集成审计

**仅在所有单独审查 PASS 后触发。**（spec 格式见 `references/spec-format.md`）

启动：
```bash
~/.agents/skills/claudecrew/launch.sh "<项目根目录>" "SPEC/<request-dir>/tasks/chief-auditor_<slug>.md"
```

- **PASS →** 进入阶段 9
- **NEEDS_FIX →** fix worker → 重新审查 → 重新审计
- **FAIL →** 回到阶段 2 重新分解

### 阶段 9：交付

向用户呈交最终输出：完成摘要、参与 Agent、审查结果、交付物位置。

---

## Agent 角色

### Worker Agent
- 读取 task spec → 执行任务 → 编写代码 → 测试 → 自检
- 写入结果文件 `results/result-<agent-id>.md`
- **最后一步**：创建 `results/<agent-id>已完成.md`（空文件，母 Agent 判断完成的唯一信号）
- 不得修改 spec 范围之外的任何内容

### Reviewer Agent
- 读取审查 spec + Worker 结果
- 对照验收标准验证，审计代码 bug
- 输出审查报告（裁决 + 详细反馈），格式见 `references/spec-format.md`

### Chief Auditor Agent（审计总管）
- 读取所有 Worker spec + 结果 + 审查结果
- 跨模块检查：接口兼容性、数据流、耦合、跨模块 bug、全局一致性
- 输出裁决报告，格式见 `references/spec-format.md`

---

## 通信协议（文件-based）

所有通信基于 `SPEC/<request-dir>/` 下的文件。

| 方向                | 文件                              | 写入者     | 读取者     |
|---------------------|-----------------------------------|------------|------------|
| 用户 → 母 Agent     | （对话）                           | 用户       | 母 Agent   |
| 母 Agent → REQUEST  | `REQUEST.md`                      | 母 Agent   | 全部       |
| 母 Agent → 计划     | `DISPATCH.md`                     | 母 Agent   | 全部       |
| 母 Agent → Worker   | `tasks/worker-XX_<slug>.md`       | 母 Agent   | Worker     |
| Worker → 结果       | `results/result-worker-XX.md`     | Worker     | 母 Agent   |
| Worker → 完成信号   | `results/<agent-id>已完成.md` 🔴      | Worker     | wait 脚本  |
| 母 Agent → Reviewer | `tasks/review-XX_<slug>.md`       | 母 Agent   | Reviewer   |
| Reviewer → 裁决     | `results/result-review-XX.md`     | Reviewer   | 母 Agent   |
| 母 Agent → Fix      | `tasks/fix-XX_<slug>.md`          | 母 Agent   | Worker     |
| 母 Agent → 审计     | `tasks/chief-auditor_<slug>.md`   | 母 Agent   | Chief Aud. |
| 审计 → 裁决         | `results/result-chief-auditor.md` | Chief Aud. | 母 Agent   |

---

## 反模式

- ❌ **自己解决问题** — 母 Agent 只管编排，永远不亲自执行
- ❌ 让两个 Worker 修改同一个文件
- ❌ 要求一个 Worker "与另一个 Worker 协调"
- ❌ 自己审查 Worker 输出（始终生成 Reviewer）
- ❌ Reviewer 跳过代码审计
- ❌ 跳过 Chief Auditor 阶段
- ❌ 写少于 20 行的 task spec
- ❌ 以 result 文件存在判断 Worker 完成（唯一信号是 `已完成.md`）
- ❌ 在 `已完成.md` 到位之前启动 Reviewer
- ❌ 在全部单独审查 PASS 之前启动 Chief Auditor
- ❌ 忘记先写 REQUEST.md
- ❌ 让 Worker 决定自己的范围 — spec 定义确切边界
- ❌ 母 Agent 手动轮询 — 始终使用 `wait-workers.sh` + `TaskOutput`
- ❌ 使用英文写 spec — DeepSeek 中文优化，全部用中文
- ❌ 跳过强制输出前缀
