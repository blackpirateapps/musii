# Android Release & Signing Guide

This guide details configuring production release signing and producing distribution-ready APKs and App Bundles (AABs).

---

## 1. Generating a Release Keystore

Generate an upload keystore using `keytool`:

```bash
keytool -genkey -v -keystore ~/musii-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias musii-key
```

Keep your keystore file and passwords safe and never check them into git.

---

## 2. Configure Keystore in Gradle

Create a file named `android/key.properties` (which is git-ignored by default):

```properties
storePassword=<YOUR_STORE_PASSWORD>
keyPassword=<YOUR_KEY_PASSWORD>
keyAlias=musii-key
storeFile=/path/to/musii-release-key.jks
```

In `android/app/build.gradle.kts`, the signing configs load from `key.properties` when present:

```kotlin
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
```

---

## 3. Automated GitHub Actions Release Workflow

Musii includes a GitHub Actions workflow located at [`.github/workflows/build-apk.yml`](../.github/workflows/build-apk.yml).

### Build Pipeline:
1. Automatically triggers on every push to `main` and on pull requests.
2. Can be manually triggered via `workflow_dispatch` from the GitHub Actions console.
3. Automatically provisions Ubuntu runner, JDK 17, and Flutter stable.
4. Executes `build_runner`, `flutter analyze`, and `flutter test`.
5. Builds the production APK (`flutter build apk --release`).
6. Archives and uploads the release APK as a downloadable artifact.

### Downloading the Build Artifact:
1. Navigate to your Musii repository on GitHub.
2. Click the **Actions** tab.
3. Select the latest successful **Build Musii Android APK** run.
4. Under the **Artifacts** section, download `musii-release-apk`.
