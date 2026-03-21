---
name: release
description: Full Tusk release — bump version, build DMG, publish GitHub release, update README
disable-model-invocation: true
argument-hint: <new-version>
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
---

# Tusk Release

Perform a full release of Tusk for version `$ARGUMENTS`.

Work directly on the `main` branch (no feature branch needed for releases).

## Steps

### 1. Verify starting state
- Pull the latest changes: `git pull`
- Confirm the current branch is `main` and the working tree is clean
- If not, stop and tell the user what needs to be resolved first

### 2. Bump version everywhere
Update the following files — replace the old `CFBundleShortVersionString` with `$ARGUMENTS` and increment `CFBundleVersion` by 1:
- `Tusk/Resources/Info.plist` — `CFBundleShortVersionString` and `CFBundleVersion`
- `project.yml` — same two keys under `info:`
- `README.md` — update the download link filename and URL (both the display text `Tusk-X.X.X.dmg` and the URL path `vX.X.X/Tusk-X.X.X.dmg`)

To find the current version and build number before editing, read those files first.

### 3. Regenerate Xcode project
```
xcodegen generate
```

### 4. Build Release
```
xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -destination "platform=macOS" build
```
Confirm `** BUILD SUCCEEDED **` before continuing.

### 5. Package the DMG
- Get the built app path from:
  ```
  xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -showBuildSettings | awk '$1 == "BUILT_PRODUCTS_DIR" {print $3}'
  ```
- Replace `dist/dmg-staging/Tusk.app` with the freshly built app — **always `rm -rf` first** so `cp -R` creates a fresh copy rather than copying into the existing bundle directory:
  ```
  rm -rf dist/dmg-staging/Tusk.app
  cp -R "$BUILT_PRODUCTS_DIR/Tusk.app" dist/dmg-staging/
  ```
- Verify the version in the staged app matches `$ARGUMENTS`:
  ```
  defaults read "$(pwd)/dist/dmg-staging/Tusk.app/Contents/Info.plist" CFBundleShortVersionString
  ```
- Check the DMG doesn't already exist:
  ```
  ls dist/Tusk-$ARGUMENTS.dmg 2>/dev/null && echo "DMG already exists — stop" || echo "OK"
  ```
  If the file already exists, stop and ask the user before overwriting.
- Create the DMG:
  ```
  hdiutil create -volname "Tusk" -srcfolder dist/dmg-staging -ov -format UDZO dist/Tusk-$ARGUMENTS.dmg
  ```

### 6. Commit, tag, and push
```
git add Tusk/Resources/Info.plist project.yml Tusk.xcodeproj README.md
git commit -m "chore: bump version to $ARGUMENTS"
git tag v$ARGUMENTS
git push
git push origin v$ARGUMENTS
```

### 7. Create GitHub release
```
gh release create v$ARGUMENTS dist/Tusk-$ARGUMENTS.dmg \
  --title "Tusk $ARGUMENTS" \
  --notes "<release notes>"
```

For the release notes, look at `git log` since the previous tag and summarise the commits into sections:
- **Features** — `feat:` commits
- **Fixes** — `fix:` commits
- **Design** / **Other** — everything else

Always append this footer to the release notes:
```
---

> Not notarized. On first launch right-click → **Open**, or run:
> \`\`\`
> xattr -d com.apple.quarantine /Applications/Tusk.app
> \`\`\`
```

### 8. Confirm
Report the GitHub release URL and confirm all steps completed successfully.
