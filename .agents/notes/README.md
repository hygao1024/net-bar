# Agent Notes

Agent Note（决策记录）保存代码和测试难以完整表达的原因、取舍和后果。正文语言沿用目标仓库约定；标题、状态和固定章节名保留英文，供工具稳定校验。

## 路径与分类

```text
docs/notes/{lifecycle}/{class}/yyyy-mm-dd-topic-title.md
```

活动 lifecycle（生命周期）：

- `proposed`：尚未完整交付的方案。
- `implemented`：已经完整交付且理由仍可能指导未来决定。
- `rejected`：明确否决且仍能防止现实、有诱惑力错误的方案。

分类是闭合集合：`feature` 表示新的用户或模型能力，`bug-fix` 表示缺陷修正，`simplification` 表示删除或合并已有表面，`architecture` 表示交付源码的结构决定，`process` 表示代码周边的工具与流程，`testing` 表示测试基础设施和策略。日期是主题首次提出日期；活动 lifecycle 变化只移动目录，保留分类、日期和主题文件名。

## 何时创建

每个 non-trivial change（非平凡变更）必须在同一变更中新增或更新至少一份 Agent Note。更新仍拥有该决定的记录即可；纯机械或纯局部且不改变行为、契约、结构、流程或理由的修改可以豁免。这个语义判断由 Review（评审）负责，格式校验不猜测 diff 的含义。

## 文件格式

头部必须为：

```markdown
# Agent Note: <标题>

Status: <status>
```

状态行后是一个空行。所有记录以 `## Problem` 开始正文并包含 `## Alternatives considered`；替代方案只能记录真实考虑过的选择。内容完整性由 Review（评审）判断，机械检查只验证稳定格式。

`proposed`：

```markdown
## Problem
## Proposal
## Alternatives considered
## Acceptance criteria
## Risks
```

`implemented`：

```markdown
## Problem
## Decision
## Alternatives considered
## Consequences
```

`rejected` 保留提案事实，要求 `Problem`、`Proposal` 和 `Alternatives considered`；状态行为 `Status: rejected — <拒绝原因>`。不要为了被拒绝的方案编造 acceptance criteria（验收条件）或 risks（风险）。

## 更新与取代

- `proposed` 实施后移动到 `implemented`，用现在时 Decision 和 Consequences 描述已交付事实。
- 实现位置变化但决定不变时，更新当前 implemented 记录中的事实。
- 新决定改变旧决定时，新建记录；部分取代保留旧记录并双向链接，不把旧记录改写成相反结论。
- 完全被取代的 implemented 记录可以合并到当前所有者后删除。删除前必须保留旧记录中独有的理由、替代方案、后果、必要验证和已知覆盖缺口，并修复所有入站链接；只取代一个实现、默认值、传输、展示或仍保留兼容处理时不属于完全取代。
- implemented 记录只有在理由、替代方案、负面保证、兼容约束或重新评估条件仍可能指导未来选择时保持活动。
- rejected 记录只在落选方案仍是现实且有诱惑力的错误时保持活动；已经不可能、被完全取代或不再防止误判时修复入站链接后删除，不归档 rejected 记录。
- proposed 记录不归档；不再推进时转为仍有警示价值的 rejected，或在没有保留价值时删除。年龄、字数和引用次数只能帮助发现候选；全仓审计只在明确请求、活动语料妨碍发现或大范围取代时执行。

## 冻结归档

archive（归档）不是第四个 lifecycle，而是已经不再指导当前选择的 implemented 历史。当已交付决定完整且其理由不太可能继续指导未来工作时，可以归档；理由、替代方案、负面保证、持久化或 wire（线协议）语义、安全规则或重新引入条件仍有未来价值时保持 active（活动）。归档以目标仓库已有的冻结守卫为执行前提：从 `implemented/<class>` 原样移动到 `archived/<class>`，保留 `Status: implemented`，只在下一行增加不早于文件日期的 `Archived: YYYY-MM-DD`。归档前修复活动文档的入站链接；归档后的正文、路径和出站链接都不得修改，也不得作为当前事实来源。

没有真实归档时，不维护空 manifest（清单）或 seal（封存）命令。首次归档必须在同一变更中引入目标仓库原生、经过 negative control（负向控制）的冻结守卫；此前保留活动记录。
