import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'edit_schedule_page.dart'; // تأكد من المسار الصحيح للملف
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/recurrence_utils.dart';
// تأكد من استيراد المودل الخاص بك هنا بشكل صحيح
// import '../models/recurring_schedule.dart'; 

class RecurringSchedulesPage extends StatefulWidget {
  const RecurringSchedulesPage({super.key});

  @override
  State<RecurringSchedulesPage> createState() => _RecurringSchedulesPageState();
}

class _RecurringSchedulesPageState extends State<RecurringSchedulesPage> {
  bool _loading = true;
  String _error = '';
  final _items = <RecurringSchedule>[];
  final _studentNames = <String, String>{};

  // متغيرات البحث والفلترة
  String _searchQuery = '';
  String _filterType = 'all'; // all, daily, weekly, monthly

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // --- منطق جلب البيانات ---
  Future<void> _loadAll() async {
    final auth = context.read<AuthProvider>();
    final code = auth.currentUser?.code ?? '';
    if (code.isEmpty) {
      setState(() { _loading = false; _error = 'لم يتم العثور على المعلّم'; });
      return;
    }

    try {
      // 1. جلب أسماء الطلاب
      final stSnap = await FirebaseDatabase.instance.ref("users/$code/students").get();
      if (stSnap.exists && stSnap.value is Map) {
        final raw = Map<String, dynamic>.from(stSnap.value as Map);
        raw.forEach((k, v) {
          if (v is Map && v['name'] != null) {
            _studentNames[k] = v['name'].toString();
          } else {
            _studentNames[k] = v?.toString() ?? 'طالب';
          }
        });
      }

      // 2. جلب المواعيد المتكررة
      final ref = FirebaseDatabase.instance.ref("users/$code/recurringSchedules");
      final snap = await ref.get();
      _items.clear();
      if (snap.exists && snap.value is Map) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        for (final e in map.entries) {
          if (e.value is Map) {
            // ملاحظة: تأكد أن fromMap يأخذ المفتاح (e.key) لحفظ الـ ID للحذف
            _items.add(
              RecurringSchedule.fromMap(e.key, Map<String, dynamic>.from(e.value)),
            );
          }
        }
      }
      setState(() { _loading = false; });
    } catch (e) {
      setState(() { _loading = false; _error = 'تعذر التحميل: $e'; });
    }
  }

  // --- منطق الحذف ---
  Future<void> _deleteItem(RecurringSchedule item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذا الموعد المتكرر؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final auth = context.read<AuthProvider>();
    final code = auth.currentUser?.code ?? '';
    if (code.isEmpty) return;

    // الحذف من الفايربيس (نفترض أن المودل يحتوي على خاصية id أو key)
    // item.id هو مفتاح العنصر في قاعدة البيانات
    try {
      await FirebaseDatabase.instance
          .ref("users/$code/recurringSchedules/${item.id}")
          .remove();

      setState(() {
        _items.remove(item);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الموعد بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- منطق التعديل ---
  void _editItem(RecurringSchedule item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditSchedulePage(schedule: item),
      ),
    ).then((_) {
      // هذه الدالة تنفذ "بعد" العودة من صفحة التعديل
      // نقوم بإعادة تحميل البيانات لتظهر التعديلات الجديدة في القائمة
      _loadAll();
    });
  }

  // --- الفلترة والبحث ---
  List<RecurringSchedule> get _filteredItems {
    return _items.where((r) {
      // 1. فلتر البحث بالاسم
      final name = (_studentNames[r.student] ?? 'طالب').toLowerCase();
      final matchSearch = name.contains(_searchQuery.toLowerCase().trim());

      // 2. فلتر النوع (يومي/أسبوعي...)
      bool matchType = true;
      if (_filterType != 'all') {
        matchType = (r.repeatType == _filterType);
      }

      return matchSearch && matchType;
    }).toList();
  }

  // --- بناء الواجهة ---
  @override
  Widget build(BuildContext context) {
    final themeProv = context.watch<ThemeProvider>();
    final isDark = themeProv.mode == ThemeMode.dark;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface, // لون خلفية حديث
      appBar: AppBar(
        title: const Text('المواعيد المتكررة', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // قسم البحث والفلترة
          _buildSearchAndFilterBar(scheme),

          // قائمة العناصر
          Expanded(
            child: _loading
                ? const _LoadingState()
                : _error.isNotEmpty
                ? _ErrorState(message: _error, onRetry: _loadAll)
                : _filteredItems.isEmpty
                ? const _EmptyState()
                : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _filteredItems.length,
                separatorBuilder: (c, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _filteredItems[index];
                  return _RecurringCard(
                    item: item,
                    studentName: _studentNames[item.student] ?? 'طالب',
                    onDelete: () => _deleteItem(item),
                    onEdit: () => _editItem(item),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // مربع البحث
              Expanded(
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: scheme.outlineVariant.withOpacity(0.2)),
                  ),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
                      hintText: 'ابحث عن طالب...',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // زر الفلترة
              Container(
                height: 50,
                width: 50,
                decoration: BoxDecoration(
                  color: _filterType == 'all' ? scheme.surfaceContainerHighest.withOpacity(0.5) : scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: scheme.outlineVariant.withOpacity(0.2)),
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.filter_list_rounded,
                    color: _filterType == 'all' ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
                  ),
                  onPressed: _showFilterDialog,
                ),
              ),
            ],
          ),

          // عرض شريط صغير يوضح الفلتر المختار إذا لم يكن "الكل"
          if (_filterType != 'all')
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Row(
                children: [
                  Text('الفلترة حسب: ', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  Chip(
                    label: Text(_getFilterLabel(_filterType)),
                    backgroundColor: scheme.primaryContainer,
                    labelStyle: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => setState(() => _filterType = 'all'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _getFilterLabel(String type) {
    switch (type) {
      case 'daily': return 'يومي';
      case 'weekly': return 'أسبوعي';
      case 'monthly': return 'شهري';
      default: return 'الكل';
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('تصفية حسب التكرار', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.all_inclusive),
                title: const Text('عرض الكل'),
                selected: _filterType == 'all',
                onTap: () { setState(() => _filterType = 'all'); Navigator.pop(ctx); },
              ),
              ListTile(
                leading: const Icon(Icons.today),
                title: const Text('يومي'),
                selected: _filterType == 'daily',
                onTap: () { setState(() => _filterType = 'daily'); Navigator.pop(ctx); },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_view_week),
                title: const Text('أسبوعي'),
                selected: _filterType == 'weekly',
                onTap: () { setState(() => _filterType = 'weekly'); Navigator.pop(ctx); },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('شهري'),
                selected: _filterType == 'monthly',
                onTap: () { setState(() => _filterType = 'monthly'); Navigator.pop(ctx); },
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- تصميم البطاقة الجديد ---
class _RecurringCard extends StatelessWidget {
  final RecurringSchedule item;
  final String studentName;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _RecurringCard({
    required this.item,
    required this.studentName,
    required this.onDelete,
    required this.onEdit,
  });

  String _repeatLabel(RecurringSchedule r) {
    switch (r.repeatType) {
      case 'daily': return 'يومي (${r.repeatInterval})';
      case 'everyXDays': return 'كل ${r.repeatInterval} يوم';
      case 'weekly': return 'أسبوعي';
      case 'monthly': return 'شهري';
      default: return 'بدون';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dfTime = DateFormat('HH:mm');
    final dfDate = DateFormat('yyyy-MM-dd');

    // حساب الموعد القادم
    DateTime? next;
    for (int d = 0; d <= 60; d++) {
      final day = DateTime.now().add(Duration(days: d));
      if (RecurrenceUtils.occursOn(item, day)) { next = day; break; }
    }
    final nextStr = next != null ? dfDate.format(next) : '—';

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // الجزء العلوي: المعلومات الأساسية
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAvatar(studentName, scheme),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              studentName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _buildStatusChip(item, scheme),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, size: 16, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            '${dfTime.format(item.startTime)} - ${dfTime.format(item.endTime)}',
                            style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.next_plan_outlined, size: 16, color: scheme.tertiary),
                          const SizedBox(width: 4),
                          Text('القادم: $nextStr', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // فاصل
          Divider(height: 1, color: scheme.outlineVariant.withOpacity(0.3)),

          // الجزء السفلي: أزرار التحكم
          InkWell(
            onTap: () {}, // لامتصاص النقر في الخلفية
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
            child: Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.edit_outlined,
                    label: 'تعديل',
                    color: scheme.primary,
                    onTap: onEdit,
                  ),
                ),
                Container(width: 1, height: 30, color: scheme.outlineVariant.withOpacity(0.3)),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.delete_outline,
                    label: 'حذف',
                    color: scheme.error,
                    onTap: onDelete,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String name, ColorScheme scheme) {
    final initials = (name.isNotEmpty)
        ? name.trim().split(RegExp(r'\s+')).take(2).map((w) => w.characters.first.toUpperCase()).join()
        : '?';
    return CircleAvatar(
      radius: 22,
      backgroundColor: scheme.primaryContainer,
      child: Text(initials, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatusChip(RecurringSchedule r, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _repeatLabel(r),
        style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// --- حالات التحميل والخطأ والفارغ (كما هي مع تحسين بسيط) ---

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: scheme.error),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton.tonal(onPressed: onRetry, child: const Text('إعادة المحاولة')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_outlined, size: 60, color: scheme.outline.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'لا توجد مواعيد متكررة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: scheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'استخدم زر الإضافة لإنشاء جداول جديدة',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}