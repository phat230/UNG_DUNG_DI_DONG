import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';

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
    String selectedColor = item?['color'] as String? ?? '#4759D6';
    PlatformFile? pickedImage;
    Uint8List? pickedImageBytes;
    bool removeCurrentImage = false;
    final currentImageUrl = item?['imageUrl'] as String?;

    final colors = ['#4759D6', '#2E7D32', '#EF6C00', '#C62828', '#6A1B9A', '#00838F'];

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(item == null ? 'Thêm danh mục' : 'Sửa danh mục'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tên danh mục',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Màu đại diện:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final c in colors)
                      GestureDetector(
                        onTap: () => setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(int.parse(c.replaceFirst('#', '0xff'))),
                            shape: BoxShape.circle,
                            border: selectedColor == c
                                ? Border.all(color: Colors.black, width: 2.5)
                                : null,
                          ),
                          child: selectedColor == c
                              ? const Icon(Icons.check, size: 18, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Hình ảnh danh mục:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (pickedImageBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            pickedImageBytes!,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        )
                      else if (!removeCurrentImage && currentImageUrl != null && currentImageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            Api.fullImageUrl(currentImageUrl),
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 32),
                          ),
                        )
                      else
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.image_outlined, color: Colors.grey),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pickedImage?.name ??
                                  (!removeCurrentImage && currentImageUrl != null
                                      ? 'Đã có ảnh đại diện'
                                      : 'Chưa có ảnh'),
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
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
                                      setDialogState(() {
                                        pickedImage = file;
                                        pickedImageBytes = bytes;
                                        removeCurrentImage = false;
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.photo_library, size: 14),
                                  label: Text(
                                    pickedImage != null || (!removeCurrentImage && currentImageUrl != null)
                                        ? 'Đổi ảnh'
                                        : 'Chọn ảnh',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (pickedImage != null || (!removeCurrentImage && currentImageUrl != null))
                                  TextButton(
                                    onPressed: () => setDialogState(() {
                                      pickedImage = null;
                                      pickedImageBytes = null;
                                      removeCurrentImage = true;
                                    }),
                                    child: const Text('Xóa ảnh', style: TextStyle(color: Colors.red, fontSize: 12)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (name.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || name.text.trim().isEmpty) return;

    try {
      final catId = await Api.saveCategory(
        id: item?['id'] as int?,
        name: name.text.trim(),
        color: selectedColor,
      );

      if (pickedImage != null) {
        await Api.uploadCategoryImage(catId, pickedImage!);
      } else if (removeCurrentImage && item?['id'] != null) {
        await Api.deleteCategoryImage(item!['id'] as int);
      }

      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
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
            padding: const EdgeInsets.all(8),
            children: [
              for (final item in items)
                Card(
                  child: ListTile(
                    title: Text(item['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                    leading: item['imageUrl'] != null && (item['imageUrl'] as String).isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              Api.fullImageUrl(item['imageUrl'] as String),
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                backgroundColor: Color(
                                  int.parse((item['color'] as String? ?? '#4759D6').replaceFirst('#', '0xff')),
                                ),
                                child: const Icon(Icons.folder, color: Colors.white),
                              ),
                            ),
                          )
                        : CircleAvatar(
                            backgroundColor: Color(
                              int.parse((item['color'] as String? ?? '#4759D6').replaceFirst('#', '0xff')),
                            ),
                            child: const Icon(Icons.folder, color: Colors.white),
                          ),
                    onTap: () => _edit(item),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Xác nhận xóa'),
                            content: Text('Xóa danh mục "${item['name']}" và hình ảnh kèm theo?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                        try {
                          await Api.deleteCategory(item['id'] as int);
                          await _load();
                        } catch (e) {
                          if (mounted)
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
  );
}

