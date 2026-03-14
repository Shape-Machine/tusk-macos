---
name: update-screenshots
description: Rename raw screenshot files to versioned names and update the README screenshots section
disable-model-invocation: true
argument-hint: <version>
allowed-tools: Bash, Read, Write, Edit, Glob
---

# Update Screenshots

Rename all screenshots in `screenshots/` to use the versioned naming scheme `$ARGUMENTS-NN.png` and update the README.

## Steps

### 1. Find and rename screenshots
- List all files in `screenshots/` sorted by modification time (oldest first)
- Rename them sequentially: `$ARGUMENTS-01.png`, `$ARGUMENTS-02.png`, etc.
- Use `mv` for each file

### 2. Update README screenshots section
- Read `README.md`
- Replace the entire `## Screenshots` section (from `## Screenshots` down to the next `---` separator) with a new section that:
  - Lists every renamed file as its own `<img>` tag on a separate row
  - Uses max width for GitHub rendering: `width="800"`
  - One image per row (no table, just stacked images)
  - Format:
    ```
    ## Screenshots

    ![Screenshot 01](screenshots/$ARGUMENTS-01.png)

    ![Screenshot 02](screenshots/$ARGUMENTS-02.png)

    ...
    ```

### 3. Confirm
Report the list of renamed files and confirm README was updated.
