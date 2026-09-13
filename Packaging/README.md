# macOS release packaging

`background.svg` is the editable installation-window artwork. `background.tiff` contains 1× and 2× representations, so Finder can render it sharply on Retina displays. The app and Applications link remain real draggable Finder icons.

Release procedure:

1. Update the marketing version and build number with `asc xcode version edit` and commit the release source.
2. Archive the Release configuration for `generic/platform=macOS`, with `ONLY_ACTIVE_ARCH=NO` and both `arm64 x86_64` architectures.
3. Export the archive with Xcode's `developer-id` method, a Developer ID Application certificate, and hardened runtime.
4. ZIP the exported app with `ditto -c -k --keepParent`, submit it using `asc notarization submit`, wait for acceptance, then staple the app.
5. Run `Packaging/create-dmg.sh /path/to/AutoShell.app /path/to/AutoShell-version.dmg`. This requires `dmgbuild` (1.6.7 for this release; install it in a virtual environment). Set `DMGBUILD_BIN` to its executable if it is not on PATH. The layout metadata is written directly, independent of Finder tab preferences. When inspecting the image, use a separate Finder window; opening it in an existing tab can inherit that window’s sidebar and toolbar.
6. Sign the DMG with `codesign --timestamp`, submit the DMG for notarization, and staple it after acceptance.
7. Verify `codesign`, `stapler validate`, `spctl`, and `hdiutil verify`; mount the final DMG to inspect the layout and Applications link.
8. Publish the DMG and its SHA-256 checksum in a GitHub Release targeting the exact source commit.

Build archives, exported apps, credentials, and notarization logs belong outside the repository. Only the finished DMG and checksum are release assets.
