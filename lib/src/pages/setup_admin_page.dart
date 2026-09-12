import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class SetupAdminPage extends StatefulWidget {
  const SetupAdminPage({super.key});

  @override
  State<SetupAdminPage> createState() => _SetupAdminPageState();
}

class _SetupAdminPageState extends State<SetupAdminPage> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  String _error = '';
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء حساب الإدارة')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'الاسم'),
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
                      : ElevatedButton(
                    onPressed: () async {
                      setState(() {
                        _error = '';
                        _loading = true;
                      });
                      try {
                        await context.read<AuthProvider>().createAdmin(
                          _nameController.text.trim(),
                          _codeController.text.trim(),
                        );
                        if (context.mounted) {
                          Navigator.pushReplacementNamed(
                              context, '/login');
                        }
                      } catch (e) {
                        setState(() {
                          _error = e
                              .toString()
                              .replaceFirst('Exception: ', '');
                        });
                      } finally {
                        if (mounted) {
                          setState(() => _loading = false);
                        }
                      }
                    },
                    child: const Text('إنشاء الحساب'),
                  ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
