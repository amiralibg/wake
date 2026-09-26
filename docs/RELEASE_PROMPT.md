# Release Wake v0.1.0 on GitHub

Paste everything below the line into a new Claude Code session opened on this repo.

---

You're publishing the first release of **Wake**, my native macOS browser, on GitHub as **v0.1.0**. Read `HANDOFF.md` and the README's **Installing** and **Releasing** sections first. Then read `.github/workflows/release.yml` and `.github/workflows/build.yml` end to end before running anything.

Repo: https://github.com/amiralibg/wake (branch `main`). Use the `gh` CLI.

## Ground rules

- **Ask me before every outward-facing step:** committing, pushing, setting secrets, creating tags, publishing or editing a release. Show me exactly what will happen, then wait for a yes. Approval for one step doesn't cover the next.
- Never print, paste or commit the private signing key. It lives at `~/.wake-release/sparkle_private_key`; only pipe it into `gh secret set`.
- Report every problem as it happens, with the log. Don't retry blindly and don't work around failures silently.
- Keep builds free of errors and warnings.

## Steps

1. **Check the working tree.**
   - Run `git status`, `git log --oneline -5` and `git diff --stat`.
   - If the round-10/11 work isn't committed yet, propose focused commits and wait for my approval. Suggested split:
     1. DevTools, search engines, onboarding and performance.
     2. History, searches and import.
     3. Sparkle auto-update and release workflows.
     4. Docs and the test site.
   - Commit messages end with the co-author line from this session's instructions.

2. **Build locally as CI will.**
   - Run `xcodegen generate`, then build Release with `MARKETING_VERSION=0.1.0 CURRENT_PROJECT_VERSION=<commit count>`.
   - Confirm no warnings, `codesign --verify --deep --strict` passes, and Info.plist has `SUFeedURL`, `SUPublicEDKey` and version 0.1.0.
   - Launch the Release build and check Wake ▸ Check for Updates… runs without error. Before the first release it should say the feed can't be found or that there's nothing newer.

3. **Check the workflow will run.**
   - Is the `macos-26` runner label available on GitHub-hosted runners today?
   - Does `setup-xcode latest-stable` give Xcode 26 or later, which the macOS 26 SDK for Liquid Glass needs? If not, pin the Xcode version or change the runner, and tell me what you changed.
   - Check the `build.yml` run on `main` is green after pushing (ask before pushing).

4. **Add the signing secret** (ask first):
   ```bash
   gh secret set SPARKLE_PRIVATE_KEY < ~/.wake-release/sparkle_private_key
   ```
   Confirm it exists with `gh secret list` (names only). Don't add the Developer ID secrets unless I give you a certificate. Without them the build is signed ad hoc.

5. **Tag and release** (ask first):
   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```
   Watch the run with `gh run watch`. If it fails, read the failing step's log (`gh run view --log-failed`), explain the cause, propose a fix, and ask before re-running. To retry after fixing, delete and re-push the tag only with my approval.

6. **Verify the release.**
   - Assets: `Wake-0.1.0.dmg`, `Wake-0.1.0.zip` and `appcast.xml`.
   - `https://github.com/amiralibg/wake/releases/latest/download/appcast.xml` downloads.
   - The appcast has version 0.1.0, a `sparkle:edSignature`, and a length matching the zip.
   - Verify the zip's EdDSA signature against the public key in `project.yml`, using Sparkle's `sign_update --verify` or a small CryptoKit check.
   - Download the DMG, install it to /Applications (it's ad-hoc signed, so macOS asks first: System Settings ▸ Privacy & Security ▸ Open Anyway), launch it, and confirm the version in Settings ▸ General ▸ Updates.

7. **Polish the release page.** Propose release notes and ask before editing:
   - a short intro;
   - the headline features (the trail, the Deck, Moments, Pop Out, History and import, DevTools, Zen, auto-update);
   - install steps, including the Gatekeeper note;
   - known limitations: Web Inspector via private SPI, Safari import needs Full Disk Access, and IndexedDB/caches don't move between engines.

   Optionally attach the teaser from `build/teaser/Wake-teaser.mp4` if it exists.

8. **Test the update path, later.** Sparkle only offers an update when a newer release exists, so tell me how to check it once v0.1.1 ships. Also say what's unproven with ad-hoc signing: Sparkle's code-signature check between builds, and macOS asking whether the new build may keep the old container's data.

## Report

End with:
- The release URL.
- The asset list with sizes.
- The workflow run URL and duration.
- What you verified and how.
- Anything that needed fixing.
- Anything still unproven.
