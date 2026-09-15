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

## 2. GitHub Actions Secrets Configuration (Recommended)

To allow GitHub Actions to build signed release APKs without checking keys into the repository, add the following secrets under **Settings > Secrets and variables > Actions** in your GitHub repository:

| Secret Name | Description | Example / Command |
|---|---|---|
| `KEYSTORE_BASE64` | Base64-encoded string of your `.jks` file | `base64 -w 0 ~/musii-release-key.jks` |
| `KEYSTORE_PASSWORD` | Store password for the keystore | Your keystore password |
| `KEY_ALIAS` | Alias name for the key entry | `musii-key` |
| `KEY_PASSWORD` | Password for the key alias | Your key password |

### Converting Keystore to Base64:
On Linux/macOS:
```bash
base64 -w 0 ~/musii-release-key.jks
```
(On macOS, use `base64 -i ~/musii-release-key.jks | tr -d '\n'`).

Copy the entire output and paste it into the `KEYSTORE_BASE64` secret in GitHub.

---

## 3. Generating the Android Signing Report via GitHub Actions

Musii includes a dedicated workflow to extract and display the SHA-1 and SHA-256 certificate fingerprints directly inside GitHub Actions:

- **Workflow File**: [`.github/workflows/signing-report.yml`](../.github/workflows/signing-report.yml)
- **How to Run**:
  1. Go to the **Actions** tab in your GitHub repository.
  2. Select **Android Signing Report** in the left sidebar.
  3. Click **Run workflow** on the `main` branch.
  4. Once complete, click the workflow run:
     - The job summary page displays the formatted SHA-1 and SHA-256 fingerprints in markdown table format.
     - You can also download the `android-signing-report` artifact containing the full diagnostic dump.

---

## 4. Local Signing Configuration (Optional)

Create a file named `android/key.properties` (which is git-ignored by default):

```properties
storePassword=<YOUR_STORE_PASSWORD>
keyPassword=<YOUR_KEY_PASSWORD>
keyAlias=musii-key
storeFile=upload-keystore.jks
```

Place `upload-keystore.jks` inside `android/app/`.

In `android/app/build.gradle.kts`, the signing configs automatically load from `key.properties` when present:

```kotlin
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { path ->
                    val f = file(path)
                    if (f.exists()) f else rootProject.file(path)
                }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}
```

---

## 5. Automated GitHub Actions Release Workflow

- **Workflow File**: [`.github/workflows/build-apk.yml`](../.github/workflows/build-apk.yml)
- **Behavior**:
  - Automatically loads `KEYSTORE_BASE64` and credentials if configured.
  - Falls back gracefully to debug signing if secrets are not set yet.
  - Builds `app-release.apk` and uploads the artifact `musii-release-apk`.
