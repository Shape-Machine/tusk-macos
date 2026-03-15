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

### 2. Rate importance

Score the issue on three axes, each 1–5:

- **Impact** — how many users does this affect, and how much does it improve their workflow?
- **Complexity** — how hard is this to implement correctly? (5 = very hard)
- **Risk** — could this break existing behaviour or introduce regressions? (5 = high risk)

Present as a concise table. Add a one-sentence verdict: **High / Medium / Low priority** with reasoning.

### 3. Review proposed UX and implementation guidelines

If the issue contains UX or implementation suggestions, extract them explicitly. Then:

- Search the codebase for the relevant files, views, and patterns that would be touched
- Assess whether the proposed approach fits the existing architecture and SwiftUI patterns used in the project
- Call out anything that looks off — wrong layer, inconsistent with how similar features work, or likely to cause SwiftUI state bugs

If the issue has no UX/implementation detail, skip this step and note that none was provided.

### 4. Propose implementation path

Based on your code review, propose:

- **UX** — exactly what the user sees and how they interact with it. Be specific: which view, which control, what triggers what.
- **Implementation** — which files change, what new types or views are needed, how state flows. Reference actual file paths and existing patterns in the codebase.
- **What to avoid** — flag any traps or anti-patterns specific to this codebase (e.g. SwiftUI List font propagation, stale coordinator patterns, etc.)

Keep this tight. No padding.

### 5. Wait for approval

Stop and ask the user:
- Does the proposed UX and implementation path look right?
- Any changes before proceeding?

Do not write any code until the user explicitly approves.

### 6. Implement in a feature branch

Once approved:

1. Derive a branch name from the issue title — lowercase, hyphenated, prefixed with `feature/` (e.g. `feature/explain-analyze-viewer`)
2. Create and switch to the branch:
   ```
   git checkout -b feature/<branch-name>
   ```
3. Implement exactly what was approved — no scope creep
4. Follow all existing patterns in the codebase (font settings via `@AppStorage`, explicit `.font()` on List rows, etc.)
5. Build to confirm no regressions:
   ```
   xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -destination "platform=macOS" build
   ```
6. Commit:
   ```
   git add <changed files>
   git commit -m "feat: <short description>"
   ```
7. Push and open a PR:
   ```
   git push -u origin feature/<branch-name>
   gh pr create --title "<title>" --body "<summary + closes #$ARGUMENTS>"
   ```

### 7. Confirm

Report the PR URL and summarise what was implemented.
