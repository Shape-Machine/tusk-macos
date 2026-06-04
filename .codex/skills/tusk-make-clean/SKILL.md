---
name: tusk-make-clean
description: "Use when the user asks to run `make clean` for the Tusk macOS project or diagnose failures while cleaning Xcode build artifacts."
---

# Tusk Make Clean

Run `make clean` to remove Xcode build artifacts for the Tusk project.

## Steps

### 1. Run Clean

```sh
make clean
```

Capture the full output.

### 2. Evaluate Result

If the command exits successfully and `** CLEAN SUCCEEDED **` appears, report success concisely.

If the command fails or produces errors:

1. Read the error output carefully.
2. Identify the root cause, such as a missing project file, unavailable `xcodebuild`, scheme mismatch, or DerivedData permission issue.
3. Present the user with a one-line summary, the specific error line or lines, and concrete recommended actions.

Do not auto-fix clean failures unless the user explicitly asks for repairs.
