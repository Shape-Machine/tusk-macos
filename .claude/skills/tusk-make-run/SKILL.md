---
name: tusk-make-run
description: Run `make run` on the Tusk project (builds then launches the app) and diagnose any errors
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
---

# Tusk Make Run

Run `make run` to build and launch the Tusk app. This will kill any running Tusk instance, build the project, and open the freshly built app.

## Steps

### 1. Run

```
make run
```

Capture the full output.

### 2. Evaluate result

**If the command succeeds** (`** BUILD SUCCEEDED **` appears and the app opens):
- Report success concisely. No further action needed.

**If the command fails or produces errors:**
- Read the error output carefully.
- Identify the root cause. Common failure categories for this project:
  - **Compile errors** — Swift/ObjC syntax or type errors; pinpoint the file and line.
  - **Linker errors** — missing frameworks or libraries.
  - **Code signing / provisioning** — expired certificate, missing entitlement.
  - **Missing generated files** — project.yml out of sync; `xcodegen generate` may be needed first.
  - **xcodebuild not found** — Xcode not installed or `xcode-select` not pointing to the right path.
  - **App launch failure** — built OK but `open` failed (wrong APP path, sandbox issue).
- Present the user with:
  1. A clear one-line summary of what went wrong.
  2. The specific error line(s) from the output (file path and line number if available).
  3. Concrete recommended actions to resolve it.
- Do NOT attempt to auto-fix — just diagnose and recommend.
