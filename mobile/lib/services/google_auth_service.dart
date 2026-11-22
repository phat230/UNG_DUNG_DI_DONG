import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuth {
  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue:
        '718608016645-3app65fhp7t6togvq19arp4ut4ccffg5.apps.googleusercontent.com',
  );
  static bool get isConfigured => serverClientId.isNotEmpty;

  static Future<void> initialize() async {
    if (isConfigured) {
      await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    }
  }

  static Future<String> getIdToken() async {
    if (!isConfigured) {
      throw Exception(
        'Chưa cấu hình Google OAuth Client ID. Cần thêm GOOGLE_SERVER_CLIENT_ID khi build app.',
      );
    }
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception(
        'Google chưa trả ID token. Hãy kiểm tra cấu hình Web Client ID.',
      );
    }
    return idToken;
  }
}

