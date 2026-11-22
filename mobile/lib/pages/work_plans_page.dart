import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../services/api_service.dart';

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
  String? error;

  List<Map<String, dynamic>> _itemsOf(Map<String, dynamic> plan) {
    final raw = plan['items'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  Future<void> _load() async {
    try {
      final value = await Api.getPlans();
      if (!mounted) return;
      setState(() {
        plans = value;
        loading = false;
        error = null;
      });
      widget.onCountChanged(
        value
            .where((p) => p['confirmedAt'] == null)
            .fold<int>(0, (sum, p) => sum + _itemsOf(p).length),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = '$e';
        });
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
    final included = _itemsOf(
      plan,
    ).map((i) => int.tryParse('${i['taskId']}')).whereType<int>().toSet();
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
        int.parse('${plan['id']}'),
        task.id,
        _itemsOf(plan).length,
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
        int.parse('${plan['id']}'),
        int.parse('${item['taskId']}'),
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
      await Api.removePlanItem(
        int.parse('${plan['id']}'),
        int.parse('${item['taskId']}'),
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
        : error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    'Không tải được kế hoạch. $error',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          )
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
                    title: Text(plan['name']?.toString() ?? 'Kế hoạch'),
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
                                    await Api.deletePlan(
                                      int.parse('${plan['id']}'),
                                    );
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
                                    await Api.confirmPlan(
                                      int.parse('${plan['id']}'),
                                    );
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

