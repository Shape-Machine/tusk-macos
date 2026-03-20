---
name: issue
description: Review one or more GitHub issues, rate them, validate UX/implementation guidelines against the codebase, propose the best implementation path, then implement all in a single PR on approval
disable-model-invocation: false
argument-hint: <issue-number> [issue-number ...]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, AskUserQuestion, ExitPlanMode
---

# Issue Review & Implementation

Work through one or more GitHub issues end-to-end: understand them, rate them, validate any proposed approach against the real codebase, propose the best path forward, and implement all in a single PR on approval.

Parse `$ARGUMENTS` as a space-separated list of issue numbers. All steps below apply to every issue in the list.

## Steps

### 1. Fetch all issues

For each issue number in `$ARGUMENTS`:
```
gh issue view <number>
```

Read the full issue body, title, labels, and any comments for each.

### 2. Check for existing work

For each issue number, verify the issue is still open:

```
gh issue view <number> --json state --jq '.state'
```

If any issue is already closed, report it and stop — do not work on a closed issue.

Check if work has already started:

```
git branch -a | grep <number>
gh pr list --search "<number>" --state all
```

If an open PR or branch already exists for any issue, report it and stop — do not duplicate work.

### 3. Rate importance

For each issue, score on three axes, each 1–5:

- **Impact** — how many users does this affect, and how much does it improve their workflow?
- **Complexity** — how hard is this to implement correctly? (5 = very hard)
- **Risk** — could this break existing behaviour or introduce regressions? (5 = high risk)

Present as a concise table with one row per issue. Add a one-sentence verdict per issue: **High / Medium / Low priority** with reasoning.

### 4. Review proposed UX and implementation guidelines

For each issue, extract any UX or implementation suggestions explicitly. Then:

- Search the codebase for the relevant files, views, and patterns that would be touched
- Assess whether the proposed approach fits the existing architecture and SwiftUI patterns used in the project
- Call out anything that looks off — wrong layer, inconsistent with how similar features work, or likely to cause SwiftUI state bugs
- Identify shared infrastructure or patterns across the issues that can be implemented once

If an issue has no UX/implementation detail, skip that step for it and note that none was provided.

### 5. Propose implementation path

Propose a single combined implementation covering all issues:

- **UX** — for each issue, exactly what the user sees and how they interact with it. Be specific: which view, which control, what triggers what.
- **Implementation** — which files change, what new types or views are needed, how state flows. Reference actual file paths and existing patterns. Call out shared infrastructure that serves multiple issues.
- **What to avoid** — flag any traps or anti-patterns specific to this codebase.

Keep this tight. No padding.

### 6. Wait for approval

Present the user with three options:
1. **Approve** — proceed with implementation as proposed
2. **Revise** — user provides feedback; update the proposal and loop back to this step
3. **Abort** — stop without implementing anything

Do not write any code until the user explicitly approves.

### 7. Update each GitHub issue with the approved plan

For each issue number, post a comment summarising the approved plan:

```
gh issue comment <number> --body "$(cat <<'EOF'
## Approved Implementation Plan

### UX
<exact UX as approved for this issue>

### Implementation
<files that will change, new types/views, how state flows>

### What will not change
<anything explicitly out of scope>

---
*Implementation starting now (combined PR with issues <all numbers>).*
EOF
)"
```

### 8. Baseline build check

Before touching any code, confirm the current state of the repo builds cleanly:

```
xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -destination "platform=macOS" build 2>&1 | tail -3
```

If the build fails, stop and report — do not proceed on a broken baseline.

### 9. Implement in a single feature branch

1. Branch name:
   - Single issue: `feature/#<number>-<slug>`
   - Multiple issues: `feature/#<first-number>-#<second-number>-...-<slug>` where slug describes the combined work
   ```
   git checkout -b feature/<branch-name>
   ```
2. Implement exactly what was approved for all issues — no scope creep
3. Follow all existing patterns in the codebase (font settings via `@AppStorage`, explicit `.font()` on List rows, etc.)
4. Build to confirm no regressions:
   ```
   xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -destination "platform=macOS" build 2>&1 | tail -3
   ```
   Do not proceed if the build fails.
5. Stage and commit only the files you changed. Use one commit per issue if the changes are cleanly separable, or a single commit if they share infrastructure:
   ```
   git add <changed files>
   git commit -m "feat: <short description>"
   ```

### 10. Push and open a single PR

Find the current milestone (the open milestone with the most open issues):

```
gh api repos/Shape-Machine/tusk-macos/milestones --jq 'sort_by(.open_issues) | reverse | .[0].title'
```

```
git push -u origin feature/<branch-name>
gh pr create \
  --title "<concise title covering all issues>" \
  --milestone "<current-milestone-title>" \
  --body "$(cat <<'EOF'
## Summary
<2–4 sentences describing what was built and why>

## Changes
- <file or component>: <what changed>
- ...

## What was not changed
<explicitly note anything adjacent that was considered but left out>

## How to test
<short, specific steps to verify each feature works>

Closes #<number1>
Closes #<number2>
...
EOF
)"
```

### 11. Confirm

Report the PR URL and summarise what was implemented for each issue.
