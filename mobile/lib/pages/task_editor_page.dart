import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/task_item.dart';
import '../services/api_service.dart';

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
  PlatformFile? selectedImage;
  Uint8List? selectedImageBytes;
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
        imageFile: selectedImage,
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
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (selectedImageBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        selectedImageBytes!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                      ),
                    )
                  else if (widget.initial?.imageUrl != null &&
                      widget.initial!.imageUrl!.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        Api.fullImageUrl(widget.initial!.imageUrl),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 36),
                      ),
                    )
                  else
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add_photo_alternate_outlined, color: Colors.grey),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedImage?.name ??
                              (widget.initial?.imageUrl != null
                                  ? 'Đã có ảnh đại diện'
                                  : 'Chưa chọn ảnh đại diện'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final result = await FilePicker.pickFiles(
                                  type: FileType.custom,
                                  allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
                                );
                                if (result.isNotEmpty) {
                                  final file = result.first;
                                  final bytes = await file.readAsBytes();
                                  setState(() {
                                    selectedImage = file;
                                    selectedImageBytes = bytes;
                                  });
                                }
                              },
                              icon: const Icon(Icons.photo_library, size: 16),
                              label: Text(
                                widget.initial?.imageUrl != null || selectedImage != null
                                    ? 'Đổi ảnh'
                                    : 'Chọn ảnh',
                              ),
                            ),
                            if (selectedImage != null)
                              TextButton(
                                onPressed: () => setState(() {
                                  selectedImage = null;
                                  selectedImageBytes = null;
                                }),
                                child: const Text('Bỏ chọn'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
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

