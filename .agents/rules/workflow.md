---
name: workflow-rules
description: Strict workflow rules for the Musii project covering local build restrictions, verification, handoff updates, and git commits.
always_on: true
---

# Musii Project Workflow Rules

## 1. No Local APK Builds
- **CRITICAL**: Do NOT execute `flutter build apk` or local Gradle build tasks in this environment.
- APK builds and releases are automated through GitHub Actions CI (`.github/workflows/build-apk.yml`).

## 2. Verification Protocol
- Static analysis: `flutter analyze` must produce 0 issues.
- Automated tests: `flutter test` must run and pass with 100% success across all unit, widget, and integration tests.

## 3. AI Handoff Updates
- Keep `docs/ai-handoff.md` continuously updated with any architectural changes, schema additions, or new components.

## 4. Git Commit & Push
- Commit all changes with descriptive commit messages and push to the remote git branch.
