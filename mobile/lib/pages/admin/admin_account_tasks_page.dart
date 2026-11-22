import 'package:flutter/material.dart';
import '../../models/task_item.dart';
import '../../services/api_service.dart';

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

