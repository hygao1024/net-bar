# Agent Note: Repository collaboration rules

Status: implemented

## Problem

仓库协作需要明确修改授权、事实归属与验证责任，避免依赖单次对话中的约定。

## Decision

以根目录 AGENTS.md 作为协作入口，具体任务按需加载 `.agents/skills/` 中的指导；决策记录的路径和格式由 `.agents/notes/README.md` 统一定义。检查选择依据实际改动及仓库已有命令，规则的语义适用性由评审判断。

## Alternatives considered

- 仅保留对话约定：后续协作者无法从仓库发现约束。
- 将完整检查套件固定到每次提交：增加局部检查点成本，保留按改动风险选择验证的方式。

## Consequences

流程规则随仓库版本管理；后续非平凡变更需要维护拥有决定的记录。当前未引入自动化文档检查或 Git hook（钩子），文本规则仍依赖协作者执行，不构成自动门禁。
