# Google Drive & Google Cloud Console Setup Guide

This guide walks you through configuring Google Cloud Platform (GCP) to allow Musii to connect to Google Drive and access personal audio libraries.

---

## 1. Create a Google Cloud Project

1. Open the [Google Cloud Console](https://console.cloud.google.com/).
2. Click the project dropdown at the top of the page and select **New Project**.
3. Name your project (e.g., `Musii Music Player`) and click **Create**.

---

## 2. Enable the Google Drive API

1. In the Google Cloud Console, navigate to **APIs & Services > Library**.
2. Search for `Google Drive API`.
3. Select **Google Drive API** and click **Enable**.

---

## 3. Configure OAuth Consent Screen

1. Navigate to **APIs & Services > OAuth consent screen**.
2. Choose **User Type**:
   - **External**: Allows any personal Google account to sign in.
3. Fill in the App Information:
   - **App name**: `Musii`
   - **User support email**: Your personal email.
   - **Developer contact information**: Your personal email.
4. Click **Save and Continue**.
5. On the **Scopes** page, click **Add or Remove Scopes**:
   - Add `https://www.googleapis.com/auth/drive.readonly` (Read-only access to Drive metadata and files).
   - Alternatively, for restricted folder access, `https://www.googleapis.com/auth/drive.file`.
6. On the **Test users** page:
   - Add your Google account email as a test user while the app is in "Testing" mode.
7. Click **Save and Continue**.

---

## 4. Create Android OAuth 2.0 Client ID

1. Navigate to **APIs & Services > Credentials**.
2. Click **Create Credentials > OAuth client ID**.
3. Select **Application type**: `Android`.
4. Fill in the required fields:
   - **Name**: `Musii Android Client`
   - **Package name**: `com.blackpirateapps.musii`
5. Retrieve your SHA-1 signing certificate fingerprint:

### Debug Keystore SHA-1 (for local testing):
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
```
Copy the `SHA1` string (e.g., `AA:BB:CC:DD:...`).

### Release Keystore SHA-1 (for production builds):
```bash
keytool -list -v -keystore /path/to/your-release-key.jks -alias your-alias
```

6. Paste the SHA-1 fingerprint into the GCP console.
7. Click **Create**.

---

## 5. Required OAuth Scopes in Musii

Musii requests the following scopes during sign-in:

| Scope | Purpose |
|---|---|
| `email` | Identify the connected Google user account. |
| `https://www.googleapis.com/auth/drive.readonly` | Recursively browse directories and download audio file binary streams. |

---

## 6. Verification & Troubleshooting

- **Error: `ApiException: 10`**:
  - Cause: SHA-1 fingerprint mismatch or package name mismatch between Android manifest and GCP OAuth client ID.
  - Solution: Verify that `com.blackpirateapps.musii` matches the GCP console and that the SHA-1 matches the active signing keystore.
- **Error: `Access blocked: App not verified`**:
  - Cause: App is in Testing status and your account is not added as a test user.
  - Solution: In the GCP Console under **OAuth consent screen > Test users**, add your Google email address.
