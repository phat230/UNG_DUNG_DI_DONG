import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  try {
    await GoogleAuth.initialize();
  } catch (e) {
    debugPrint('GoogleAuth init error: $e');
  }
  try {
    await ReminderNotifications.initialize();
  } catch (e) {
    debugPrint('ReminderNotifications init error: $e');
  }
  runApp(const TaskFlowApp());
}

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

class ReminderNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Reminder notification init error: $e');
    }
  }

  static Future<void> schedule({
    required int taskId,
    required String title,
    required DateTime firstAt,
    required DateTime until,
    required int everyMinutes,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await cancel(taskId);
      final start = firstAt.isAfter(DateTime.now())
          ? firstAt
          : DateTime.now().add(Duration(minutes: everyMinutes));
      final available = await _plugin.pendingNotificationRequests();
      final count = ((until.difference(start).inMinutes ~/ everyMinutes) + 1)
          .clamp(0, (450 - available.length).clamp(0, 450));
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'task_reminders',
          'Nhắc công việc',
          channelDescription: 'Nhắc bạn hoàn thành công việc đúng hạn',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );
      for (var i = 0; i < count; i++) {
        final at = start.add(Duration(minutes: everyMinutes * i));
        await _plugin.zonedSchedule(
          taskId * 1000 + i,
          'Đến hạn công việc',
          title,
          tz.TZDateTime.from(at, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'task:$taskId',
        );
      }
    } catch (e) {
      debugPrint('Schedule notification error: $e');
    }
  }

  static Future<void> cancel(int taskId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final item in pending.where((item) => item.id ~/ 1000 == taskId)) {
        await _plugin.cancel(item.id);
      }
    } catch (e) {
      debugPrint('Cancel notification error: $e');
    }
  }

  static Future<void> showNotice(int id, String title, String body) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _plugin.show(
        id + 100000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'task_notices',
            'Thông báo nhóm',
            channelDescription: 'Thông báo liên quan đến công việc nhóm',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('Show notice error: $e');
    }
  }
}

class TaskFlowApp extends StatefulWidget {
  const TaskFlowApp({super.key});
  @override
  State<TaskFlowApp> createState() => _TaskFlowAppState();
}

class _TaskFlowAppState extends State<TaskFlowApp> {
  bool? signedIn;
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => signedIn = prefs.getString('jwt') != null);
  }

  void _onAuth() => setState(() => signedIn = true);
  void _onLogout() => setState(() => signedIn = false);
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TaskFlow',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4759d6)),
      useMaterial3: true,
    ),
    home: signedIn == null
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : signedIn!
        ? TaskHome(onLogout: _onLogout)
        : LoginPage(onLogin: _onAuth),
  );
}

class Api {
  // Android emulator reaches the host computer through 10.0.2.2.
  static const baseUrl = String.fromEnvironment(
    'TASKFLOW_API_URL',
    defaultValue: 'http://127.0.0.1:5000/api',
  );
  static Future<void> login(String username, String password) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userName': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200)
      throw Exception(
        'Đăng nhập thất bại. Kiểm tra tài khoản và trạng thái API.',
      );
    await _storeSession(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<String?> requestPasswordReset(String email) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email}),
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        body['message'] ?? 'Không gửi được yêu cầu đặt lại mật khẩu.',
      );
    }
    return body['debugResetToken'] as String?;
  }

  static Future<void> resetPassword(
    String email,
    String token,
    String newPassword,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'token': token,
            'newPassword': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['message'] ?? 'Không thể đặt lại mật khẩu.');
    }
  }

  static Future<void> loginWithGoogle(String idToken) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/google/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'idToken': idToken}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Không thể đăng nhập bằng Google.');
    }
    await _storeSession(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<void> _storeSession(Map<String, dynamic> body) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt', body['token'] as String);
    await prefs.setString('userId', body['user']['id'] as String);
    await prefs.setString(
      'displayName',
      body['user']['displayName'] as String? ??
          body['user']['userName'] as String? ??
          '',
    );
    await prefs.setBool(
      'isAdmin',
      (body['user']['roles'] as List).contains('Admin'),
    );
  }

  static Future<Map<String, dynamic>> getProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .get(
          Uri.parse('$baseUrl/auth/me'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('Không tải được hồ sơ tài khoản.');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/auth/change-password'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({
            'currentPassword': currentPassword,
            'newPassword': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final body = r.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(
        body['message'] ??
            body['errors']?.toString() ??
            'Không đổi được mật khẩu.',
      );
    }
  }

  static Future<List<Map<String, dynamic>>> getPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .get(
          Uri.parse('$baseUrl/plans'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200)
      throw Exception('Không tải được kế hoạch công việc.');
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> createPlan(String name, List<int> taskIds) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/plans'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({'name': name, 'taskIds': taskIds}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không tạo được kế hoạch: ${r.body}');
  }

  static Future<void> addPlanItem(int planId, int taskId, int sortOrder) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/plans/$planId/items'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({'taskId': taskId, 'sortOrder': sortOrder}),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không thêm được công việc vào kế hoạch.');
  }

  static Future<void> updatePlanItem(
    int planId,
    int taskId,
    int sortOrder,
    DateTime? plannedFor,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .put(
          Uri.parse('$baseUrl/plans/$planId/items/$taskId'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({
            'sortOrder': sortOrder,
            'plannedFor': plannedFor?.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không cập nhật được lịch kế hoạch.');
  }

  static Future<void> removePlanItem(int planId, int taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .delete(
          Uri.parse('$baseUrl/plans/$planId/items/$taskId'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không gỡ được công việc khỏi kế hoạch.');
  }

  static Future<void> confirmPlan(int planId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/plans/$planId/confirm'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không xác nhận được kế hoạch.');
  }

  static Future<void> deletePlan(int planId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .delete(
          Uri.parse('$baseUrl/plans/$planId'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không xóa được kế hoạch.');
  }

  static Future<void> linkGoogle(String idToken) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/auth/google/link'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({'idToken': idToken}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Không thể liên kết Google.');
    }
  }

  static Future<void> register(
    String name,
    String email,
    String username,
    String password,
    String accountType,
    String? groupName,
  ) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/register'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'displayName': name,
            'email': email,
            'userName': username,
            'password': password,
            'accountType': accountType,
            'groupName': groupName,
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200)
      throw Exception(
        'Đăng ký chưa thành công. Tên đăng nhập/email có thể đã được sử dụng.',
      );
  }

  static Future<Map<String, dynamic>?> getMyGroup() async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .get(
          Uri.parse('$baseUrl/groups/mine'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('Không lấy được thông tin nhóm.');
    return (jsonDecode(r.body) as Map<String, dynamic>)['group']
        as Map<String, dynamic>?;
  }

  static Future<Map<String, dynamic>?> getGroup(int workspaceId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .get(
          Uri.parse('$baseUrl/groups/$workspaceId'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    return (jsonDecode(r.body) as Map<String, dynamic>)['group']
        as Map<String, dynamic>?;
  }

  static Future<Map<String, dynamic>> createGroup(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/groups'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({'name': name}),
        )
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw Exception(body['message'] ?? 'Không thể tạo nhóm.');
    }
    return body;
  }

  static Future<Map<String, dynamic>> joinGroup(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/groups/join'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({'joinCode': code}),
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) {
      final message =
          (jsonDecode(r.body) as Map<String, dynamic>)['message'] ??
          'Không thể tham gia nhóm.';
      throw Exception(message);
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<void> leaveGroup(int workspaceId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/groups/$workspaceId/leave'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final body = r.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Không thể rời nhóm.');
    }
  }

  static Future<List<Map<String, dynamic>>> getGroupHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .get(
          Uri.parse('$baseUrl/groups/history'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('Không tải được lịch sử nhóm.');
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> requestRework(int taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .post(
          Uri.parse('$baseUrl/tasks/$taskId/request-rework'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final body = r.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(r.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? 'Không thể yêu cầu làm lại.');
    }
  }

  static Future<List<Map<String, dynamic>>> getNotices() async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .get(
          Uri.parse('$baseUrl/tasks/notices'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getNoticeHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .get(
          Uri.parse('$baseUrl/tasks/notices/history'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return [];
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> markNoticeRead(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await http
        .put(
          Uri.parse('$baseUrl/tasks/notices/$id/read'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
  }

  static Future<TaskPageData> getTaskPage({
    String? ownerId,
    String? q,
    int? workspaceId,
    bool personalOnly = false,
    DateTime? from,
    DateTime? to,
    int? categoryId,
    int? status,
    int page = 1,
    int pageSize = 20,
    String sort = 'newest',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt');
    final uri = Uri.parse('$baseUrl/tasks').replace(
      queryParameters: {
        'page': '$page',
        'pageSize': '$pageSize',
        'sort': sort,
        if (ownerId != null) 'ownerId': ownerId,
        if (q != null && q.isNotEmpty) 'q': q,
        if (workspaceId != null) 'workspaceId': '$workspaceId',
        if (personalOnly) 'personalOnly': 'true',
        if (from != null) 'from': from.toUtc().toIso8601String(),
        if (to != null) 'to': to.toUtc().toIso8601String(),
        if (categoryId != null) 'categoryId': '$categoryId',
        if (status != null) 'status': '$status',
      },
    );
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200)
      throw Exception('Không tải được công việc từ API.');
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (data['items'] as List).map((raw) {
      final item = raw as Map<String, dynamic>;
      final due = item['dueAt'] as String?;
      return TaskItem(
        item['id'] as int,
        item['title'] as String,
        item['status'] == 2,
        due == null ? 'Chưa đặt hạn' : due.substring(0, 10),
        description: item['description'] as String? ?? '',
        dueAt: due == null ? null : DateTime.tryParse(due),
        reminderIntervalMinutes: item['reminderIntervalMinutes'] as int?,
        reminderUntil: DateTime.tryParse(
          item['reminderUntil'] as String? ?? '',
        ),
        assignedToUserId: item['ownerId'] as String?,
        workspaceId: item['workspaceId'] as int?,
        locked: item['isLocked'] as bool? ?? item['status'] == 2,
        categoryId: item['categoryId'] as int?,
        createdAt: DateTime.tryParse(item['createdAt'] as String? ?? ''),
        priority: item['priority'] as int? ?? 1,
        status: item['status'] as int? ?? 0,
      );
    }).toList();
    return TaskPageData(items, data['total'] as int, page, pageSize);
  }

  static Future<List<TaskItem>> getTasks({
    String? ownerId,
    String? q,
    int? workspaceId,
    bool personalOnly = false,
    DateTime? from,
    DateTime? to,
  }) async => (await getTaskPage(
    ownerId: ownerId,
    q: q,
    workspaceId: workspaceId,
    personalOnly: personalOnly,
    from: from,
    to: to,
    pageSize: 100,
  )).items;
  static Future<void> updateTask({
    required int id,
    required String title,
    required String description,
    required int? categoryId,
    required DateTime? dueAt,
    required int priority,
    required int status,
    int? workspaceId,
    String? assignedToUserId,
    int? reminderIntervalMinutes,
    DateTime? reminderUntil,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http
        .put(
          Uri.parse('$baseUrl/tasks/$id'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({
            'title': title,
            'description': description,
            'categoryId': categoryId,
            'dueAt': dueAt?.toUtc().toIso8601String(),
            'priority': priority,
            'status': status,
            'workspaceId': workspaceId,
            'assignedToUserId': assignedToUserId,
            'reminderIntervalMinutes': reminderIntervalMinutes,
            'reminderUntil': reminderUntil?.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw Exception('Không cập nhật được công việc.');
  }

  static Future<int> createTask({
    required String title,
    required String description,
    int? categoryId,
    int priority = 1,
    int status = 0,
    DateTime? dueAt,
    int? workspaceId,
    String? assignedToUserId,
    int? reminderIntervalMinutes,
    DateTime? reminderUntil,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http
        .post(
          Uri.parse('$baseUrl/tasks'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode({
            'title': title,
            'description': description,
            'categoryId': categoryId,
            'priority': priority,
            'status': status,
            'workspaceId': workspaceId,
            'assignedToUserId': assignedToUserId,
            'dueAt': dueAt?.toUtc().toIso8601String(),
            'reminderIntervalMinutes': reminderIntervalMinutes,
            'reminderUntil': reminderUntil?.toUtc().toIso8601String(),
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw Exception('Không lưu được công việc lên API.');
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as int;
  }

  static Future<void> setTaskStatus(int taskId, int status) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .patch(
          Uri.parse('$baseUrl/tasks/$taskId/status'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode(status),
        )
        .timeout(const Duration(seconds: 12));
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không cập nhật được trạng thái công việc.');
  }

  static Future<void> deleteTask(int taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http
        .delete(
          Uri.parse('$baseUrl/tasks/$taskId'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = response.body.isEmpty
          ? 'Bạn không có quyền xóa nhiệm vụ này.'
          : (jsonDecode(response.body) as Map<String, dynamic>)['message'] ??
                'Không thể xóa nhiệm vụ.';
      throw Exception(message);
    }
  }

  static Future<List<Map<String, dynamic>>> getTaskAttachments(
    int taskId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http
        .get(
          Uri.parse('$baseUrl/tasks/$taskId/attachments'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200)
      throw Exception('Không tải được tệp đính kèm.');
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> uploadTaskAttachment(
    int taskId,
    PlatformFile file,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/tasks/$taskId/attachments'),
    );
    request.headers['Authorization'] = 'Bearer ${prefs.getString('jwt')}';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        await file.readAsBytes(),
        filename: file.name,
      ),
    );
    final streamed = await request.send().timeout(const Duration(seconds: 40));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = response.body.isEmpty
          ? 'Không tải tệp lên được.'
          : (jsonDecode(response.body) as Map<String, dynamic>)['message'] ??
                'Không tải tệp lên được.';
      throw Exception(message);
    }
  }

  static Future<Uint8List> downloadTaskAttachment(
    int taskId,
    int attachmentId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http
        .get(
          Uri.parse(
            '$baseUrl/tasks/$taskId/attachments/$attachmentId/download',
          ),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) throw Exception('Không tải được tệp.');
    return response.bodyBytes;
  }

  static Future<void> deleteTaskAttachment(int taskId, int attachmentId) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http
        .delete(
          Uri.parse('$baseUrl/tasks/$taskId/attachments/$attachmentId'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 204)
      throw Exception('Không xóa được tệp đính kèm.');
  }

  static Future<void> syncPending() async {
    if (kIsWeb) return;
    final db = await TaskStore.db;
    final rows = await db.query(
      'sync_queue',
      where: 'entity=?',
      whereArgs: ['task'],
      orderBy: 'id',
    );
    final prefs = await SharedPreferences.getInstance();
    for (final row in rows) {
      final isUpdate = row['operation'] == 'update';
      final response =
          await (isUpdate
                  ? http.put(
                      Uri.parse('$baseUrl/tasks/${row['entityId']}'),
                      headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer ${prefs.getString('jwt')}',
                      },
                      body: row['payload'] as String,
                    )
                  : http.post(
                      Uri.parse('$baseUrl/tasks'),
                      headers: {
                        'Content-Type': 'application/json',
                        'Authorization': 'Bearer ${prefs.getString('jwt')}',
                      },
                      body: row['payload'] as String,
                    ))
              .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) break;
      await db.delete('sync_queue', where: 'id=?', whereArgs: [row['id']]);
    }
  }

  static Future<List<Map<String, dynamic>>> getCategories() async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http
        .get(
          Uri.parse('$baseUrl/categories'),
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('Không tải được danh mục.');
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> saveCategory({
    int? id,
    required String name,
    required String color,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${prefs.getString('jwt')}',
    };
    final uri = Uri.parse('$baseUrl/categories${id == null ? '' : '/$id'}');
    final r = id == null
        ? await http.post(
            uri,
            headers: headers,
            body: jsonEncode({'name': name, 'color': color}),
          )
        : await http.put(
            uri,
            headers: headers,
            body: jsonEncode({'name': name, 'color': color}),
          );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không lưu được danh mục. Tên có thể đã tồn tại.');
  }

  static Future<void> deleteCategory(int id) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.delete(
      Uri.parse('$baseUrl/categories/$id'),
      headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
    );
    if (r.statusCode == 409)
      throw Exception('Danh mục còn công việc sử dụng nên không thể xóa.');
    if (r.statusCode != 204) throw Exception('Không xóa được danh mục.');
  }

  static Future<List<Map<String, dynamic>>> getMembers({
    String? q,
    DateTime? createdFrom,
    DateTime? createdTo,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final uri = Uri.parse('$baseUrl/admin/members').replace(
      queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        if (createdFrom != null) 'createdFrom': createdFrom.toIso8601String(),
        if (createdTo != null) 'createdTo': createdTo.toIso8601String(),
      },
    );
    final r = await http
        .get(
          uri,
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200)
      throw Exception('Không tải được danh sách thành viên.');
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getAdminGroups({String? q}) async {
    final prefs = await SharedPreferences.getInstance();
    final uri = Uri.parse(
      '$baseUrl/admin/groups',
    ).replace(queryParameters: {if (q != null && q.isNotEmpty) 'q': q});
    final r = await http
        .get(
          uri,
          headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) throw Exception('Không tải được danh sách nhóm.');
    return (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> createAdminMember({
    required String username,
    required String displayName,
    required String email,
    required String password,
    required String role,
    int? workspaceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.post(
      Uri.parse('$baseUrl/admin/members'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${prefs.getString('jwt')}',
      },
      body: jsonEncode({
        'userName': username,
        'displayName': displayName,
        'email': email,
        'password': password,
        'role': role,
        'workspaceId': workspaceId,
      }),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception(
        'Không tạo được tài khoản. Hãy kiểm tra username, email và mật khẩu.',
      );
  }

  static Future<void> createAdminGroup(String name, String leaderUserId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.post(
      Uri.parse('$baseUrl/admin/groups'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${prefs.getString('jwt')}',
      },
      body: jsonEncode({'name': name, 'leaderUserId': leaderUserId}),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception(
        'Không tạo được nhóm. Nhóm trưởng có thể đã tham gia nhóm khác.',
      );
  }

  static Future<void> addMemberToGroup(int groupId, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.post(
      Uri.parse('$baseUrl/admin/groups/$groupId/members'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${prefs.getString('jwt')}',
      },
      body: jsonEncode({'userId': userId}),
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception(
        'Không thêm được thành viên vào nhóm. Tài khoản có thể đã thuộc nhóm khác.',
      );
  }

  static Future<void> removeMemberFromGroup(int groupId, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.delete(
      Uri.parse('$baseUrl/admin/groups/$groupId/members/$userId'),
      headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
    );
    if (r.statusCode != 204)
      throw Exception('Không xóa được thành viên khỏi nhóm.');
  }

  static Future<void> setMemberRole(String id, String role) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.put(
      Uri.parse('$baseUrl/admin/members/$id/role'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${prefs.getString('jwt')}',
      },
      body: jsonEncode({'role': role}),
    );
    if (r.statusCode != 204) throw Exception('Không cập nhật được vai trò.');
  }

  static Future<void> setMemberActive(String id, bool active) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.put(
      Uri.parse('$baseUrl/admin/members/$id/status'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${prefs.getString('jwt')}',
      },
      body: jsonEncode({'isActive': active}),
    );
    if (r.statusCode != 204)
      throw Exception('Không cập nhật được trạng thái thành viên.');
  }

  static Future<void> setTaskDone(TaskItem task) async {
    final prefs = await SharedPreferences.getInstance();
    final response = await http
        .patch(
          Uri.parse('$baseUrl/tasks/${task.id}/status'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${prefs.getString('jwt')}',
          },
          body: jsonEncode(task.done ? 0 : 2),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300)
      throw Exception('Không cập nhật được công việc trên API.');
  }
}

Future<void> openChangePasswordDialog(BuildContext context) async {
  final current = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  var busy = false;
  String? error;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setStateDialog) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: current,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu hiện tại',
                ),
              ),
              TextField(
                controller: next,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu mới (8 ký tự, có số)',
                ),
              ),
              TextField(
                controller: confirm,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nhập lại mật khẩu mới',
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    setStateDialog(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      if (next.text.length < 8 ||
                          !RegExp(r'\d').hasMatch(next.text))
                        throw Exception(
                          'Mật khẩu mới cần ít nhất 8 ký tự và có số.',
                        );
                      if (next.text != confirm.text)
                        throw Exception('Hai mật khẩu mới chưa khớp.');
                      await Api.changePassword(current.text, next.text);
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đã đổi mật khẩu.')),
                        );
                    } catch (e) {
                      setStateDialog(
                        () => error = e.toString().replaceFirst(
                          'Exception: ',
                          '',
                        ),
                      );
                    } finally {
                      setStateDialog(() => busy = false);
                    }
                  },
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cập nhật'),
          ),
        ],
      ),
    ),
  );
  current.dispose();
  next.dispose();
  confirm.dispose();
}

Future<void> openGoogleLinkSettings(BuildContext context) async {
  try {
    final profile = await Api.getProfile();
    if (!context.mounted) return;
    final email = profile['email'] as String? ?? '';
    final linked = profile['googleLinked'] == true;
    if (linked) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Google đã liên kết'),
          content: Text('Tài khoản $email đã được liên kết với Google.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Liên kết tài khoản Google'),
        content: Text(
          'Liên kết Google với tài khoản TaskFlow $email để lần sau đăng nhập nhanh hơn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Để sau'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.link),
            label: const Text('Liên kết Google'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final idToken = await GoogleAuth.getIdToken();
    await Api.linkGoogle(idToken);
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã liên kết Google với tài khoản TaskFlow.'),
        ),
      );
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});
  final VoidCallback onLogin;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final user = TextEditingController();
  final pass = TextEditingController();
  final name = TextEditingController();
  final email = TextEditingController();
  final groupName = TextEditingController();
  bool busy = false;
  bool register = false;
  bool obscurePassword = true;
  String accountType = 'Personal';
  String? error;

  Future<void> signInWithGoogle() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final token = await GoogleAuth.getIdToken();
      await Api.loginWithGoogle(token);
      widget.onLogin();
    } catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> forgotPassword() async {
    final emailController = TextEditingController(
      text: user.text.contains('@') ? user.text.trim() : '',
    );
    final tokenController = TextEditingController();
    final passwordController = TextEditingController();
    var requested = false;
    var working = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Đặt lại mật khẩu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Nhập email đã đăng ký. Chúng tôi sẽ gửi mã đặt lại mật khẩu đến email đó.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  enabled: !requested && !working,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email tài khoản',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (requested) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: tokenController,
                    enabled: !working,
                    decoration: const InputDecoration(
                      labelText: 'Mã đặt lại mật khẩu',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    enabled: !working,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mật khẩu mới (ít nhất 8 ký tự, có số)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (dialogError != null) ...[
                  const SizedBox(height: 12),
                  Text(dialogError!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
            FilledButton(
              onPressed: working
                  ? null
                  : () async {
                      setDialogState(() {
                        working = true;
                        dialogError = null;
                      });
                      try {
                        if (!requested) {
                          if (!emailController.text.trim().contains('@')) {
                            throw Exception('Hãy nhập email hợp lệ.');
                          }
                          final debugToken = await Api.requestPasswordReset(
                            emailController.text.trim(),
                          );
                          tokenController.text = debugToken ?? '';
                          setDialogState(() {
                            requested = true;
                          });
                        } else {
                          if (tokenController.text.trim().isEmpty)
                            throw Exception('Hãy nhập mã nhận được qua email.');
                          if (passwordController.text.length < 8 ||
                              !RegExp(
                                r'\d',
                              ).hasMatch(passwordController.text)) {
                            throw Exception(
                              'Mật khẩu cần ít nhất 8 ký tự và có ít nhất một chữ số.',
                            );
                          }
                          await Api.resetPassword(
                            emailController.text.trim(),
                            tokenController.text.trim(),
                            passwordController.text,
                          );
                          if (dialogContext.mounted)
                            Navigator.pop(dialogContext);
                          if (mounted)
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đổi mật khẩu thành công. Hãy đăng nhập bằng mật khẩu mới.',
                                ),
                              ),
                            );
                        }
                      } catch (e) {
                        setDialogState(
                          () => dialogError = e.toString().replaceFirst(
                            'Exception: ',
                            '',
                          ),
                        );
                      } finally {
                        setDialogState(() => working = false);
                      }
                    },
              child: working
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(requested ? 'Đặt lại mật khẩu' : 'Gửi mã'),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
    tokenController.dispose();
    passwordController.dispose();
  }

  Future<void> submit() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (register)
        await Api.register(
          name.text.trim(),
          email.text.trim(),
          user.text.trim(),
          pass.text,
          accountType,
          accountType == 'Group' ? groupName.text.trim() : null,
        );
      await Api.login(user.text.trim(), pass.text);
      widget.onLogin();
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xfff4f6fc),
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffeef1ff), Color(0xfff8f9ff), Color(0xfff4f6fc)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xff5669e8), Color(0xff7b61d1)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xff5669e8).withValues(alpha: .24),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'TaskFlow',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    register
                        ? 'Tạo không gian làm việc của bạn'
                        : 'Sắp xếp công việc. Giữ nhịp mỗi ngày.',
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: Colors.blueGrey),
                  ),
                  const SizedBox(height: 26),
                  Card(
                    elevation: 2,
                    shadowColor: const Color(0xff273465).withValues(alpha: .08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            register
                                ? 'Tạo tài khoản mới'
                                : 'Chào mừng trở lại',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 20),
                          if (register) ...[
                            TextField(
                              controller: name,
                              textCapitalization: TextCapitalization.words,
                              decoration: _authDecoration(
                                'Họ và tên',
                                Icons.badge_outlined,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _authDecoration(
                                'Email',
                                Icons.alternate_email,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(
                                  value: 'Personal',
                                  label: Text('Cá nhân'),
                                  icon: Icon(Icons.person_outline),
                                ),
                                ButtonSegment(
                                  value: 'Group',
                                  label: Text('Tạo nhóm'),
                                  icon: Icon(Icons.groups_outlined),
                                ),
                              ],
                              selected: {accountType},
                              onSelectionChanged: (v) =>
                                  setState(() => accountType = v.first),
                            ),
                            if (accountType == 'Group') ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: groupName,
                                decoration: _authDecoration(
                                  'Tên nhóm',
                                  Icons.group_work_outlined,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Bạn sẽ là trưởng nhóm và có thể giao việc cho thành viên tham gia bằng mã nhóm.',
                                  style: TextStyle(color: Colors.blueGrey),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                          TextField(
                            controller: user,
                            decoration: _authDecoration(
                              register
                                  ? 'Tên đăng nhập'
                                  : 'Tên đăng nhập hoặc email',
                              Icons.person_outline,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: pass,
                            obscureText: obscurePassword,
                            decoration:
                                _authDecoration(
                                  'Mật khẩu',
                                  Icons.lock_outline,
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () => obscurePassword = !obscurePassword,
                                    ),
                                    icon: Icon(
                                      obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 52,
                            child: FilledButton(
                              onPressed: busy ? null : submit,
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      register ? 'Tạo tài khoản' : 'Đăng nhập',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          if (!register) ...[
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: busy ? null : forgotPassword,
                                icon: const Icon(Icons.lock_reset),
                                label: const Text('Quên mật khẩu?'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: busy ? null : signInWithGoogle,
                              icon: const Icon(Icons.g_mobiledata, size: 28),
                              label: const Text('Tiếp tục với Google'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                          Center(
                            child: TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      register = !register;
                                      error = null;
                                    }),
                              child: Text(
                                register
                                    ? 'Đã có tài khoản? Đăng nhập'
                                    : 'Chưa có tài khoản? Đăng ký',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!register)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Demo: phat.nguyen / TaskFlow@2026',
                        style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  InputDecoration _authDecoration(String label, IconData icon) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: const Color(0xfff8f9fd),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xffe7eaf3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xff5669e8), width: 1.5),
        ),
      );
}

class TaskPageData {
  const TaskPageData(this.items, this.total, this.page, this.pageSize);
  final List<TaskItem> items;
  final int total;
  final int page;
  final int pageSize;
}

class TaskItem {
  TaskItem(
    this.id,
    this.title,
    this.done,
    this.due, {
    this.description = '',
    this.dueAt,
    this.reminderIntervalMinutes,
    this.reminderUntil,
    this.assignedToUserId,
    this.workspaceId,
    this.locked = false,
    this.categoryId,
    this.createdAt,
    this.priority = 1,
    this.status = 0,
  });
  final int id;
  final String title;
  final bool done;
  final String due;
  final String description;
  final DateTime? dueAt;
  final int? reminderIntervalMinutes;
  final DateTime? reminderUntil;
  final String? assignedToUserId;
  final int? workspaceId;
  final bool locked;
  final int? categoryId;
  final DateTime? createdAt;
  final int priority;
  final int status;
}

class TaskStore {
  static Database? _db;
  static final List<TaskItem> _webTasks = [
    TaskItem(1, '[Nguyễn Đức Phát] Chốt yêu cầu và sơ đồ use case', false, 'Đồ án', description: 'Đồ án', priority: 1, status: 0),
    TaskItem(2, '[Nguyễn Đức Phát] Thiết kế cơ sở dữ liệu SQL Server', false, 'Đồ án', description: 'Đồ án', priority: 3, status: 0),
    TaskItem(3, '[Nguyễn Đức Phát] Soạn nội dung báo cáo giữa kỳ', false, 'Học tập', description: 'Học tập', priority: 1, status: 0),
    TaskItem(4, '[Bùi Đức Anh] Xây dựng API quản lý công việc', false, 'Backend', description: 'Backend', priority: 2, status: 0),
    TaskItem(5, '[Bùi Đức Anh] Tạo API danh mục công việc', false, 'Backend', description: 'Backend', priority: 1, status: 0),
    TaskItem(6, '[Bùi Đức Anh] Kiểm tra giao diện trên điện thoại', false, 'Cá nhân', description: 'Cá nhân', priority: 0, status: 0),
  ];
  static Future<Database> get db async {
    if (kIsWeb) throw UnsupportedError('SQLite is not supported on web.');
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'taskflow.db'),
      version: 4,
      onCreate: (d, _) async {
      await d.execute(
        'CREATE TABLE tasks(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,description TEXT NOT NULL DEFAULT \'\',dueAt TEXT,priority INTEGER NOT NULL DEFAULT 1,status INTEGER NOT NULL DEFAULT 0,category TEXT NOT NULL DEFAULT \'Cá nhân\',updatedAt TEXT NOT NULL,workspaceId INTEGER,assignedToUserId TEXT,reminderIntervalMinutes INTEGER,reminderUntil TEXT,categoryId INTEGER)',
      );
      await d.execute(
        'CREATE TABLE sync_queue(id INTEGER PRIMARY KEY AUTOINCREMENT,entity TEXT NOT NULL,entityId INTEGER NOT NULL,operation TEXT NOT NULL,payload TEXT NOT NULL,createdAt TEXT NOT NULL)',
      );
      final now = DateTime.now();
      final samples = [
        ('[Nguyễn Đức Phát] Chốt yêu cầu và sơ đồ use case', 'Đồ án', 1, 0, 1),
        (
          '[Nguyễn Đức Phát] Thiết kế cơ sở dữ liệu SQL Server',
          'Đồ án',
          2,
          0,
          3,
        ),
        ('[Nguyễn Đức Phát] Soạn nội dung báo cáo giữa kỳ', 'Học tập', 5, 0, 1),
        ('[Bùi Đức Anh] Xây dựng API quản lý công việc', 'Backend', 3, 0, 2),
        ('[Bùi Đức Anh] Tạo API danh mục công việc', 'Backend', 4, 0, 1),
        (
          '[Bùi Đức Anh] Kiểm tra giao diện trên điện thoại',
          'Cá nhân',
          6,
          0,
          0,
        ),
      ];
      for (final sample in samples) {
        await d.insert('tasks', {
          'title': sample.$1,
          'category': sample.$2,
          'dueAt': now.add(Duration(days: sample.$3)).toIso8601String(),
          'status': sample.$4,
          'priority': sample.$5,
          'updatedAt': now.toIso8601String(),
        });
      }
    },
    onUpgrade: (d, oldVersion, _) async {
      if (oldVersion < 2) {
        await d.execute('ALTER TABLE tasks ADD COLUMN workspaceId INTEGER');
        await d.execute('ALTER TABLE tasks ADD COLUMN assignedToUserId TEXT');
        await d.execute(
          'ALTER TABLE tasks ADD COLUMN reminderIntervalMinutes INTEGER',
        );
        await d.execute('ALTER TABLE tasks ADD COLUMN reminderUntil TEXT');
      }
      if (oldVersion < 3)
        await d.execute('ALTER TABLE tasks ADD COLUMN categoryId INTEGER');
      if (oldVersion < 4)
        await d.execute('UPDATE tasks SET status=2 WHERE status=1');
    },
  );
  }
  static Future<List<TaskItem>> all() async {
    if (kIsWeb) return List.from(_webTasks);
    final rows = await (await db).query(
      'tasks',
      orderBy: 'status ASC,dueAt ASC',
    );
    return rows
        .map(
          (r) => TaskItem(
            r['id'] as int,
            r['title'] as String,
            (r['status'] as int) == 2,
            (r['dueAt'] as String?) ?? 'Chưa đặt hạn',
            description: r['description'] as String? ?? '',
            dueAt: DateTime.tryParse(r['dueAt'] as String? ?? ''),
            reminderIntervalMinutes: r['reminderIntervalMinutes'] as int?,
            reminderUntil: DateTime.tryParse(
              r['reminderUntil'] as String? ?? '',
            ),
            assignedToUserId: r['assignedToUserId'] as String?,
            workspaceId: r['workspaceId'] as int?,
            categoryId: r['categoryId'] as int?,
            createdAt: DateTime.tryParse(r['updatedAt'] as String? ?? ''),
            priority: r['priority'] as int? ?? 1,
            status: r['status'] as int? ?? 0,
          ),
        )
        .toList();
  }

  static Future<int> add(
    String title, {
    String description = '',
    DateTime? dueAt,
    int? categoryId,
    int priority = 1,
    int status = 0,
    int? workspaceId,
    String? assignedToUserId,
    int? reminderIntervalMinutes,
    DateTime? reminderUntil,
    bool queue = true,
  }) async {
    if (kIsWeb) {
      final id = _webTasks.length + 1;
      _webTasks.add(TaskItem(
        id,
        title,
        status == 2,
        dueAt?.toIso8601String() ?? 'Chưa đặt hạn',
        description: description,
        dueAt: dueAt,
        priority: priority,
        status: status,
        workspaceId: workspaceId,
        assignedToUserId: assignedToUserId,
        categoryId: categoryId,
      ));
      return id;
    }
    final d = await db;
    final now = DateTime.now().toIso8601String();
    final id = await d.insert('tasks', {
      'title': title,
      'description': description,
      'categoryId': categoryId,
      'priority': priority,
      'status': status,
      'dueAt': dueAt?.toIso8601String(),
      'workspaceId': workspaceId,
      'assignedToUserId': assignedToUserId,
      'reminderIntervalMinutes': reminderIntervalMinutes,
      'reminderUntil': reminderUntil?.toIso8601String(),
      'updatedAt': now,
    });
    if (queue)
      await d.insert('sync_queue', {
        'entity': 'task',
        'entityId': id,
        'operation': 'upsert',
        'payload': jsonEncode({
          'title': title,
          'description': description,
          'categoryId': categoryId,
          'priority': priority,
          'status': status,
          'workspaceId': workspaceId,
          'assignedToUserId': assignedToUserId,
          'dueAt': dueAt?.toUtc().toIso8601String(),
          'reminderIntervalMinutes': reminderIntervalMinutes,
          'reminderUntil': reminderUntil?.toUtc().toIso8601String(),
        }),
        'createdAt': now,
      });
    return id;
  }

  static Future<void> cache(List<TaskItem> items) async {
    if (kIsWeb) {
      _webTasks.clear();
      _webTasks.addAll(items);
      return;
    }
    final d = await db;
    await d.transaction((txn) async {
      for (final task in items) {
        await txn.insert('tasks', {
          'id': task.id,
          'title': task.title,
          'description': task.description,
          'categoryId': task.categoryId,
          'dueAt': task.dueAt?.toIso8601String(),
          'status': task.done ? 2 : task.status,
          'priority': task.priority,
          'workspaceId': task.workspaceId,
          'assignedToUserId': task.assignedToUserId,
          'reminderIntervalMinutes': task.reminderIntervalMinutes,
          'reminderUntil': task.reminderUntil?.toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  static Future<void> update(
    TaskItem task, {
    required String title,
    required String description,
    required int? categoryId,
    required DateTime? dueAt,
    required int priority,
    required int? reminderIntervalMinutes,
    required DateTime? reminderUntil,
    required int status,
  }) async {
    if (kIsWeb) {
      final idx = _webTasks.indexWhere((t) => t.id == task.id);
      if (idx != -1) {
        _webTasks[idx] = TaskItem(
          task.id,
          title,
          status == 2,
          dueAt?.toIso8601String() ?? 'Chưa đặt hạn',
          description: description,
          dueAt: dueAt,
          priority: priority,
          status: status,
          workspaceId: task.workspaceId,
          assignedToUserId: task.assignedToUserId,
          categoryId: categoryId,
        );
      }
      return;
    }
    final d = await db;
    final now = DateTime.now().toIso8601String();
    final payload = {
      'title': title,
      'description': description,
      'categoryId': categoryId,
      'dueAt': dueAt?.toUtc().toIso8601String(),
      'priority': priority,
      'status': status,
      'workspaceId': task.workspaceId,
      'assignedToUserId': task.assignedToUserId,
      'reminderIntervalMinutes': reminderIntervalMinutes,
      'reminderUntil': reminderUntil?.toUtc().toIso8601String(),
    };
    await d.update(
      'tasks',
      {
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'dueAt': dueAt?.toIso8601String(),
        'priority': priority,
        'status': status,
        'reminderIntervalMinutes': reminderIntervalMinutes,
        'reminderUntil': reminderUntil?.toIso8601String(),
        'updatedAt': now,
      },
      where: 'id=?',
      whereArgs: [task.id],
    );
    await d.insert('sync_queue', {
      'entity': 'task',
      'entityId': task.id,
      'operation': 'update',
      'payload': jsonEncode(payload),
      'createdAt': now,
    });
  }

  static Future<void> toggle(TaskItem t) async {
    if (kIsWeb) {
      final idx = _webTasks.indexWhere((x) => x.id == t.id);
      if (idx != -1) {
        final old = _webTasks[idx];
        _webTasks[idx] = TaskItem(
          old.id,
          old.title,
          !old.done,
          old.due,
          description: old.description,
          dueAt: old.dueAt,
          priority: old.priority,
          status: old.done ? 0 : 2,
        );
      }
      return;
    }
    final d = await db;
    await d.update(
      'tasks',
      {'status': t.done ? 0 : 2, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id=?',
      whereArgs: [t.id],
    );
  }
}

class TaskHome extends StatefulWidget {
  const TaskHome({super.key, required this.onLogout});
  final VoidCallback onLogout;
  @override
  State<TaskHome> createState() => _TaskHomeState();
}

class _TaskHomeState extends State<TaskHome> {
  final taskSearch = TextEditingController();
  List<TaskItem> tasks = [];
  List<Map<String, dynamic>> categories = [];
  int? selectedCategoryId;
  int taskPage = 1;
  int taskTotal = 0;
  final int taskPageSize = 20;
  bool loadingMoreTasks = false;
  int planItemCount = 0;
  bool loading = true;
  bool? isAdmin;
  String? userId;
  Map<String, dynamic>? group;
  List<Map<String, dynamic>> groups = [];
  List<Map<String, dynamic>> noticeHistory = [];
  int homeTab = 0;
  int? selectedWorkspaceId;
  bool personalOnly = false;
  bool todayOnly = false;
  String groupSearch = '';
  Timer? noticeTimer;
  bool pollingNotices = false;
  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted)
        setState(() {
          isAdmin = p.getBool('isAdmin') ?? false;
          userId = p.getString('userId');
        });
    });
    _load();
    noticeTimer = Timer.periodic(
      const Duration(seconds: 25),
      (_) => _pollNotices(),
    );
  }

  Future<void> _load() async {
    List<TaskItem> data;
    try {
      await Api.syncPending();
      final prefs = await SharedPreferences.getInstance();
      userId = prefs.getString('userId');
      categories = await Api.getCategories();
      groups = await Api.getGroupHistory();
      group = selectedWorkspaceId == null
          ? null
          : await Api.getGroup(selectedWorkspaceId!) ??
                groups
                    .where((g) => g['groupId'] == selectedWorkspaceId)
                    .firstOrNull;
      final today = DateTime.now();
      final pageData = await Api.getTaskPage(
        q: taskSearch.text.trim(),
        workspaceId: selectedWorkspaceId,
        personalOnly: personalOnly,
        categoryId: selectedCategoryId,
        from: todayOnly ? DateTime(today.year, today.month, today.day) : null,
        to: todayOnly ? DateTime(today.year, today.month, today.day) : null,
        page: 1,
        pageSize: taskPageSize,
      );
      data = pageData.items;
      taskTotal = pageData.total;
      taskPage = 1;
      await TaskStore.cache(data);
      noticeHistory = await Api.getNoticeHistory();
      await _pollNotices();
      for (final task in data) {
        if (task.done) {
          await ReminderNotifications.cancel(task.id);
        } else if (task.assignedToUserId != null &&
            task.assignedToUserId != userId) {
          await ReminderNotifications.cancel(task.id);
        } else if (task.reminderIntervalMinutes != null &&
            task.reminderUntil != null) {
          await ReminderNotifications.schedule(
            taskId: task.id,
            title: task.title,
            firstAt: DateTime.now().add(
              Duration(minutes: task.reminderIntervalMinutes!),
            ),
            until: task.reminderUntil!,
            everyMinutes: task.reminderIntervalMinutes!,
          );
        }
      }
    } catch (_) {
      data = await TaskStore.all();
      taskTotal = data.length;
      taskPage = 1;
    }
    if (mounted) setState(() => {tasks = data, loading = false});
  }

  Future<void> _loadMoreTasks() async {
    if (loadingMoreTasks || tasks.length >= taskTotal) return;
    setState(() => loadingMoreTasks = true);
    try {
      final today = DateTime.now();
      final pageData = await Api.getTaskPage(
        q: taskSearch.text.trim(),
        workspaceId: selectedWorkspaceId,
        personalOnly: personalOnly,
        categoryId: selectedCategoryId,
        from: todayOnly ? DateTime(today.year, today.month, today.day) : null,
        to: todayOnly ? DateTime(today.year, today.month, today.day) : null,
        page: taskPage + 1,
        pageSize: taskPageSize,
      );
      setState(() {
        tasks.addAll(pageData.items);
        taskPage = pageData.page;
        taskTotal = pageData.total;
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => loadingMoreTasks = false);
    }
  }

  @override
  void dispose() {
    noticeTimer?.cancel();
    taskSearch.dispose();
    super.dispose();
  }

  Future<void> _pollNotices() async {
    if (pollingNotices) return;
    pollingNotices = true;
    try {
      final notices = await Api.getNotices();
      for (final notice in notices) {
        final id = notice['id'] as int;
        await ReminderNotifications.showNotice(
          id,
          'TaskFlow • Yêu cầu làm lại',
          notice['message'] as String? ??
              'Trưởng nhóm yêu cầu cập nhật công việc.',
        );
        await Api.markNoticeRead(id);
      }
      noticeHistory = await Api.getNoticeHistory();
      if (mounted && homeTab == 1) setState(() {});
    } catch (_) {
      // The API may be temporarily unavailable; unread notices remain on the server.
    } finally {
      pollingNotices = false;
    }
  }

  Future<void> _add() async {
    if (group != null && group!['isCurrent'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đây là nhóm cũ. Chọn nhóm đang tham gia hoặc Cá nhân để tạo việc mới.',
          ),
        ),
      );
      return;
    }
    final draft = await Navigator.push<TaskDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditorPage(
          group: personalOnly ? null : group,
          userId: userId,
          categories: categories,
        ),
      ),
    );
    if (draft == null) return;
    var notificationId = -1;
    var synced = false;
    try {
      notificationId = await Api.createTask(
        title: draft.title,
        description: draft.description,
        categoryId: draft.categoryId,
        priority: draft.priority,
        status: draft.status,
        dueAt: draft.dueAt,
        workspaceId: draft.workspaceId,
        assignedToUserId: draft.assignedToUserId,
        reminderIntervalMinutes: draft.reminderIntervalMinutes,
        reminderUntil: draft.reminderUntil,
      );
      synced = true;
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e Đã lưu cục bộ.')));
    }
    final localId = await TaskStore.add(
      draft.title,
      description: draft.description,
      categoryId: draft.categoryId,
      priority: draft.priority,
      status: draft.status,
      dueAt: draft.dueAt,
      workspaceId: draft.workspaceId,
      assignedToUserId: draft.assignedToUserId,
      reminderIntervalMinutes: draft.reminderIntervalMinutes,
      reminderUntil: draft.reminderUntil,
      queue: !synced,
    );
    notificationId = synced ? notificationId : localId;
    if ((draft.assignedToUserId == null || draft.assignedToUserId == userId) &&
        draft.reminderIntervalMinutes != null &&
        draft.reminderUntil != null) {
      await ReminderNotifications.schedule(
        taskId: notificationId,
        title: draft.title,
        firstAt: DateTime.now().add(
          Duration(minutes: draft.reminderIntervalMinutes!),
        ),
        until: draft.reminderUntil!,
        everyMinutes: draft.reminderIntervalMinutes!,
      );
    }
    await _load();
  }

  Future<void> _editTask(TaskItem task) async {
    Map<String, dynamic>? taskGroup;
    if (task.workspaceId != null) {
      taskGroup = task.workspaceId == selectedWorkspaceId
          ? group
          : await Api.getGroup(task.workspaceId!);
      if (taskGroup?['isCurrent'] != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chỉ sửa được công việc của nhóm đang tham gia.'),
          ),
        );
        return;
      }
      final role = taskGroup?['role'];
      if (task.assignedToUserId != userId && role != 'Leader') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chỉ người được giao hoặc trưởng nhóm mới sửa được việc này.',
            ),
          ),
        );
        return;
      }
    }
    final draft = await Navigator.push<TaskDraft>(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditorPage(
          group: taskGroup,
          userId: userId,
          categories: categories,
          initial: task,
        ),
      ),
    );
    if (draft == null) return;
    try {
      await Api.updateTask(
        id: task.id,
        title: draft.title,
        description: draft.description,
        categoryId: draft.categoryId,
        dueAt: draft.dueAt,
        priority: draft.priority,
        status: draft.status,
        workspaceId: task.workspaceId,
        assignedToUserId: task.assignedToUserId,
        reminderIntervalMinutes: draft.reminderIntervalMinutes,
        reminderUntil: draft.reminderUntil,
      );
    } catch (e) {
      await TaskStore.update(
        task,
        title: draft.title,
        description: draft.description,
        categoryId: draft.categoryId,
        dueAt: draft.dueAt,
        priority: draft.priority,
        status: draft.status,
        reminderIntervalMinutes: draft.reminderIntervalMinutes,
        reminderUntil: draft.reminderUntil,
      );
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e Đã lưu thay đổi cục bộ.')));
    }
    await _load();
  }

  Future<void> _showTaskDetails(TaskItem task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                task.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                task.description.isEmpty ? 'Chưa có mô tả.' : task.description,
              ),
              const SizedBox(height: 8),
              Text('Danh mục: ${_categoryName(task.categoryId)}'),
              Text(
                'Hạn: ${task.dueAt == null ? 'Chưa đặt' : MaterialLocalizations.of(context).formatMediumDate(task.dueAt!)}',
              ),
              Text(
                'Ưu tiên: ${['Thấp', 'Bình thường', 'Cao', 'Khẩn cấp'][task.priority.clamp(0, 3)]}',
              ),
              const SizedBox(height: 12),
              if (_canEditTask(task))
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _editTask(task);
                  },
                  icon: const Icon(Icons.edit),
                  label: const Text('Sửa công việc'),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _showTaskAttachments(task);
                },
                icon: const Icon(Icons.attach_file),
                label: const Text('Ảnh và tệp đính kèm'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _joinGroup() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tham gia nhóm'),
        content: TextField(
          controller: c,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Mã nhóm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Tham gia'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    try {
      final joined = await Api.joinGroup(code);
      selectedWorkspaceId = joined['id'] as int;
      personalOnly = false;
      todayOnly = true;
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _leaveGroup({int? workspaceId}) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rời nhóm?'),
        content: const Text(
          'Nhiệm vụ và kết quả cũ vẫn được lưu trong lịch sử cá nhân và nhóm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ở lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );
    if (leave != true) return;
    try {
      final groupId =
          workspaceId ?? group?['id'] as int? ?? group?['groupId'] as int?;
      if (groupId == null) return;
      await Api.leaveGroup(groupId);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showTaskHistory() async {
    try {
      final history = await Api.getGroupHistory();
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(builder: (_) => TaskHistoryPage(groups: history)),
      );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _confirmTaskCompletion(TaskItem task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận hoàn thành'),
        content: Text(
          'Bạn đã hoàn thành "${task.title}"? Sau khi xác nhận, công việc sẽ được khóa để tránh thay đổi nhầm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Chưa xong'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ReminderNotifications.cancel(task.id);
    try {
      await Api.setTaskDone(task);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không lưu được trạng thái hoàn thành: $e')),
        );
    }
  }

  Future<void> _requestTaskRedo(TaskItem task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yêu cầu làm lại?'),
        content: Text(
          'Đánh dấu "${task.title}" là chưa hoàn thành và gửi thông báo cho thành viên?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Gửi yêu cầu'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Api.requestRework(task.id);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Đã chuyển việc về chưa hoàn thành và gửi thông báo.',
            ),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  bool _canDeleteTask(TaskItem task) {
    if (task.workspaceId == null) return true;
    final membership = groups
        .where((g) => g['groupId'] == task.workspaceId)
        .firstOrNull;
    return membership?['isCurrent'] == true && membership?['role'] == 'Leader';
  }

  bool _canEditAttachments(TaskItem task) {
    if (task.workspaceId == null) return true;
    final membership = groups
        .where((g) => g['groupId'] == task.workspaceId)
        .firstOrNull;
    return membership?['isCurrent'] == true &&
        (task.assignedToUserId == userId || membership?['role'] == 'Leader');
  }

  bool _canEditTask(TaskItem task) {
    if (task.locked) return false;
    if (task.workspaceId == null) return true;
    final membership = groups
        .where((g) => g['groupId'] == task.workspaceId)
        .firstOrNull;
    return membership?['isCurrent'] == true &&
        (task.assignedToUserId == userId || membership?['role'] == 'Leader');
  }

  String _categoryName(int? id) =>
      categories
          .where((item) => item['id'] == id)
          .map((item) => item['name'] as String)
          .firstOrNull ??
      'Chưa phân loại';

  Future<void> _deleteTask(TaskItem task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa nhiệm vụ?'),
        content: Text(
          'Bạn có chắc muốn xóa "${task.title}" cùng các tệp đính kèm không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteTask(task.id);
      await ReminderNotifications.cancel(task.id);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã xóa nhiệm vụ.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openAttachment(
    TaskItem task,
    Map<String, dynamic> attachment,
  ) async {
    try {
      final bytes = await Api.downloadTaskAttachment(
        task.id,
        attachment['id'] as int,
      );
      final contentType = attachment['contentType'] as String? ?? '';
      if (contentType.startsWith('image/')) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => Dialog(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: InteractiveViewer(child: Image.memory(bytes)),
            ),
          ),
        );
      } else {
        final saved = await FilePicker.saveFile(
          fileName: attachment['fileName'] as String? ?? 'task-file',
          bytes: bytes,
          mimeType: contentType,
        );
        if (mounted && saved != null)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Đã lưu tệp: ${saved.path}')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _showTaskAttachments(TaskItem task) async {
    List<Map<String, dynamic>> attachments;
    try {
      attachments = await Api.getTaskAttachments(task.id);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tệp đính kèm (${attachments.length})',
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                    ),
                    if (_canEditAttachments(task))
                      IconButton.filledTonal(
                        tooltip: 'Tải ảnh hoặc tệp lên',
                        onPressed: () async {
                          final files = await FilePicker.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: [
                              'png',
                              'jpg',
                              'jpeg',
                              'gif',
                              'webp',
                              'pdf',
                              'doc',
                              'docx',
                              'xls',
                              'xlsx',
                              'ppt',
                              'pptx',
                              'txt',
                              'csv',
                              'zip',
                            ],
                          );
                          if (files.isEmpty) return;
                          try {
                            for (final file in files) {
                              await Api.uploadTaskAttachment(task.id, file);
                            }
                            attachments = await Api.getTaskAttachments(task.id);
                            setSheetState(() {});
                          } catch (e) {
                            if (mounted)
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$e')));
                          }
                        },
                        icon: const Icon(Icons.upload_file),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: attachments.isEmpty
                    ? const Center(
                        child: Text('Chưa có ảnh hoặc tệp đính kèm.'),
                      )
                    : ListView.builder(
                        itemCount: attachments.length,
                        itemBuilder: (ctx, index) {
                          final item = attachments[index];
                          final isImage = (item['contentType'] as String? ?? '')
                              .startsWith('image/');
                          return ListTile(
                            leading: Icon(
                              isImage
                                  ? Icons.image_outlined
                                  : Icons.insert_drive_file_outlined,
                            ),
                            title: Text(item['fileName'] as String? ?? 'Tệp'),
                            subtitle: Text(
                              '${((item['size'] as num? ?? 0) / 1024).toStringAsFixed(1)} KB',
                            ),
                            onTap: () => _openAttachment(task, item),
                            trailing: _canEditAttachments(task)
                                ? IconButton(
                                    tooltip: 'Xóa tệp',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      try {
                                        await Api.deleteTaskAttachment(
                                          task.id,
                                          item['id'] as int,
                                        );
                                        attachments.removeAt(index);
                                        setSheetState(() {});
                                      } catch (e) {
                                        if (mounted)
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                      }
                                    },
                                  )
                                : null,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<TaskItem> get _visibleTasks {
    final query = taskSearch.text.trim().toLowerCase();
    return tasks
        .where(
          (task) =>
              (selectedCategoryId == null ||
                  task.categoryId == selectedCategoryId) &&
              (query.isEmpty ||
                  task.title.toLowerCase().contains(query) ||
                  task.description.toLowerCase().contains(query)),
        )
        .toList();
  }

  Future<void> _createMyGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo nhóm mới'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Tên nhóm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(ctx, value);
            },
            child: const Text('Tạo nhóm'),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      final created = await Api.createGroup(name);
      selectedWorkspaceId = created['id'] as int;
      personalOnly = false;
      todayOnly = true;
      await _load();
      if (!mounted) return;
      final code = created['joinCode'] as String;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Đã tạo nhóm'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gửi mã này cho thành viên để họ tham gia nhóm ${created['name']}: ',
              ),
              const SizedBox(height: 12),
              SelectableText(
                code,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã sao chép mã nhóm.')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Sao chép mã'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _showGroupOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Tạo nhóm mới'),
              subtitle: const Text('Bạn sẽ là trưởng nhóm và nhận mã mời.'),
              onTap: () => Navigator.pop(ctx, 'create'),
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Tham gia nhóm bằng mã'),
              subtitle: const Text('Nhập mã do trưởng nhóm gửi cho bạn.'),
              onTap: () => Navigator.pop(ctx, 'join'),
            ),
          ],
        ),
      ),
    );
    if (action == 'create') await _createMyGroup();
    if (action == 'join') await _joinGroup();
  }

  String _memberName(String id) {
    final members =
        (group?['members'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return members
            .where((m) => m['id'] == id)
            .map((m) => m['displayName'] as String)
            .firstOrNull ??
        id;
  }

  Future<void> _selectGroup(
    Map<String, dynamic> item, {
    bool today = true,
  }) async {
    selectedWorkspaceId = (item['groupId'] ?? item['id']) as int;
    personalOnly = false;
    todayOnly = today;
    homeTab = 0;
    await _load();
  }

  Future<void> _selectAll() async {
    selectedWorkspaceId = null;
    personalOnly = false;
    todayOnly = false;
    homeTab = 0;
    await _load();
  }

  Future<void> _selectPersonal() async {
    selectedWorkspaceId = null;
    personalOnly = true;
    todayOnly = false;
    homeTab = 0;
    await _load();
  }

  Widget _taskCards() => _visibleTasks.isEmpty
      ? const Center(child: Text('Không có nhiệm vụ trong phạm vi đã chọn.'))
      : ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
          itemCount: _visibleTasks.length + (tasks.length < taskTotal ? 1 : 0),
          itemBuilder: (ctx, i) {
            if (i >= _visibleTasks.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: loadingMoreTasks ? null : _loadMoreTasks,
                    icon: loadingMoreTasks
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more),
                    label: Text(
                      loadingMoreTasks ? 'Đang tải…' : 'Tải thêm công việc',
                    ),
                  ),
                ),
              );
            }
            final task = _visibleTasks[i];
            return Card(
              child: CheckboxListTile(
                value: task.done,
                onChanged: task.done
                    ? null
                    : (_) => _confirmTaskCompletion(task),
                title: InkWell(
                  onTap: () => _showTaskDetails(task),
                  child: Text(
                    task.title,
                    style: TextStyle(
                      decoration: task.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                subtitle: Text(
                  [
                    task.due,
                    _categoryName(task.categoryId),
                    if (task.reminderIntervalMinutes != null)
                      'Nhắc mỗi ${task.reminderIntervalMinutes} phút',
                    if (task.assignedToUserId != null)
                      'Người phụ trách: ${_memberName(task.assignedToUserId!)}',
                  ].where((s) => s.isNotEmpty).join(' • '),
                ),
                secondary: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_canEditTask(task))
                      IconButton(
                        tooltip: 'Sửa công việc',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editTask(task),
                      ),
                    IconButton(
                      tooltip: 'Ảnh và tệp đính kèm',
                      icon: const Icon(Icons.attach_file),
                      onPressed: () => _showTaskAttachments(task),
                    ),
                    if (_canDeleteTask(task))
                      IconButton(
                        tooltip: 'Xóa nhiệm vụ',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deleteTask(task),
                      ),
                    if (task.done &&
                        task.workspaceId != null &&
                        _canDeleteTask(task) &&
                        task.assignedToUserId != userId)
                      IconButton(
                        tooltip: 'Yêu cầu làm lại',
                        icon: const Icon(Icons.restart_alt_rounded),
                        onPressed: () => _requestTaskRedo(task),
                      )
                    else if (task.locked)
                      const Icon(Icons.lock),
                  ],
                ),
              ),
            );
          },
        );

  Widget _overviewBody() {
    final visibleTasks = _visibleTasks;
    final pending = visibleTasks.where((t) => !t.done).length;
    final done = visibleTasks.length - pending;
    final selectedLabel = personalOnly
        ? 'Cá nhân'
        : group == null
        ? 'Tất cả nhiệm vụ'
        : group!['name'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const CircleAvatar(radius: 25, child: Icon(Icons.task_alt)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedLabel,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text('$pending việc cần làm • $done đã hoàn thành'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: taskSearch,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Tìm nhiệm vụ, mô tả...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Xóa tìm kiếm',
                onPressed: () {
                  taskSearch.clear();
                  setState(() {});
                  _load();
                },
                icon: const Icon(Icons.close),
              ),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Tất cả'),
                  selected: selectedWorkspaceId == null && !personalOnly,
                  onSelected: (_) => _selectAll(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Cá nhân'),
                  selected: personalOnly,
                  onSelected: (_) => _selectPersonal(),
                ),
              ),
              for (final item in groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${item['groupName']}${item['isCurrent'] == true ? '' : ' • cũ'}',
                    ),
                    selected: selectedWorkspaceId == item['groupId'],
                    onSelected: (_) => _selectGroup(item),
                  ),
                ),
              for (final item in categories)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(item['name'] as String),
                    selected: selectedCategoryId == item['id'],
                    onSelected: (_) {
                      selectedCategoryId = selectedCategoryId == item['id']
                          ? null
                          : item['id'] as int;
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            todayOnly ? 'Nhiệm vụ hôm nay' : 'Nhiệm vụ',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '${visibleTasks.length} nhiệm vụ • $pending cần hoàn thành',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.blueGrey),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _taskCards()),
      ],
    );
  }

  Widget _groupsBody() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: TextField(
          onChanged: (value) =>
              setState(() => groupSearch = value.trim().toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Tìm nhóm...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _createMyGroup,
                icon: const Icon(Icons.add),
                label: const Text('Tạo nhóm'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _joinGroup,
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Nhập mã'),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child:
            groups
                .where(
                  (g) => (g['groupName'] as String? ?? '')
                      .toLowerCase()
                      .contains(groupSearch),
                )
                .isEmpty
            ? const Center(
                child: Text(
                  'Bạn chưa tham gia nhóm nào. Tạo nhóm hoặc nhập mã mời.',
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                itemCount: groups
                    .where(
                      (g) => (g['groupName'] as String? ?? '')
                          .toLowerCase()
                          .contains(groupSearch),
                    )
                    .length,
                itemBuilder: (context, index) {
                  final item = groups
                      .where(
                        (g) => (g['groupName'] as String? ?? '')
                            .toLowerCase()
                            .contains(groupSearch),
                      )
                      .toList()[index];
                  final active = item['isCurrent'] == true;
                  final leader = item['role'] == 'Leader';
                  final memberTasks = (item['tasks'] as List? ?? const [])
                      .cast<Map<String, dynamic>>();
                  final completed = memberTasks
                      .where((t) => t['status'] == 2)
                      .length;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          leader
                              ? Icons.admin_panel_settings_outlined
                              : Icons.groups_outlined,
                        ),
                      ),
                      title: Text(item['groupName'] as String? ?? 'Nhóm'),
                      subtitle: Text(
                        '${active ? (leader ? 'Trưởng nhóm' : 'Đang tham gia') : 'Đã rời nhóm'} • $completed/${memberTasks.length} việc cá nhân hoàn thành',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (active && leader && item['joinCode'] != null)
                            IconButton(
                              tooltip: 'Sao chép mã mời',
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(
                                    text: item['joinCode'] as String,
                                  ),
                                );
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Đã sao chép mã nhóm.'),
                                    ),
                                  );
                              },
                              icon: const Icon(Icons.copy),
                            ),
                          if (active && !leader)
                            IconButton(
                              tooltip: 'Rời nhóm',
                              onPressed: () => _leaveGroup(
                                workspaceId: item['groupId'] as int,
                              ),
                              icon: const Icon(Icons.logout),
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => _selectGroup(item),
                    ),
                  );
                },
              ),
      ),
    ],
  );

  Widget _notificationsBody() => noticeHistory.isEmpty
      ? const Center(child: Text('Chưa có thông báo.'))
      : ListView.builder(
          itemCount: noticeHistory.length,
          padding: const EdgeInsets.all(12),
          itemBuilder: (context, index) {
            final notice = noticeHistory[index];
            final unread = notice['readAt'] == null;
            return Card(
              child: ListTile(
                leading: Icon(
                  unread
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_none,
                ),
                title: Text(
                  notice['message'] as String? ?? 'Thông báo công việc',
                ),
                subtitle: Text('${notice['createdAt'] ?? ''}'),
                tileColor: unread
                    ? Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: .35)
                    : null,
              ),
            );
          },
        );

  @override
  Widget build(BuildContext context) {
    if (isAdmin == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (isAdmin!) return AdminDashboard(onLogout: widget.onLogout);
    final unread = noticeHistory.where((n) => n['readAt'] == null).length;
    final pendingTasks = _visibleTasks.where((task) => !task.done).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(['Tổng quan', 'Thông báo', 'Nhóm'][homeTab]),
        actions: [
          if (homeTab == 1)
            IconButton(
              tooltip: 'Làm mới thông báo',
              onPressed: _pollNotices,
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: 'Đổi mật khẩu',
            onPressed: () => openChangePasswordDialog(context),
            icon: const Icon(Icons.key),
          ),
          IconButton(
            tooltip: 'Tài khoản và liên kết Google',
            onPressed: () => openGoogleLinkSettings(context),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('jwt');
              await prefs.remove('isAdmin');
              await prefs.remove('userId');
              widget.onLogout();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: loading && groups.isEmpty && tasks.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : homeTab == 0
          ? _overviewBody()
          : homeTab == 1
          ? _notificationsBody()
          : homeTab == 2
          ? _groupsBody()
          : WorkPlansPage(
              tasks: tasks,
              onChanged: _load,
              onCountChanged: (value) {
                if (mounted) setState(() => planItemCount = value);
              },
            ),
      floatingActionButton: homeTab == 0
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Thêm việc'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: homeTab,
        onDestinationSelected: (index) async {
          setState(() => homeTab = index);
          if (index == 1) await _pollNotices();
        },
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingTasks > 0,
              label: Text('$pendingTasks'),
              child: const Icon(Icons.dashboard_outlined),
            ),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: const Icon(Icons.notifications),
            label: 'Thông báo',
          ),
          const NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Nhóm',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: planItemCount > 0,
              label: Text('$planItemCount'),
              child: const Icon(Icons.event_note_outlined),
            ),
            selectedIcon: const Icon(Icons.event_note),
            label: 'Kế hoạch',
          ),
        ],
      ),
    );
  }
}

class TaskHistoryPage extends StatelessWidget {
  const TaskHistoryPage({super.key, required this.groups});
  final List<Map<String, dynamic>> groups;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lịch sử nhiệm vụ')),
    body: groups.isEmpty
        ? const Center(child: Text('Chưa có lịch sử nhóm.'))
        : ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final tasks = (group['tasks'] as List? ?? const [])
                  .cast<Map<String, dynamic>>();
              final current = group['isCurrent'] == true;
              return Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: Icon(current ? Icons.groups : Icons.history),
                  title: Text(group['groupName'] as String? ?? 'Nhóm'),
                  subtitle: Text(
                    current
                        ? 'Đang tham gia • ${tasks.length} nhiệm vụ'
                        : 'Đã rời nhóm • ${tasks.length} nhiệm vụ',
                  ),
                  children: tasks.isEmpty
                      ? const [
                          ListTile(
                            title: Text(
                              'Chưa có nhiệm vụ được giao trong nhóm này.',
                            ),
                          ),
                        ]
                      : [
                          for (final task in tasks)
                            ListTile(
                              leading: Icon(
                                task['status'] == 2
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: task['status'] == 2
                                    ? Colors.green
                                    : null,
                              ),
                              title: Text(task['title'] as String? ?? ''),
                              subtitle: Text(
                                task['status'] == 2
                                    ? 'Đã hoàn thành'
                                    : 'Chưa hoàn thành',
                              ),
                              trailing: task['dueAt'] == null
                                  ? null
                                  : Text(
                                      (task['dueAt'] as String).substring(
                                        0,
                                        10,
                                      ),
                                    ),
                            ),
                        ],
                ),
              );
            },
          ),
  );
}

class TaskDraft {
  const TaskDraft({
    this.existingTaskId,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.dueAt,
    required this.priority,
    required this.status,
    required this.workspaceId,
    required this.assignedToUserId,
    required this.reminderIntervalMinutes,
    required this.reminderUntil,
  });
  final int? existingTaskId;
  final String title;
  final String description;
  final int? categoryId;
  final DateTime? dueAt;
  final int priority;
  final int status;
  final int? workspaceId;
  final String? assignedToUserId;
  final int? reminderIntervalMinutes;
  final DateTime? reminderUntil;
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.onLogout});
  final VoidCallback onLogout;
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int tab = 0;
  final userSearch = TextEditingController();
  final groupSearch = TextEditingController();
  final taskSearch = TextEditingController();
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> groups = [];
  List<TaskItem> tasks = [];
  DateTime? createdFrom;
  DateTime? createdTo;
  DateTime? taskFrom;
  DateTime? taskTo;
  int? taskStatusFilter;
  int taskListPage = 1;
  int taskListTotal = 0;
  bool loadingMoreAdminTasks = false;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await Future.wait([_loadUsers(), _loadGroups(), _loadTasks()]);
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _loadUsers() async {
    users = await Api.getMembers(
      q: userSearch.text.trim(),
      createdFrom: createdFrom,
      createdTo: createdTo,
    );
  }

  Future<void> _loadGroups() async {
    groups = await Api.getAdminGroups(q: groupSearch.text.trim());
  }

  Future<void> _loadTasks() async {
    final data = await Api.getTaskPage(
      q: taskSearch.text.trim(),
      status: taskStatusFilter,
      from: taskFrom,
      to: taskTo,
      page: 1,
      pageSize: 20,
      sort: 'newest',
    );
    tasks = data.items;
    taskListTotal = data.total;
    taskListPage = 1;
  }

  Future<void> _filterTaskDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 5),
      initialDateRange: taskFrom == null
          ? null
          : DateTimeRange(start: taskFrom!, end: taskTo ?? taskFrom!),
    );
    if (range == null) return;
    taskFrom = range.start;
    taskTo = range.end;
    await _loadTasks();
    if (mounted) setState(() {});
  }

  Future<void> _loadMoreAdminTasks() async {
    if (loadingMoreAdminTasks || tasks.length >= taskListTotal) return;
    setState(() => loadingMoreAdminTasks = true);
    try {
      final data = await Api.getTaskPage(
        q: taskSearch.text.trim(),
        status: taskStatusFilter,
        from: taskFrom,
        to: taskTo,
        page: taskListPage + 1,
        pageSize: 20,
        sort: 'newest',
      );
      setState(() {
        tasks.addAll(data.items);
        taskListPage = data.page;
        taskListTotal = data.total;
      });
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => loadingMoreAdminTasks = false);
    }
  }

  Future<void> _changeAdminTaskStatus(TaskItem task) async {
    const statuses = {
      0: 'Cần làm',
      1: 'Đang làm',
      2: 'Hoàn thành',
      3: 'Đã lưu trữ',
    };
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Trạng thái: ${task.title}'),
        children: [
          for (final entry in statuses.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, entry.key),
              child: Row(
                children: [
                  if (entry.key == task.status)
                    const Icon(Icons.check, size: 18),
                  const SizedBox(width: 8),
                  Text(entry.value),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null) return;
    try {
      await Api.setTaskStatus(task.id, selected);
      await _loadTasks();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _dateFilter() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 2),
      initialDateRange: createdFrom == null
          ? null
          : DateTimeRange(start: createdFrom!, end: createdTo ?? createdFrom!),
    );
    if (range != null) {
      createdFrom = range.start;
      createdTo = range.end;
      await _loadUsers();
      if (mounted) setState(() {});
    }
  }

  Future<void> _addMember(int groupId) async {
    final available = await Api.getMembers();
    final unassigned = available
        .where((m) => m['workspaceId'] == null)
        .toList();
    if (unassigned.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không còn tài khoản chưa được xếp nhóm.'),
          ),
        );
      return;
    }
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Thêm thành viên vào nhóm'),
        children: [
          for (final m in unassigned)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m['id'] as String),
              child: Text('${m['displayName']} • ${m['email']}'),
            ),
        ],
      ),
    );
    if (selected == null) return;
    try {
      await Api.addMemberToGroup(groupId, selected);
      await _refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _removeMember(int groupId, Map<String, dynamic> member) async {
    try {
      await Api.removeMemberFromGroup(groupId, member['id'] as String);
      await _refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _createGroup() async {
    final available = await Api.getMembers();
    final leaders = available.where((m) => m['workspaceId'] == null).toList();
    if (leaders.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cần tài khoản chưa tham gia nhóm để làm trưởng nhóm.',
            ),
          ),
        );
      return;
    }
    final name = TextEditingController();
    String? leaderId = leaders.first['id'] as String;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Tạo nhóm'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Tên nhóm'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: leaderId,
                decoration: const InputDecoration(labelText: 'Nhóm trưởng'),
                items: [
                  for (final u in leaders)
                    DropdownMenuItem(
                      value: u['id'] as String,
                      child: Text(u['displayName'] as String),
                    ),
                ],
                onChanged: (v) => setStateDialog(() => leaderId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, (name.text.trim(), leaderId!)),
              child: const Text('Tạo'),
            ),
          ],
        ),
      ),
    );
    if (result == null || result.$1.isEmpty) return;
    try {
      await Api.createAdminGroup(result.$1, result.$2);
      await _refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _createMember() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AdminCreateMemberPage(groups: groups)),
    );
    if (created == true) await _refresh();
  }

  Future<void> _openUser(Map<String, dynamic> user) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminAccountTasksPage(user: user)),
    );
  }

  String _dateLabel(DateTime? date) => date == null
      ? 'Chọn ngày'
      : MaterialLocalizations.of(context).formatMediumDate(date);
  @override
  Widget build(BuildContext context) {
    final titles = ['Tài khoản', 'Nhóm', 'Công việc'];
    return Scaffold(
      appBar: AppBar(
        title: Text('Quản trị • ${titles[tab]}'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: 'Đổi mật khẩu',
            onPressed: () => openChangePasswordDialog(context),
            icon: const Icon(Icons.key),
          ),
          IconButton(
            tooltip: 'Liên kết Google',
            onPressed: () => openGoogleLinkSettings(context),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => v == 'categories'
                    ? const CategoryAdminPage()
                    : const MemberAdminPage(),
              ),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'categories',
                child: Text('Quản lý danh mục'),
              ),
              PopupMenuItem(value: 'roles', child: Text('Quản lý vai trò')),
            ],
          ),
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: _createMember,
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Tạo tài khoản'),
            )
          : tab == 1
          ? FloatingActionButton.extended(
              onPressed: _createGroup,
              icon: const Icon(Icons.group_add),
              label: const Text('Tạo nhóm'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Tài khoản',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Nhóm',
          ),
          NavigationDestination(
            icon: Icon(Icons.task_outlined),
            selectedIcon: Icon(Icons.task),
            label: 'Công việc',
          ),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : IndexedStack(
              index: tab,
              children: [_usersTab(), _groupsTab(), _tasksTab()],
            ),
    );
  }

  Widget _usersTab() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          controller: userSearch,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) async {
            await _loadUsers();
            if (mounted) setState(() {});
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Tìm tên, username hoặc email',
            suffixIcon: IconButton(
              onPressed: () async {
                userSearch.clear();
                await _loadUsers();
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.clear),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _dateFilter,
                icon: const Icon(Icons.date_range),
                label: Text(
                  createdFrom == null
                      ? 'Lọc ngày tạo'
                      : '${_dateLabel(createdFrom)} – ${_dateLabel(createdTo)}',
                ),
              ),
            ),
            if (createdFrom != null)
              IconButton(
                onPressed: () async {
                  createdFrom = null;
                  createdTo = null;
                  await _loadUsers();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.filter_alt_off),
              ),
          ],
        ),
      ),
      Expanded(
        child: users.isEmpty
            ? const Center(child: Text('Không tìm thấy tài khoản.'))
            : ListView.builder(
                itemCount: users.length,
                itemBuilder: (ctx, i) {
                  final u = users[i];
                  final roles = (u['roles'] as List? ?? const []).join(', ');
                  final created = DateTime.tryParse(
                    u['createdAt'] as String? ?? '',
                  );
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (u['displayName'] as String).characters.first,
                        ),
                      ),
                      title: Text(u['displayName'] as String),
                      subtitle: Text(
                        '${u['userName']} • ${u['email']}\n$roles • Tạo ${_dateLabel(created)}',
                      ),
                      isThreeLine: true,
                      trailing: Icon(
                        u['isActive'] == true
                            ? Icons.chevron_right
                            : Icons.block,
                        color: u['isActive'] == true ? null : Colors.red,
                      ),
                      onTap: () => _openUser(u),
                    ),
                  );
                },
              ),
      ),
    ],
  );
  Widget _groupsTab() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: groupSearch,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) async {
            await _loadGroups();
            if (mounted) setState(() {});
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Tìm nhóm hoặc mã tham gia',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      Expanded(
        child: groups.isEmpty
            ? const Center(child: Text('Chưa có nhóm.'))
            : ListView.builder(
                itemCount: groups.length,
                itemBuilder: (ctx, i) {
                  final g = groups[i];
                  final members = (g['members'] as List)
                      .cast<Map<String, dynamic>>();
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: ExpansionTile(
                      leading: const Icon(Icons.groups),
                      title: Text(g['name'] as String),
                      subtitle: Text(
                        'Mã ${g['joinCode']} • Trưởng nhóm: ${g['leaderName']} • ${members.length} thành viên',
                      ),
                      trailing: IconButton(
                        tooltip: 'Thêm thành viên',
                        onPressed: () => _addMember(g['id'] as int),
                        icon: const Icon(Icons.person_add_alt_1),
                      ),
                      children: [
                        for (final m in members)
                          ListTile(
                            dense: true,
                            title: Text(m['displayName'] as String),
                            subtitle: Text('${m['userName']} • ${m['role']}'),
                            trailing: m['role'] == 'Leader'
                                ? const Icon(Icons.verified_user_outlined)
                                : IconButton(
                                    onPressed: () =>
                                        _removeMember(g['id'] as int, m),
                                    icon: const Icon(
                                      Icons.person_remove_outlined,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ],
  );
  Widget _tasksTab() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: TextField(
          controller: taskSearch,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) async {
            await _loadTasks();
            if (mounted) setState(() {});
          },
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Tìm trong toàn bộ công việc',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _filterTaskDates,
                icon: const Icon(Icons.date_range),
                label: Text(
                  taskFrom == null
                      ? 'Lọc theo hạn'
                      : '${_dateLabel(taskFrom)} – ${_dateLabel(taskTo)}',
                ),
              ),
            ),
            IconButton(
              tooltip: 'Xóa lọc hạn',
              onPressed: taskFrom == null
                  ? null
                  : () async {
                      taskFrom = null;
                      taskTo = null;
                      await _loadTasks();
                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.filter_alt_off),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DropdownButtonFormField<int?>(
          initialValue: taskStatusFilter,
          decoration: const InputDecoration(
            labelText: 'Lọc trạng thái',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem<int?>(
              value: null,
              child: Text('Tất cả trạng thái'),
            ),
            DropdownMenuItem<int?>(value: 0, child: Text('Cần làm')),
            DropdownMenuItem<int?>(value: 1, child: Text('Đang làm')),
            DropdownMenuItem<int?>(value: 2, child: Text('Hoàn thành')),
            DropdownMenuItem<int?>(value: 3, child: Text('Đã lưu trữ')),
          ],
          onChanged: (value) async {
            taskStatusFilter = value;
            await _loadTasks();
            if (mounted) setState(() {});
          },
        ),
      ),
      Expanded(
        child: tasks.isEmpty
            ? const Center(child: Text('Không tìm thấy công việc.'))
            : ListView.builder(
                itemCount:
                    tasks.length + (tasks.length < taskListTotal ? 1 : 0),
                itemBuilder: (ctx, i) {
                  if (i >= tasks.length)
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: OutlinedButton.icon(
                          onPressed: loadingMoreAdminTasks
                              ? null
                              : _loadMoreAdminTasks,
                          icon: loadingMoreAdminTasks
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more),
                          label: Text(
                            loadingMoreAdminTasks ? 'Đang tải…' : 'Tải thêm',
                          ),
                        ),
                      ),
                    );
                  final task = tasks[i];
                  return ListTile(
                    leading: Icon(
                      task.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: task.done ? Colors.green : null,
                    ),
                    title: Text(task.title),
                    subtitle: Text(
                      '${task.due} • Trạng thái: ${['Cần làm', 'Đang làm', 'Hoàn thành', 'Đã lưu trữ'][task.status.clamp(0, 3)]}',
                    ),
                    trailing: const Icon(Icons.edit_note),
                    onTap: () => _changeAdminTaskStatus(task),
                  );
                },
              ),
      ),
    ],
  );
}

class AdminAccountTasksPage extends StatefulWidget {
  const AdminAccountTasksPage({super.key, required this.user});
  final Map<String, dynamic> user;
  @override
  State<AdminAccountTasksPage> createState() => _AdminAccountTasksPageState();
}

class _AdminAccountTasksPageState extends State<AdminAccountTasksPage> {
  List<TaskItem> tasks = [];
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      tasks = await Api.getTasks(ownerId: widget.user['id'] as String);
      error = null;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.user['displayName'] as String)),
    body: busy
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${widget.user['email']} • ${tasks.length} công việc',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ),
              Expanded(
                child: tasks.isEmpty
                    ? const Center(
                        child: Text('Tài khoản này chưa có công việc.'),
                      )
                    : ListView.builder(
                        itemCount: tasks.length,
                        itemBuilder: (ctx, i) {
                          final t = tasks[i];
                          return ListTile(
                            leading: Icon(
                              t.done
                                  ? Icons.check_circle
                                  : Icons.pending_actions,
                            ),
                            title: Text(t.title),
                            subtitle: Text(
                              '${t.due}${t.reminderIntervalMinutes == null ? '' : ' • nhắc mỗi ${t.reminderIntervalMinutes} phút'}',
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
  );
}

class AdminCreateMemberPage extends StatefulWidget {
  const AdminCreateMemberPage({super.key, required this.groups});
  final List<Map<String, dynamic>> groups;
  @override
  State<AdminCreateMemberPage> createState() => _AdminCreateMemberPageState();
}

class _AdminCreateMemberPageState extends State<AdminCreateMemberPage> {
  final username = TextEditingController(),
      name = TextEditingController(),
      email = TextEditingController(),
      password = TextEditingController();
  String role = 'Member';
  int? workspaceId;
  bool busy = false;
  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await Api.createAdminMember(
        username: username.text.trim(),
        displayName: name.text.trim(),
        email: email.text.trim(),
        password: password.text,
        role: role,
        workspaceId: workspaceId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tạo tài khoản')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Họ và tên',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: username,
          decoration: const InputDecoration(
            labelText: 'Tên đăng nhập',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Mật khẩu khởi tạo (tối thiểu 8 ký tự)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: role,
          decoration: const InputDecoration(
            labelText: 'Vai trò hệ thống',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Member', child: Text('Member')),
            DropdownMenuItem(value: 'Admin', child: Text('Admin')),
          ],
          onChanged: (v) => setState(() => role = v ?? 'Member'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          initialValue: workspaceId,
          decoration: const InputDecoration(
            labelText: 'Nhóm (tùy chọn)',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('Tài khoản cá nhân'),
            ),
            for (final g in widget.groups)
              DropdownMenuItem(
                value: g['id'] as int,
                child: Text(g['name'] as String),
              ),
          ],
          onChanged: (v) => setState(() => workspaceId = v),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : _save,
          icon: const Icon(Icons.person_add),
          label: Text(busy ? 'Đang tạo…' : 'Tạo tài khoản'),
        ),
      ],
    ),
  );
}

class TaskEditorPage extends StatefulWidget {
  const TaskEditorPage({
    super.key,
    required this.group,
    required this.userId,
    required this.categories,
    this.initial,
  });
  final Map<String, dynamic>? group;
  final String? userId;
  final List<Map<String, dynamic>> categories;
  final TaskItem? initial;
  @override
  State<TaskEditorPage> createState() => _TaskEditorPageState();
}

class _TaskEditorPageState extends State<TaskEditorPage> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  late DateTime dueAt;
  late DateTime reminderUntil;
  int? interval;
  int? categoryId;
  int priority = 1;
  int status = 0;
  String? assignee;
  bool get isLeader => widget.group?['role'] == 'Leader';
  @override
  void initState() {
    super.initState();
    final task = widget.initial;
    title.text = task?.title ?? '';
    description.text = task?.description ?? '';
    dueAt = task?.dueAt ?? DateTime.now().add(const Duration(hours: 1));
    reminderUntil = task?.reminderUntil ?? dueAt.add(const Duration(hours: 2));
    interval = task?.reminderIntervalMinutes ?? 5;
    categoryId = task?.categoryId;
    priority = task?.priority ?? 1;
    status = task?.status ?? 0;
    assignee = widget.userId;
  }

  Future<DateTime?> _pick(DateTime current) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  void _save() {
    if (!(form.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      TaskDraft(
        existingTaskId: widget.initial?.id,
        title: title.text.trim(),
        description: description.text.trim(),
        categoryId: categoryId,
        dueAt: dueAt,
        priority: priority,
        status: status,
        workspaceId:
            widget.initial?.workspaceId ??
            (isLeader ? widget.group!['id'] as int : null),
        assignedToUserId: widget.initial != null && !isLeader
            ? widget.initial!.assignedToUserId
            : (isLeader ? assignee : null),
        reminderIntervalMinutes: interval,
        reminderUntil: interval == null ? null : reminderUntil,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members =
        (widget.group?['members'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.initial == null ? 'Thêm công việc' : 'Sửa công việc',
        ),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: title,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Tên công việc',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nhập tên công việc.' : null,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Mô tả',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              initialValue: categoryId,
              decoration: const InputDecoration(
                labelText: 'Danh mục',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Chưa phân loại'),
                ),
                for (final item in widget.categories)
                  DropdownMenuItem<int?>(
                    value: item['id'] as int,
                    child: Text(item['name'] as String),
                  ),
              ],
              onChanged: (value) => setState(() => categoryId = value),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              initialValue: priority,
              decoration: const InputDecoration(
                labelText: 'Mức ưu tiên',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Thấp')),
                DropdownMenuItem(value: 1, child: Text('Bình thường')),
                DropdownMenuItem(value: 2, child: Text('Cao')),
                DropdownMenuItem(value: 3, child: Text('Khẩn cấp')),
              ],
              onChanged: (value) => setState(() => priority = value ?? 1),
            ),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Hạn hoàn thành'),
              subtitle: Text(
                '${MaterialLocalizations.of(context).formatMediumDate(dueAt)} • ${TimeOfDay.fromDateTime(dueAt).format(context)}',
              ),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final selected = await _pick(dueAt);
                if (selected != null)
                  setState(() {
                    dueAt = selected;
                    if (reminderUntil.isBefore(dueAt))
                      reminderUntil = dueAt.add(const Duration(hours: 2));
                  });
              },
            ),
            const Divider(),
            Text('Nhắc nhở', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: interval,
              decoration: const InputDecoration(
                labelText: 'Lặp nhắc',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: null, child: Text('Không nhắc')),
                DropdownMenuItem(value: 5, child: Text('Mỗi 5 phút')),
                DropdownMenuItem(value: 10, child: Text('Mỗi 10 phút')),
                DropdownMenuItem(value: 15, child: Text('Mỗi 15 phút')),
                DropdownMenuItem(value: 30, child: Text('Mỗi 30 phút')),
                DropdownMenuItem(value: 60, child: Text('Mỗi 1 giờ')),
              ],
              onChanged: (v) => setState(() => interval = v),
            ),
            if (interval != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Nhắc đến lúc'),
                subtitle: Text(
                  '${MaterialLocalizations.of(context).formatMediumDate(reminderUntil)} • ${TimeOfDay.fromDateTime(reminderUntil).format(context)}',
                ),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final selected = await _pick(reminderUntil);
                  if (selected != null)
                    setState(() => reminderUntil = selected);
                },
              ),
            if (isLeader) ...[
              const Divider(),
              Text(
                'Giao cho thành viên',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: assignee,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  for (final m in members)
                    DropdownMenuItem(
                      value: m['id'] as String,
                      child: Text(
                        '${m['displayName']}${m['role'] == 'Leader' ? ' (tôi)' : ''}',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => assignee = v),
              ),
            ],
            if (widget.group == null)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Công việc này chỉ thuộc tài khoản cá nhân của bạn.',
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: Text(
                widget.initial == null ? 'Lưu công việc' : 'Cập nhật công việc',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkPlansPage extends StatefulWidget {
  const WorkPlansPage({
    super.key,
    required this.tasks,
    required this.onChanged,
    required this.onCountChanged,
  });
  final List<TaskItem> tasks;
  final Future<void> Function() onChanged;
  final ValueChanged<int> onCountChanged;
  @override
  State<WorkPlansPage> createState() => _WorkPlansPageState();
}

class _WorkPlansPageState extends State<WorkPlansPage> {
  List<Map<String, dynamic>> plans = [];
  bool loading = true;

  Future<void> _load() async {
    try {
      final value = await Api.getPlans();
      if (!mounted) return;
      setState(() {
        plans = value;
        loading = false;
      });
      widget.onCountChanged(
        value
            .where((p) => p['confirmedAt'] == null)
            .fold<int>(
              0,
              (sum, p) => sum + ((p['items'] as List?)?.length ?? 0),
            ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final selected = <int>{};
    final result = await showDialog<(String, List<int>)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Tạo kế hoạch công việc'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tên kế hoạch'),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final task in widget.tasks.where((t) => !t.done))
                        CheckboxListTile(
                          value: selected.contains(task.id),
                          title: Text(task.title),
                          subtitle: Text(task.due),
                          onChanged: (value) => setDialog(() {
                            value == true
                                ? selected.add(task.id)
                                : selected.remove(task.id);
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isNotEmpty && selected.isNotEmpty)
                  Navigator.pop(ctx, (name.text.trim(), selected.toList()));
              },
              child: const Text('Tạo kế hoạch'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    if (result == null) return;
    try {
      await Api.createPlan(result.$1, result.$2);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addTask(Map<String, dynamic> plan) async {
    final included = ((plan['items'] as List?) ?? const [])
        .map((i) => (i as Map<String, dynamic>)['taskId'] as int)
        .toSet();
    final available = widget.tasks
        .where((t) => !included.contains(t.id) && !t.done)
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không còn công việc nào để thêm.')),
      );
      return;
    }
    final task = await showModalBottomSheet<TaskItem>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final item in available)
            ListTile(
              title: Text(item.title),
              subtitle: Text(item.due),
              onTap: () => Navigator.pop(ctx, item),
            ),
        ],
      ),
    );
    if (task == null) return;
    try {
      await Api.addPlanItem(
        plan['id'] as int,
        task.id,
        (plan['items'] as List).length,
      );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _scheduleItem(
    Map<String, dynamic> plan,
    Map<String, dynamic> item,
    int order,
  ) async {
    final initial =
        DateTime.tryParse(item['plannedFor'] as String? ?? '') ??
        DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    try {
      await Api.updatePlanItem(
        plan['id'] as int,
        item['taskId'] as int,
        order,
        DateTime(date.year, date.month, date.day, time.hour, time.minute),
      );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _removeItem(
    Map<String, dynamic> plan,
    Map<String, dynamic> item,
  ) async {
    try {
      await Api.removePlanItem(plan['id'] as int, item['taskId'] as int);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Kế hoạch công việc'),
      actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _create,
      icon: const Icon(Icons.add),
      label: const Text('Tạo kế hoạch'),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : plans.isEmpty
        ? const Center(
            child: Text(
              'Chưa có kế hoạch. Chọn các công việc để lập lịch và xác nhận.',
            ),
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
            children: [
              for (final plan in plans)
                Card(
                  child: ExpansionTile(
                    leading: Icon(
                      plan['confirmedAt'] == null
                          ? Icons.shopping_bag_outlined
                          : Icons.task_alt,
                      color: plan['confirmedAt'] == null ? null : Colors.green,
                    ),
                    title: Text(plan['name'] as String),
                    subtitle: Text(
                      '${(plan['items'] as List).length} công việc • ${plan['confirmedAt'] == null ? 'Bản nháp' : 'Đã xác nhận'}',
                    ),
                    children: [
                      for (var i = 0; i < (plan['items'] as List).length; i++)
                        Builder(
                          builder: (ctx) {
                            final item =
                                (plan['items'] as List)[i]
                                    as Map<String, dynamic>;
                            final planned = DateTime.tryParse(
                              item['plannedFor'] as String? ?? '',
                            );
                            return ListTile(
                              leading: CircleAvatar(child: Text('${i + 1}')),
                              title: Text(
                                item['title'] as String? ?? 'Công việc',
                              ),
                              subtitle: Text(
                                planned == null
                                    ? 'Chưa xếp giờ'
                                    : 'Dự kiến: ${MaterialLocalizations.of(context).formatMediumDate(planned)} • ${TimeOfDay.fromDateTime(planned).format(context)}',
                              ),
                              trailing: plan['confirmedAt'] == null
                                  ? Wrap(
                                      children: [
                                        IconButton(
                                          tooltip: 'Xếp lịch',
                                          onPressed: () =>
                                              _scheduleItem(plan, item, i),
                                          icon: const Icon(Icons.event),
                                        ),
                                        IconButton(
                                          tooltip: 'Gỡ khỏi kế hoạch',
                                          onPressed: () =>
                                              _removeItem(plan, item),
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                          ),
                                        ),
                                      ],
                                    )
                                  : null,
                            );
                          },
                        ),
                      if (plan['confirmedAt'] == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: () => _addTask(plan),
                                icon: const Icon(Icons.add),
                                label: const Text('Thêm việc'),
                              ),
                              TextButton.icon(
                                onPressed: () async {
                                  try {
                                    await Api.deletePlan(plan['id'] as int);
                                    await _load();
                                  } catch (e) {
                                    if (mounted)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                  }
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Xóa'),
                              ),
                              FilledButton.icon(
                                onPressed: () async {
                                  try {
                                    await Api.confirmPlan(plan['id'] as int);
                                    await _load();
                                    await widget.onChanged();
                                  } catch (e) {
                                    if (mounted)
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text('$e')),
                                      );
                                  }
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('Xác nhận kế hoạch'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
  );
}

class CategoryAdminPage extends StatefulWidget {
  const CategoryAdminPage({super.key});
  @override
  State<CategoryAdminPage> createState() => _CategoryAdminPageState();
}

class _CategoryAdminPageState extends State<CategoryAdminPage> {
  List<Map<String, dynamic>> items = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Api.getCategories();
      if (mounted)
        setState(() {
          items = result;
          error = null;
          loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          loading = false;
        });
    }
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final name = TextEditingController(text: item?['name'] as String? ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item == null ? 'Thêm danh mục' : 'Sửa danh mục'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tên danh mục'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, name.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (value == null || value.isEmpty) return;
    try {
      await Api.saveCategory(
        id: item?['id'] as int?,
        name: value,
        color: item?['color'] as String? ?? '#4759D6',
      );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quản lý danh mục')),
    floatingActionButton: FloatingActionButton(
      onPressed: () => _edit(),
      child: const Icon(Icons.add),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : ListView(
            children: [
              for (final item in items)
                ListTile(
                  title: Text(item['name'] as String),
                  leading: const Icon(Icons.folder_outlined),
                  onTap: () => _edit(item),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      try {
                        await Api.deleteCategory(item['id'] as int);
                        await _load();
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    },
                  ),
                ),
            ],
          ),
  );
}

class MemberAdminPage extends StatefulWidget {
  const MemberAdminPage({super.key});
  @override
  State<MemberAdminPage> createState() => _MemberAdminPageState();
}

class _MemberAdminPageState extends State<MemberAdminPage> {
  List<Map<String, dynamic>> items = [];
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Api.getMembers();
      if (mounted)
        setState(() {
          items = result;
          error = null;
          loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          loading = false;
        });
    }
  }

  Future<void> _role(Map<String, dynamic> item) async {
    final roles = item['roles'] as List? ?? const [];
    final current = roles.isEmpty ? 'Member' : roles.first as String;
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Vai trò: ${item['displayName']}'),
        children: [
          for (final role in ['Admin', 'Member'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, role),
              child: Row(
                children: [
                  if (role == current) const Icon(Icons.check, size: 18),
                  const SizedBox(width: 8),
                  Text(role),
                ],
              ),
            ),
        ],
      ),
    );
    if (next == null) return;
    try {
      await Api.setMemberRole(item['id'] as String, next);
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Quản lý thành viên')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : ListView(
            children: [
              for (final item in items)
                ListTile(
                  title: Text(item['displayName'] as String),
                  subtitle: Text('${item['userName']} • ${item['email']}'),
                  leading: CircleAvatar(
                    child: Text(
                      (item['displayName'] as String).characters.first,
                    ),
                  ),
                  onTap: () => _role(item),
                  trailing: Switch(
                    value: item['isActive'] as bool,
                    onChanged: (v) async {
                      try {
                        await Api.setMemberActive(item['id'] as String, v);
                        await _load();
                      } catch (e) {
                        if (mounted)
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    },
                  ),
                ),
            ],
          ),
  );
}
