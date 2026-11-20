# TaskFlow mobile

## Google sign-in

- The Flutter app passes the Web OAuth Client ID as `serverClientId`; it is a public identifier, not a secret.
- Register an OAuth client of type **Android** using package `vn.edu.taskflow.taskflow_mobile` and the SHA-1 of the certificate that signed that build.
- Also register a **Web application** OAuth client. Its Client ID is the `serverClientId` and the expected ID-token audience configured by the API.
- Set API audience with `Google__ClientIds=<WEB_CLIENT_ID>` (plus other Web client IDs only when they are actually token audiences). The Android client is registered by package/SHA-1; do not use its ID as a substitute for the Web client ID.
- Debug and release builds signed with different certificates need their corresponding Android OAuth registrations. With Google Play App Signing, include the Play app-signing SHA-1 from Play Console.
- The debug Web Client ID in this repository is public. Never commit a client secret or credential JSON file.

For an APK using a different Web client, build with:

```powershell
flutter build apk --release `
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<WEB_CLIENT_ID> `
  --dart-define=TASKFLOW_API_URL=https://<api-domain>/api
```

## API access

On a physical Android phone connected by USB to the development PC, run the API and:

```powershell
adb reverse tcp:5000 tcp:5000
```

The current `127.0.0.1` URL is for local development only. Users installing a release need a public API URL over HTTPS.
