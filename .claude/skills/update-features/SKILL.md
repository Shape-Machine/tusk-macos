---
name: update-features
description: Scan source code for user-facing features, rewrite docs/features.md, commit and push
disable-model-invocation: false
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task
---

# Update Features Doc

Scan the Tusk source code, derive a complete and accurate list of user-facing features, rewrite `docs/features.md`, then commit and push.

## Steps

### 1. Scan the source code

Thoroughly read all Swift files under:
- `Tusk/Views/` — all subfolders
- `Tusk/State/AppState.swift` (or equivalent)
- `Tusk/Models/` if present

For each view and feature area, identify what the user can actually do. Focus on user-facing behaviour, not implementation details.

### 2. Rewrite docs/features.md

Overwrite `docs/features.md` with a fresh, accurate feature summary. Use the following structure and tone:

- Top-level heading: `# Tusk — Features`
- One `###` section per logical feature group (e.g. Connections, Schema Browser, Data Browser, Query Editor, File Explorer, Tabs, Appearance)
- Each section: one short sentence introducing the feature group, followed by a tight bullet list of capabilities
- Bullets are concise — one feature per bullet, no padding
- Include keyboard shortcuts inline where relevant (e.g. `⌘↵ run all`)
- Do not invent features; only document what is actually in the code

### 3. Commit and push

```
git add docs/features.md
git commit -m "docs: update features for <version>"
git push
```

Get the current version from `Tusk/Resources/Info.plist` (`CFBundleShortVersionString`) to use in the commit message.

### 4. Confirm
Report what changed and confirm the push succeeded.
