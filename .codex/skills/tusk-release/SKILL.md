---
name: tusk-release
description: "Use when preparing a full Tusk macOS release: bump the app version, regenerate the Xcode project, build and package the DMG, publish the GitHub release, and update README links."
---

# Tusk Release

Perform a full release of Tusk. Work directly on `main`; do not create a feature branch for releases.

## Version

Use the version provided by the user. If no version is provided, derive one with the `YYYY.MM.DD-NN` scheme:

1. Get today's date with `date +%Y.%m.%d`.
2. List existing tags for today with `git tag | grep "^v$(date +%Y.%m.%d)-"`.
3. If there are no tags for today, use `YYYY.MM.DD-00`.
4. If tags exist, increment the zero-padded counter.
5. Confirm the derived version with the user before proceeding.

## Workflow

### 1. Verify Starting State

- Run `git pull`.
- Confirm the current branch is `main`.
- Confirm the working tree is clean.
- If the branch is not `main` or the working tree is dirty, stop and report what the user needs to resolve.

### 2. Bump Version

Read the current values first, then update:

- `Tusk/Resources/Info.plist`: set `CFBundleShortVersionString` to the release version and increment `CFBundleVersion` by 1.
- `project.yml`: update the same two keys under `info:`.
- `README.md`: update both the displayed DMG filename and URL path, including `v<version>/Tusk-<version>.dmg`.

### 3. Regenerate Xcode Project

```sh
xcodegen generate
```

### 4. Build Release

```sh
xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -destination "platform=macOS" build
```

Confirm `** BUILD SUCCEEDED **` before continuing.

### 5. Package DMG

Get the built app path:

```sh
xcodebuild -project Tusk.xcodeproj -scheme Tusk -configuration Release -showBuildSettings | awk '$1 == "BUILT_PRODUCTS_DIR" {print $3}'
```

Replace the staged app with a fresh copy:

```sh
rm -rf dist/dmg-staging/Tusk.app
cp -R "$BUILT_PRODUCTS_DIR/Tusk.app" dist/dmg-staging/
```

Verify the staged app version:

```sh
defaults read "$(pwd)/dist/dmg-staging/Tusk.app/Contents/Info.plist" CFBundleShortVersionString
```

Check whether the DMG already exists:

```sh
ls dist/Tusk-<version>.dmg 2>/dev/null && echo "DMG already exists - stop" || echo "OK"
```

If it exists, stop and ask the user before overwriting. Otherwise create it:

```sh
hdiutil create -volname "Tusk" -srcfolder dist/dmg-staging -ov -format UDZO dist/Tusk-<version>.dmg
```

### 6. Commit, Tag, And Push

```sh
git add Tusk/Resources/Info.plist project.yml Tusk.xcodeproj README.md
git commit -m "chore: bump version to <version>"
git tag v<version>
git push
git push origin v<version>
```

### 7. Create GitHub Release

Summarize commits since the previous tag into release notes:

- `feat:` commits under **Features**
- `fix:` commits under **Fixes**
- design changes under **Design**
- everything else under **Other**

Always append this footer:

```md
---

> Not notarized. On first launch right-click -> **Open**, or run:
> ```
> xattr -d com.apple.quarantine /Applications/Tusk.app
> ```
```

Create the release:

```sh
gh release create v<version> dist/Tusk-<version>.dmg \
  --title "Tusk <version>" \
  --notes "<release notes>"
```

### 8. Confirm

Report the GitHub release URL and confirm all release steps completed successfully.
