import 'package:flutter/material.dart';
import '../../models/task_item.dart';
import '../../services/api_service.dart';
import '../category_admin_page.dart';
import '../member_admin_page.dart';
import 'admin_account_tasks_page.dart';
import 'admin_create_member_page.dart';

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

  Future<void> _deleteMember(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa tài khoản?'),
        content: Text(
          'Tài khoản ${user['displayName']} và các công việc cá nhân, kế hoạch của tài khoản sẽ bị xóa vĩnh viễn. Hành động này không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa tài khoản'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Api.deleteMember(user['id'] as String);
      await _refresh();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _deleteAdminTask(TaskItem task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa công việc?'),
        content: Text(
          '“${task.title}” và các tệp đính kèm sẽ bị xóa vĩnh viễn. Nếu công việc đang ở trong kế hoạch, công việc sẽ được gỡ khỏi kế hoạch đó.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa công việc'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Api.deleteTask(task.id);
      await _loadTasks();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
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
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            u['isActive'] == true
                                ? Icons.chevron_right
                                : Icons.block,
                            color: u['isActive'] == true ? null : Colors.red,
                          ),
                          IconButton(
                            tooltip: 'Xóa tài khoản',
                            onPressed: () => _deleteMember(u),
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                          ),
                        ],
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_note),
                        IconButton(
                          tooltip: 'Xóa công việc',
                          onPressed: () => _deleteAdminTask(task),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _changeAdminTaskStatus(task),
                  );
                },
              ),
      ),
    ],
  );
}

