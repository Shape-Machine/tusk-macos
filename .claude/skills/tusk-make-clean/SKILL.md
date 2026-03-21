---
name: tusk-make-clean
description: Run `make clean` on the Tusk project and diagnose any errors
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
---

# Tusk Make Clean

Run `make clean` to remove Xcode build artifacts for the Tusk project.

## Steps

### 1. Run clean

```
make clean
```

Capture the full output.

### 2. Evaluate result

**If the command exits successfully** (`** CLEAN SUCCEEDED **` appears in output):
- Report success concisely. No further action needed.

**If the command fails or produces errors:**
- Read the error output carefully.
- Identify the root cause (e.g. missing project file, xcodebuild not found, scheme mismatch, DerivedData permissions issue, etc.).
- Present the user with:
  1. A clear one-line summary of what went wrong.
  2. The specific error line(s) from the output.
  3. Concrete recommended actions to resolve it (e.g. run `xcodegen generate` first, check Xcode installation, fix permissions on DerivedData, etc.).
- Do NOT attempt to auto-fix — just diagnose and recommend.
