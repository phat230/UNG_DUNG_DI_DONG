import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/task_item.dart';

class TaskStore {
  static Database? _db;
  static final List<TaskItem> _webTasks = [
    TaskItem(
      1,
      '[Nguyễn Đức Phát] Chốt yêu cầu và sơ đồ use case',
      false,
      'Đồ án',
      description: 'Đồ án',
      priority: 1,
      status: 0,
    ),
    TaskItem(
      2,
      '[Nguyễn Đức Phát] Thiết kế cơ sở dữ liệu SQL Server',
      false,
      'Đồ án',
      description: 'Đồ án',
      priority: 3,
      status: 0,
    ),
    TaskItem(
      3,
      '[Nguyễn Đức Phát] Soạn nội dung báo cáo giữa kỳ',
      false,
      'Học tập',
      description: 'Học tập',
      priority: 1,
      status: 0,
    ),
    TaskItem(
      4,
      '[Bùi Đức Anh] Xây dựng API quản lý công việc',
      false,
      'Backend',
      description: 'Backend',
      priority: 2,
      status: 0,
    ),
    TaskItem(
      5,
      '[Bùi Đức Anh] Tạo API danh mục công việc',
      false,
      'Backend',
      description: 'Backend',
      priority: 1,
      status: 0,
    ),
    TaskItem(
      6,
      '[Bùi Đức Anh] Kiểm tra giao diện trên điện thoại',
      false,
      'Cá nhân',
      description: 'Cá nhân',
      priority: 0,
      status: 0,
    ),
  ];
  static Future<Database> get db async {
    if (kIsWeb) throw UnsupportedError('SQLite is not supported on web.');
    return _db ??= await openDatabase(
      p.join(await getDatabasesPath(), 'taskflow.db'),
      version: 5,
      onCreate: (d, _) async {
        await d.execute(
          'CREATE TABLE tasks(id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,description TEXT NOT NULL DEFAULT \'\',dueAt TEXT,priority INTEGER NOT NULL DEFAULT 1,status INTEGER NOT NULL DEFAULT 0,category TEXT NOT NULL DEFAULT \'Cá nhân\',updatedAt TEXT NOT NULL,workspaceId INTEGER,assignedToUserId TEXT,reminderIntervalMinutes INTEGER,reminderUntil TEXT,categoryId INTEGER,imageUrl TEXT)',
        );
        await d.execute(
          'CREATE TABLE sync_queue(id INTEGER PRIMARY KEY AUTOINCREMENT,entity TEXT NOT NULL,entityId INTEGER NOT NULL,operation TEXT NOT NULL,payload TEXT NOT NULL,createdAt TEXT NOT NULL)',
        );
        final now = DateTime.now();
        final samples = [
          (
            '[Nguyễn Đức Phát] Chốt yêu cầu và sơ đồ use case',
            'Đồ án',
            1,
            0,
            1,
          ),
          (
            '[Nguyễn Đức Phát] Thiết kế cơ sở dữ liệu SQL Server',
            'Đồ án',
            2,
            0,
            3,
          ),
          (
            '[Nguyễn Đức Phát] Soạn nội dung báo cáo giữa kỳ',
            'Học tập',
            5,
            0,
            1,
          ),
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
        if (oldVersion < 5)
          await d.execute('ALTER TABLE tasks ADD COLUMN imageUrl TEXT');
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
            imageUrl: r['imageUrl'] as String?,
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
      _webTasks.add(
        TaskItem(
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
        ),
      );
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
          'imageUrl': task.imageUrl,
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

