import 'dart:ui' as ui;

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'account_details_page.dart';
import 'add_teacher_page.dart';

class HomeAdmin extends StatefulWidget {
  const HomeAdmin({super.key});

  @override
  State<HomeAdmin> createState() => _HomeAdminState();
}

class _HomeAdminState extends State<HomeAdmin> {
  final _searchController = TextEditingController();
  String _roleFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final dbRef = FirebaseDatabase.instance.ref("users");

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("لوحة الإدارة"),
          actions: [
            IconButton(
              tooltip: 'إضافة معلم',
              onPressed: () => _openAddTeacher(context),
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ],
        ),
        drawer: _AdminDrawer(
          name: auth.currentUser?.name ?? "مدير",
          email: auth.currentUser?.email ?? "no-email",
          onAddTeacher: () => _openAddTeacher(context),
          onLogout: () {
            auth.signOut();
            Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
          },
        ),
        body: StreamBuilder<DatabaseEvent>(
          stream: dbRef.onValue,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final accounts = _parseAccounts(snapshot.data?.snapshot.value);
            final filtered = _filterAccounts(accounts);

            if (accounts.isEmpty) {
              return _AdminEmptyState(
                  onAddTeacher: () => _openAddTeacher(context));
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100
                    ? 3
                    : constraints.maxWidth >= 720
                        ? 2
                        : 1;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _AdminHeader(
                      name: auth.currentUser?.name ?? 'مدير',
                      total: accounts.length,
                      onAddTeacher: () => _openAddTeacher(context),
                    ),
                    const SizedBox(height: 12),
                    _StatsBand(accounts: accounts),
                    const SizedBox(height: 12),
                    _FiltersBar(
                      controller: _searchController,
                      roleFilter: _roleFilter,
                      onSearchChanged: (_) => setState(() {}),
                      onRoleChanged: (value) =>
                          setState(() => _roleFilter = value),
                    ),
                    const SizedBox(height: 12),
                    if (filtered.isEmpty)
                      const _NoResults()
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: columns == 1 ? 3.25 : 2.75,
                        ),
                        itemBuilder: (context, index) {
                          final account = filtered[index];
                          return _AccountCard(
                            account: account,
                            onOpen: () => _openAccount(context, account),
                          );
                        },
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _parseAccounts(Object? value) {
    if (value is! Map) return [];
    final data = Map<String, dynamic>.from(value);
    final accounts = data.entries.map((entry) {
      final userMap = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : <String, dynamic>{};
      return {
        "id": entry.key,
        "name": userMap["name"] ?? "مجهول",
        "role": userMap["role"] ?? "student",
        "email": userMap["email"] ?? "",
      };
    }).toList();
    accounts
        .sort((a, b) => a["name"].toString().compareTo(b["name"].toString()));
    return accounts;
  }

  List<Map<String, dynamic>> _filterAccounts(
      List<Map<String, dynamic>> accounts) {
    final query = _searchController.text.trim().toLowerCase();
    return accounts.where((account) {
      final role = account["role"].toString();
      final matchesRole = _roleFilter == 'all' || role == _roleFilter;
      final text = '${account["name"]} ${account["email"]} ${account["id"]}'
          .toLowerCase();
      return matchesRole && (query.isEmpty || text.contains(query));
    }).toList();
  }

  Future<void> _openAddTeacher(BuildContext context) async {
    Navigator.popUntil(context, (route) => route.isFirst);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddTeacherPage()),
    );
  }

  void _openAccount(BuildContext context, Map<String, dynamic> account) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountDetailsPage(account: account),
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  final String name;
  final int total;
  final VoidCallback onAddTeacher;

  const _AdminHeader({
    required this.name,
    required this.total,
    required this.onAddTeacher,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.primary,
            child: Icon(Icons.admin_panel_settings_rounded,
                color: scheme.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مرحباً $name',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'إدارة $total حساب من مكان واحد',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onAddTeacher,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('إضافة معلم'),
          ),
        ],
      ),
    );
  }
}

class _StatsBand extends StatelessWidget {
  final List<Map<String, dynamic>> accounts;

  const _StatsBand({required this.accounts});

  @override
  Widget build(BuildContext context) {
    final teachers = accounts.where((a) => a["role"] == "teacher").length;
    final students = accounts.where((a) => a["role"] == "student").length;
    final admins = accounts.where((a) => a["role"] == "admin").length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatTile(
          icon: Icons.groups_rounded,
          label: 'كل الحسابات',
          value: accounts.length.toString(),
          color: Colors.indigo,
        ),
        _StatTile(
          icon: Icons.co_present_rounded,
          label: 'المعلمون',
          value: teachers.toString(),
          color: Colors.teal,
        ),
        _StatTile(
          icon: Icons.school_rounded,
          label: 'الطلاب',
          value: students.toString(),
          color: Colors.deepOrange,
        ),
        _StatTile(
          icon: Icons.shield_rounded,
          label: 'الإدارة',
          value: admins.toString(),
          color: Colors.purple,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final TextEditingController controller;
  final String roleFilter;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onSearchChanged;

  const _FiltersBar({
    required this.controller,
    required this.roleFilter,
    required this.onRoleChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            onChanged: onSearchChanged,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'بحث بالاسم أو البريد أو الكود',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _roleChip('all', 'الكل'),
                _roleChip('teacher', 'معلم'),
                _roleChip('student', 'طالب'),
                _roleChip('admin', 'إدارة'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleChip(String value, String label) {
    return ChoiceChip(
      selected: roleFilter == value,
      label: Text(label),
      onSelected: (_) => onRoleChanged(value),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback onOpen;

  const _AccountCard({required this.account, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final role = account["role"].toString();
    final color = _roleColor(role);
    final name = account["name"].toString();
    final email = account["email"].toString();
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Text(
                  initial,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      email.isEmpty ? account["id"].toString() : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _RoleBadge(role: role, color: color),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'فتح الحساب',
                onPressed: onOpen,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.purple;
      case 'teacher':
        return Colors.teal;
      case 'student':
        return Colors.deepOrange;
      default:
        return Colors.blueGrey;
    }
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  final Color color;

  const _RoleBadge({required this.role, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        _roleLabel(role),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'إدارة';
      case 'teacher':
        return 'معلم';
      case 'student':
        return 'طالب';
      default:
        return role;
    }
  }
}

class _AdminDrawer extends StatelessWidget {
  final String name;
  final String email;
  final VoidCallback onAddTeacher;
  final VoidCallback onLogout;

  const _AdminDrawer({
    required this.name,
    required this.email,
    required this.onAddTeacher,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(name),
            accountEmail: Text(email),
            currentAccountPicture: const CircleAvatar(
              child: Icon(Icons.admin_panel_settings, size: 32),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1_rounded),
            title: const Text("إضافة معلم"),
            onTap: onAddTeacher,
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text("تسجيل الخروج"),
            onTap: onLogout,
          ),
        ],
      ),
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  final VoidCallback onAddTeacher;

  const _AdminEmptyState({required this.onAddTeacher});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_accounts_rounded, size: 52),
            const SizedBox(height: 12),
            const Text(
              'لا يوجد بيانات بعد',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAddTeacher,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('إضافة أول معلم'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: const Text('لا توجد حسابات مطابقة'),
    );
  }
}
