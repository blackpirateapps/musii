# Musii — Project Workflow Rules

## 1. No Local APK Builds
- **Rule**: NEVER run `flutter build apk` or Gradle APK build commands locally in this development environment.
- **Rationale**: Local Android SDK/NDK/Gradle environments are constrained. APK building and release artifact signing are strictly delegated to GitHub Actions CI (`.github/workflows/build-apk.yml`).

## 2. Quality Verification Standard
- Run `flutter analyze` — Must maintain 0 issues/warnings.
- Run `flutter test` — All tests (unit, widget, integration) must pass with 100% success.
- Do not suppress linter errors or warnings with indiscriminate ignores.

## 3. Engineering Handoff Maintenance
- When modifying database schemas, core audio services, lyrics parsing, or playback pipelines, update `docs/ai-handoff.md` to document changes and pitfalls.

## 4. Git Workflow
- Always stage and commit all modified and newly created files with clear, descriptive commit messages.
- Push commits to the remote branch upon completion of the task.
