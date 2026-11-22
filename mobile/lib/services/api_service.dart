import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_item.dart';
import '../data/task_store.dart';
import 'google_auth_service.dart';

class Api {
  // Android emulator reaches the host computer through 10.0.2.2.
  // Chrome and desktop connect directly to localhost:5000.
  static String get baseUrl {
    const env = String.fromEnvironment('TASKFLOW_API_URL');
    if (env.isNotEmpty) return env;
    if (kIsWeb) return 'http://localhost:5000/api';
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000/api';
    }
    return 'http://localhost:5000/api';
  }
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
    final decoded = jsonDecode(r.body);
    if (decoded is! List) {
      throw Exception('Dữ liệu kế hoạch từ máy chủ không đúng định dạng.');
    }
    return decoded.whereType<Map>().map((rawPlan) {
      final plan = Map<String, dynamic>.from(rawPlan);
      final rawItems = plan['items'];
      plan['items'] = rawItems is List
          ? rawItems.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : <Map<String, dynamic>>[];
      return plan;
    }).toList();
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
        imageUrl: item['imageUrl'] as String?,
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
    if (response.statusCode != 200) {
      String msg = 'Không tải được tệp đính kèm.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          msg = body['message'] as String;
        }
      } catch (_) {}
      throw Exception(msg);
    }
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

  static Future<int> saveCategory({
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
    if (id != null) return id;
    final json = jsonDecode(r.body) as Map<String, dynamic>;
    return json['id'] as int;
  }

  static Future<void> uploadCategoryImage(int categoryId, PlatformFile file) async {
    final prefs = await SharedPreferences.getInstance();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/categories/$categoryId/image'),
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
      final message = response.body.isEmpty ? 'Không tải ảnh danh mục lên được.' : response.body;
      throw Exception(message);
    }
  }

  static Future<void> deleteCategoryImage(int categoryId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.delete(
      Uri.parse('$baseUrl/categories/$categoryId/image'),
      headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không xóa được ảnh danh mục.');
  }

  static Future<void> uploadTaskImage(int taskId, PlatformFile file) async {
    final prefs = await SharedPreferences.getInstance();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/tasks/$taskId/image'),
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
      final message = response.body.isEmpty ? 'Không tải ảnh công việc lên được.' : response.body;
      throw Exception(message);
    }
  }

  static Future<void> deleteTaskImage(int taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.delete(
      Uri.parse('$baseUrl/tasks/$taskId/image'),
      headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
    );
    if (r.statusCode < 200 || r.statusCode >= 300)
      throw Exception('Không xóa được ảnh công việc.');
  }

  static String fullImageUrl(String? relativeUrl) {
    if (relativeUrl == null || relativeUrl.isEmpty) return '';
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    final root = baseUrl.endsWith('/api') ? baseUrl.substring(0, baseUrl.length - 4) : baseUrl;
    return '$root${relativeUrl.startsWith('/') ? '' : '/'}$relativeUrl';
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

  static Future<void> deleteMember(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final r = await http.delete(
      Uri.parse('$baseUrl/admin/members/$id'),
      headers: {'Authorization': 'Bearer ${prefs.getString('jwt')}'},
    );
    if (r.statusCode == 409 || r.statusCode == 400) {
      try {
        final body = jsonDecode(r.body);
        throw Exception(body['message'] ?? 'Không thể xóa tài khoản này.');
      } on FormatException {
        throw Exception('Không thể xóa tài khoản này.');
      }
    }
    if (r.statusCode != 204) throw Exception('Không xóa được tài khoản.');
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
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String msg = 'Không cập nhật được công việc trên API.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          msg = body['message'] as String;
        }
      } catch (_) {}
      throw Exception(msg);
    }
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

