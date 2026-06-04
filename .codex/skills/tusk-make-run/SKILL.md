---
name: tusk-make-run
description: "Use when the user asks to run `make run` for the Tusk macOS project, build and launch the app, or diagnose build and launch failures."
---

# Tusk Make Run

Run `make run` to build and launch the Tusk app. This kills any running Tusk instance, builds the project, and opens the freshly built app.

## Steps

### 1. Run

```sh
make run
```

Capture the full output.

### 2. Evaluate Result

If the command succeeds, `** BUILD SUCCEEDED **` appears, and the app opens, report success concisely.

If the command fails or produces errors:

1. Read the error output carefully.
2. Identify the root cause.
3. Present the user with a one-line summary, the specific error line or lines, and concrete recommended actions.

Common failure categories:

- Compile errors: pinpoint the Swift or Objective-C file and line.
- Linker errors: identify missing frameworks or libraries.
- Code signing or provisioning errors: call out expired certificates, missing entitlements, or provisioning issues.
- Missing generated files: `project.yml` may be out of sync and `xcodegen generate` may be needed.
- Missing `xcodebuild`: Xcode may be absent or `xcode-select` may point to the wrong path.
- App launch failure: the build succeeded but `open` failed due to the app path or sandbox state.

Do not auto-fix run failures unless the user explicitly asks for repairs.
