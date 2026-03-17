---
name: milestone
description: List open and closed issues for a milestone. Open issues are grouped by implementation affinity — which ones can be built together in the same feature branch. Defaults to the current (most active open) milestone if no argument is given.
disable-model-invocation: false
argument-hint: [milestone-title]
allowed-tools: Bash
---

# Milestone Issue Summary

Display a grouped summary of all issues in a milestone.

## Steps

### 1. Resolve the milestone

If `$ARGUMENTS` is non-empty, use it as the milestone title.

If `$ARGUMENTS` is empty, find the current milestone — the open milestone with the most open issues:

```
gh api repos/Shape-Machine/tusk-macos/milestones --jq 'sort_by(.open_issues) | reverse | .[0].title'
```

If no open milestones exist, report that and stop.

### 2. Fetch open and closed issues

```
gh issue list --milestone "<milestone>" --state open --json number,title,labels,body --limit 100
gh issue list --milestone "<milestone>" --state closed --json number,title,labels --limit 100
```

### 3. Group open issues by implementation affinity

Analyse the open issues and group them by which ones can be implemented together in the same feature branch. Use your knowledge of the codebase to reason about:

- **Shared files** — issues that touch the same view, model, or database layer
- **Shared infrastructure** — issues that need the same new type, query, or UI pattern
- **Logical cohesion** — issues that are variants of the same feature (e.g. "show X in sidebar", "show Y in sidebar")

Each group gets:
- A short **group name** describing what they have in common (e.g. "Schema sidebar additions", "Table detail new tabs")
- A one-line **rationale** explaining why they belong together
- The list of issues in the group

Issues that are genuinely standalone get their own single-issue group.

### 4. Display the summary

Print the milestone title as a heading.

**Open issues** — one section per implementation group:

```
### <Group name>
<rationale>
  #<number>  <title>
  #<number>  <title>
```

After all groups, print a total: `<N> open across <M> groups`.

**Closed issues** — flat list, no grouping:

```
  #<number>  <title>
```

After closed issues, print a count: `<N> closed`.

Keep output concise — group names and rationale tight, no extra prose.
