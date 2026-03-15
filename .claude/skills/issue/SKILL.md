---
name: issue
description: Review a GitHub issue, rate its importance, validate UX/implementation guidelines against the codebase, propose the best implementation path, then implement on approval
disable-model-invocation: false
argument-hint: <issue-number>
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task, AskUserQuestion, ExitPlanMode
---

# Issue Review & Implementation

Work through a GitHub issue end-to-end: understand it, rate it, validate any proposed approach against the real codebase, propose the best path forward, and implement on approval.

## Steps

### 1. Fetch the issue

```
gh issue view $ARGUMENTS
```

Read the full issue body, title, labels, and any comments.

### 2. Check for existing work

Before anything else, check if work on this issue has already started:

```
git branch -a | grep $ARGUMENTS
gh pr list --search "$ARGUMENTS" --state all
```

If an open PR or branch already exists, report it and stop — do not duplicate work.

### 3. Rate importance

Score the issue on three axes, each 1–5:

- **Impact** — how many users does this affect, and how much does it improve their workflow?
- **Complexity** — how hard is this to implement correctly? (5 = very hard)
- **Risk** — could this break existing behaviour or introduce regressions? (5 = high risk)

Present as a concise table. Add a one-sentence verdict: **High / Medium / Low priority** with reasoning. This is to help the user decide whether to proceed now or defer.

### 4. Review proposed UX and implementation guidelines

If the issue contains UX or implementation suggestions, extract them explicitly. Then:

- Search the codebase for the relevant files, views, and patterns that would be touched
- Assess whether the proposed approach fits the existing architecture and SwiftUI patterns used in the project
- Call out anything that looks off — wrong layer, inconsistent with how similar features work, or likely to cause SwiftUI state bugs

If the issue has no UX/implementation detail, skip this step and note that none was provided.

### 5. Propose implementation path

Based on your code review, propose:

- **UX** — exactly what the user sees and how they interact with it. Be specific: which view, which control, what triggers what.
- **Implementation** — which files change, what new types or views are needed, how state flows. Reference actual file paths and existing patterns in the codebase.
- **What to avoid** — flag any traps or anti-patterns specific to this codebase (e.g. SwiftUI List font propagation, stale coordinator patterns, etc.)

Keep this tight. No padding.

### 6. Wait for approval

Present the user with three options:
1. **Approve** — proceed with implementation as proposed
2. **Revise** — user provides feedback; update the proposal and loop back to this step
3. **Abort** — stop without implementing anything

Do not write any code until the user explicitly approves.

### 7. Baseline build check

Before touching any code, confirm the current state of the repo builds cleanly:

```
xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -destination "platform=macOS" build 2>&1 | tail -3
```

If the build fails, stop and report — do not proceed on a broken baseline.

### 8. Implement in a feature branch

1. Branch name: `feature/$ARGUMENTS-<slug>` where slug is a short lowercase hyphenated description of the feature (e.g. `feature/33-explain-analyze-viewer`)
   ```
   git checkout -b feature/$ARGUMENTS-<slug>
   ```
2. Implement exactly what was approved — no scope creep
3. Follow all existing patterns in the codebase (font settings via `@AppStorage`, explicit `.font()` on List rows, etc.)
4. Build to confirm no regressions:
   ```
   xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -destination "platform=macOS" build 2>&1 | tail -3
   ```
   Do not proceed if the build fails.
5. Stage and commit only the files you changed:
   ```
   git add <changed files>
   git commit -m "feat: <short description>"
   ```

### 9. Push and open PR

```
git push -u origin feature/$ARGUMENTS-<slug>
gh pr create \
  --title "<concise title>" \
  --body "$(cat <<'EOF'
## Summary
<2–4 sentences describing what was built and why>

## Changes
- <file or component>: <what changed>
- ...

## What was not changed
<explicitly note anything adjacent that was considered but left out>

## How to test
<short, specific steps to verify the feature works>

Closes #$ARGUMENTS
EOF
)"
```

### 10. Confirm

Report the PR URL and summarise what was implemented.
