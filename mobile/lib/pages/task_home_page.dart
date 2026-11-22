import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_item.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../data/task_store.dart';
import 'task_editor_page.dart';
import 'task_history_page.dart';
import 'work_plans_page.dart';
import 'admin/admin_dashboard_page.dart';

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
      if (draft.imageFile != null) {
        try {
          await Api.uploadTaskImage(notificationId, draft.imageFile!);
        } catch (e) {
          debugPrint('Upload task image error: $e');
        }
      }
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
      if (draft.imageFile != null) {
        try {
          await Api.uploadTaskImage(task.id, draft.imageFile!);
        } catch (e) {
          debugPrint('Upload task image error: $e');
        }
      }
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
    final catColor = _categoryColor(task.categoryId);
    final priorityLabels = ['Thấp', 'Bình thường', 'Cao', 'Khẩn cấp'];
    final priorityColors = [
      const Color(0xFF64748B),
      const Color(0xFF4F46E5),
      const Color(0xFFD97706),
      const Color(0xFFDC2626),
    ];
    final pIdx = task.priority.clamp(0, 3);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (task.imageUrl != null && task.imageUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Image.network(
                      Api.fullImageUrl(task.imageUrl),
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: priorityColors[pIdx].withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: priorityColors[pIdx].withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Ưu tiên: ${priorityLabels[pIdx]}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: priorityColors[pIdx],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: catColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _categoryName(task.categoryId),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: catColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: task.done ? const Color(0xFFECFDF5) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: task.done ? const Color(0xFFA7F3D0) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Text(
                      task.done ? '✓ Đã xong' : '⏳ Cần làm',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: task.done ? const Color(0xFF059669) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                task.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  task.description.isEmpty ? 'Chưa có mô tả chi tiết cho công việc này.' : task.description,
                  style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.4),
                ),
              ),
              const SizedBox(height: 14),
              if (task.dueAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 18, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Text(
                        'Hạn chót: ${MaterialLocalizations.of(context).formatMediumDate(task.dueAt!)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
              if (task.reminderIntervalMinutes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_outlined, size: 18, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Text(
                        'Nhắc nhở mỗi: ${task.reminderIntervalMinutes} phút',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
              if (task.assignedToUserId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 18, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Text(
                        'Người phụ trách: ${_memberName(task.assignedToUserId!)}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                children: [
                  if (_canEditTask(task))
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _editTask(task);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Sửa việc'),
                      ),
                    ),
                  if (_canEditTask(task)) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _showTaskAttachments(task);
                      },
                      icon: const Icon(Icons.attach_file, size: 18),
                      label: const Text('Tệp đính kèm'),
                    ),
                  ),
                ],
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
    return membership?['isCurrent'] == true;
  }

  bool _canEditTask(TaskItem task) {
    if (task.locked) return false;
    if (task.workspaceId == null) return true;
    final membership = groups
        .where((g) => g['groupId'] == task.workspaceId)
        .firstOrNull;
    return membership?['isCurrent'] == true;
  }

  String _categoryName(int? id) =>
      categories
          .where((item) => item['id'] == id)
          .map((item) => item['name'] as String)
          .firstOrNull ??
      'Chưa phân loại';

  Color _categoryColor(int? id) {
    final hex = categories
        .where((item) => item['id'] == id)
        .map((item) => item['color'] as String?)
        .firstOrNull;
    if (hex != null && hex.isNotEmpty) {
      try {
        final clean = hex.replaceAll('#', '');
        return Color(int.parse(clean.length == 6 ? 'FF$clean' : clean, radix: 16));
      } catch (_) {}
    }
    return const Color(0xFF4F46E5);
  }

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
      ? Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.assignment_turned_in_outlined, size: 32, color: Color(0xFF4F46E5)),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Không có nhiệm vụ nào',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Không tìm thấy công việc trong phạm vi hoặc bộ lọc đã chọn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        )
      : ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 100),
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
            final catColor = _categoryColor(task.categoryId);
            final priorityConfig = switch (task.priority.clamp(0, 3)) {
              3 => (
                label: 'Khẩn cấp',
                color: const Color(0xFFDC2626),
                bg: const Color(0xFFFEF2F2),
                border: const Color(0xFFFCA5A5),
                icon: Icons.local_fire_department_rounded,
              ),
              2 => (
                label: 'Cao',
                color: const Color(0xFFD97706),
                bg: const Color(0xFFFFFBEB),
                border: const Color(0xFFFDE68A),
                icon: Icons.priority_high_rounded,
              ),
              1 => (
                label: 'Bình thường',
                color: const Color(0xFF4F46E5),
                bg: const Color(0xFFEEF2FF),
                border: const Color(0xFFC7D2FE),
                icon: Icons.density_medium_rounded,
              ),
              _ => (
                label: 'Thấp',
                color: const Color(0xFF64748B),
                bg: const Color(0xFFF1F5F9),
                border: const Color(0xFFCBD5E1),
                icon: Icons.low_priority_rounded,
              ),
            };

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: task.done ? const Color(0xFFF8FAFC) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: task.done ? const Color(0xFFE2E8F0) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: task.done ? 0.02 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showTaskDetails(task),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: task.done ? null : () => _confirmTaskCompletion(task),
                              child: Container(
                                width: 26,
                                height: 26,
                                margin: const EdgeInsets.only(right: 12, top: 2),
                                decoration: BoxDecoration(
                                  color: task.done ? const Color(0xFF10B981) : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: task.done ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                                    width: 1.8,
                                  ),
                                ),
                                child: task.done
                                    ? const Icon(Icons.check, size: 18, color: Colors.white)
                                    : null,
                              ),
                            ),
                            if (task.imageUrl != null && task.imageUrl!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Image.network(
                                      Api.fullImageUrl(task.imageUrl),
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.title,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w600,
                                      color: task.done ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                                      decoration: task.done ? TextDecoration.lineThrough : null,
                                      height: 1.25,
                                    ),
                                  ),
                                  if (task.description.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      task.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: const Color(0xFF64748B),
                                        decoration: task.done ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: priorityConfig.bg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: priorityConfig.border),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(priorityConfig.icon, size: 12, color: priorityConfig.color),
                                  const SizedBox(width: 3),
                                  Text(
                                    priorityConfig.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: priorityConfig.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: catColor.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(color: catColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _categoryName(task.categoryId),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: catColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (task.due.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.schedule, size: 12, color: Color(0xFF64748B)),
                                    const SizedBox(width: 3),
                                    Text(
                                      task.due,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF475569),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (task.assignedToUserId != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFBFDBFE)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person_outline, size: 12, color: Color(0xFF2563EB)),
                                    const SizedBox(width: 3),
                                    Text(
                                      _memberName(task.assignedToUserId!),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF1D4ED8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (_canEditTask(task))
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                  tooltip: 'Sửa công việc',
                                  icon: const Icon(Icons.edit_outlined, size: 19, color: Color(0xFF64748B)),
                                  onPressed: () => _editTask(task),
                                ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                tooltip: 'Ảnh và tệp đính kèm',
                                icon: const Icon(Icons.attach_file, size: 19, color: Color(0xFF64748B)),
                                onPressed: () => _showTaskAttachments(task),
                              ),
                              if (_canDeleteTask(task))
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                  tooltip: 'Xóa nhiệm vụ',
                                  icon: const Icon(Icons.delete_outline, size: 19, color: Color(0xFFEF4444)),
                                  onPressed: () => _deleteTask(task),
                                ),
                              if (task.done &&
                                  task.workspaceId != null &&
                                  _canDeleteTask(task) &&
                                  task.assignedToUserId != userId)
                                IconButton(
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(6),
                                  tooltip: 'Yêu cầu làm lại',
                                  icon: const Icon(Icons.restart_alt_rounded, size: 19, color: Color(0xFF0284C7)),
                                  onPressed: () => _requestTaskRedo(task),
                                )
                              else if (task.locked)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(Icons.lock, size: 18, color: Color(0xFF94A3B8)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );

  Widget _overviewBody() {
    final visibleTasks = _visibleTasks;
    final pending = visibleTasks.where((t) => !t.done).length;
    final done = visibleTasks.length - pending;
    final progress = visibleTasks.isEmpty ? 0.0 : (done / visibleTasks.length);
    final percent = (progress * 100).round();
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
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF312E81), Color(0xFF4338CA), Color(0xFF2563EB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4338CA).withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.workspace_premium_outlined, size: 14, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              selectedLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$percent% xong',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$done',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5, left: 4),
                        child: Text(
                          '/ ${visibleTasks.length} nhiệm vụ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Text(
                        '$pending cần làm',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                      ),
                      const SizedBox(width: 14),
                      Icon(Icons.check_circle_outline, size: 14, color: Colors.white.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Text(
                        '$done hoàn thành',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                      ),
                    ],
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
              prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
              suffixIcon: IconButton(
                tooltip: 'Xóa tìm kiếm',
                onPressed: () {
                  taskSearch.clear();
                  setState(() {});
                  _load();
                },
                icon: const Icon(Icons.close, color: Color(0xFF64748B)),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
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
          child: Row(
            children: [
              Text(
                todayOnly ? 'Nhiệm vụ hôm nay' : 'Danh sách nhiệm vụ',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${visibleTasks.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4F46E5),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '${visibleTasks.length} nhiệm vụ • $pending cần hoàn thành',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
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
        title: Text(['Tổng quan', 'Thông báo', 'Nhóm', 'Kế hoạch'][homeTab]),
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

