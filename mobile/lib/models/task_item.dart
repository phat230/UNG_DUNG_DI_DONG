import 'package:file_picker/file_picker.dart';

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
    this.imageUrl,
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
  final String? imageUrl;
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
    this.imageFile,
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
  final PlatformFile? imageFile;
}

