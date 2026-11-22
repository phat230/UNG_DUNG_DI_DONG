import 'package:flutter/material.dart';

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

