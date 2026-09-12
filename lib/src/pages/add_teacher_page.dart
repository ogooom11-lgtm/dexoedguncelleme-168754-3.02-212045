import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class AddTeacherPage extends StatefulWidget {
  const AddTeacherPage({super.key});

  @override
  State<AddTeacherPage> createState() => _AddTeacherPageState();
}

class _AddTeacherPageState extends State<AddTeacherPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  String _error = '';
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('➕ إضافة معلم جديد')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'اسم المعلم'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _codeController,
                    decoration: const InputDecoration(
                      labelText: 'الكود (8 أرقام)',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  if (_error.isNotEmpty)
                    Text(_error, style: TextStyle(color: cs.error)),
                  const SizedBox(height: 16),
                  _loading
                      ? const CircularProgressIndicator()
                      : ElevatedButton.icon(
                    icon: const Icon(Icons.person_add),
                    onPressed: () async {
                      setState(() {
                        _error = '';
                        _loading = true;
                      });
                      try {
                        await context
                            .read<AuthProvider>()
                            .createTeacher(
                          _nameController.text.trim(),
                          _codeController.text.trim(),
                        );

                        if (context.mounted) {
                          Navigator.pop(context, true); // رجوع لصفحة الإدارة
                        }
                      } catch (e) {
                        setState(() {
                          _error =
                              e.toString().replaceFirst('Exception: ', '');
                          _codeController.clear(); // مسح الكود إذا خطأ
                        });
                      } finally {
                        if (mounted) {
                          setState(() => _loading = false);
                        }
                      }
                    },
                    label: const Text('إضافة المعلم'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
