---
name: report-issue
description: Report a bug or problem — gathers details interactively, investigates the codebase, proposes a fix plan, then files a GitHub issue
disable-model-invocation: false
argument-hint: <brief description of the issue>
allowed-tools: Bash, Read, Glob, Grep, Task, AskUserQuestion
---

# Report Issue

Gather information about a bug or problem, investigate the relevant code, propose an implementation plan to fix it, and file a well-structured GitHub issue.

## Steps

### 1. Gather details

Use the argument as a starting point: `$ARGUMENTS`

Ask the user for any missing context needed to understand the problem:

- What did you expect to happen?
- What actually happened?
- How do you reproduce it? (steps, conditions)
- Is it consistent or intermittent?
- Any error messages or unexpected output?

Only ask what isn't already clear from `$ARGUMENTS`. Keep it to one round of questions — don't interrogate.

### 2. Investigate the codebase

Based on the reported problem, search the relevant source files:

- Find the code most likely responsible for the behaviour
- Identify the root cause or the most plausible cause
- Note any related code that may need to change
- Call out any patterns or constraints that affect how a fix should be approached (e.g. SwiftUI List font propagation, actor isolation, stale state patterns)

### 3. Propose a fix plan

Write a concise, specific fix plan:

- **Root cause** — what is broken and why
- **Fix** — exactly what needs to change, which files, which functions
- **What to avoid** — any traps specific to this area of the codebase

Keep it tight. This becomes the implementation plan in the issue.

### 4. Determine labels and milestone

Select appropriate labels from the available set:

```
gh label list
```

Always include `bug`. Add any other relevant labels (e.g. `data-browser`, `query-editor`, `schema`, `operations`).

Find the current milestone (the open milestone with the most open issues):

```
gh api repos/Shape-Machine/tusk-macos/milestones --jq 'sort_by(.open_issues) | reverse | .[0].title'
```

If no open milestones exist, omit the `--milestone` flag.

### 5. File the GitHub issue

```
gh issue create \
  --title "<concise title describing the bug>" \
  --label "<labels>" \
  --milestone "<current-milestone-title>" \
  --body "$(cat <<'EOF'
## Description
<1–3 sentences describing what is broken and the impact>

## Steps to Reproduce
<numbered steps>

## Expected Behaviour
<what should happen>

## Actual Behaviour
<what actually happens>

## Root Cause
<findings from code investigation>

## Implementation Plan
<specific fix: files, functions, what changes>

## What to Avoid
<any traps or constraints to keep in mind>
EOF
)"
```

### 6. Confirm

Report the issue URL.
