// lib/src/pages/timeline/timeline_sheets.dart
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/timeline_models.dart';
import '../../services/timeline_preferences.dart';
import '../../theme/app_theme.dart';
import 'timeline_widgets.dart';

/// الإجراء الذي اختاره المستخدم من ورقة تفاصيل الدرس.
enum LessonAction {
  end,
  cancel,
  start,
  confirm,
  revert,
  edit,
  delete,
  editNote,
  openTimer,
}

/// نتيجة ورقة «تم الإنهاء».
class EndLessonResult {
  final DateTime start;
  final DateTime end;
  final double amount;
  final String note;
  const EndLessonResult({
    required this.start,
    required this.end,
    required this.amount,
    required this.note,
  });
}

Future<T?> showTimelineSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollable = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: scrollable
            ? SingleChildScrollView(child: builder(ctx))
            : builder(ctx),
      ),
    ),
  );
}

// =====================================================================
// ورقة تفاصيل الدرس
// =====================================================================

Future<LessonAction?> showLessonDetailsSheet(
  BuildContext context, {
  required TimelineLesson lesson,
  required TimelinePreferencesData prefs,
  required Color accent,
}) {
  return showTimelineSheet<LessonAction>(
    context,
    builder: (ctx) => _LessonDetailsSheet(
      lesson: lesson,
      prefs: prefs,
      accent: accent,
    ),
  );
}

class _LessonDetailsSheet extends StatelessWidget {
  const _LessonDetailsSheet({
    required this.lesson,
    required this.prefs,
    required this.accent,
  });

  final TimelineLesson lesson;
  final TimelinePreferencesData prefs;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = lesson.status;
    final isPastDay = lesson.isPastDay;
    final isRunning = status == TimelineStatus.started;
    final canEnd = status.isActionable;
    final canCancel = status.isActionable;
    final canStart = !isPastDay &&
        (status == TimelineStatus.scheduled ||
            status == TimelineStatus.recurring) &&
        lesson.isToday;
    final canConfirm = status == TimelineStatus.recurring && !isPastDay;
    final canRevert = status.isFinal && !lesson.isVirtual;
    final canEdit = !lesson.isVirtual &&
        (status == TimelineStatus.scheduled ||
            status == TimelineStatus.pending ||
            status == TimelineStatus.missed);
    final canDelete = !lesson.isVirtual;

    final actions = <Widget>[];
    if (isRunning) {
      actions.add(ActionTile(
        icon: Icons.timer_rounded,
        label: 'المؤقّت',
        color: TimelineStatus.started.color,
        filled: true,
        onTap: () => Navigator.pop(context, LessonAction.openTimer),
      ));
    }
    if (canEnd) {
      actions.add(ActionTile(
        icon: Icons.check_circle_rounded,
        label: 'تم الإنهاء',
        color: AppTheme.success,
        filled: !isRunning,
        onTap: () => Navigator.pop(context, LessonAction.end),
      ));
    }
    if (canCancel) {
      actions.add(ActionTile(
        icon: Icons.cancel_rounded,
        label: 'إلغاء الدرس',
        color: AppTheme.danger,
        onTap: () => Navigator.pop(context, LessonAction.cancel),
      ));
    }
    if (canStart) {
      actions.add(ActionTile(
        icon: Icons.play_arrow_rounded,
        label: 'ابدأ الآن',
        color: TimelineStatus.started.color,
        onTap: () => Navigator.pop(context, LessonAction.start),
      ));
    }
    if (canConfirm) {
      actions.add(ActionTile(
        icon: Icons.event_available_rounded,
        label: 'تأكيد الموعد',
        color: scheme.primary,
        onTap: () => Navigator.pop(context, LessonAction.confirm),
      ));
    }
    if (canRevert) {
      actions.add(ActionTile(
        icon: Icons.undo_rounded,
        label: 'إعادة للمجدول',
        color: scheme.primary,
        onTap: () => Navigator.pop(context, LessonAction.revert),
      ));
    }

    final secondary = <Widget>[];
    if (canEdit) {
      secondary.add(_SecondaryButton(
        icon: Icons.edit_calendar_rounded,
        label: 'تعديل',
        onTap: () => Navigator.pop(context, LessonAction.edit),
      ));
    }
    if (!lesson.isVirtual) {
      secondary.add(_SecondaryButton(
        icon: Icons.sticky_note_2_outlined,
        label: lesson.note.isEmpty ? 'إضافة ملاحظة' : 'تعديل الملاحظة',
        onTap: () => Navigator.pop(context, LessonAction.editNote),
      ));
    }
    if (canDelete) {
      secondary.add(_SecondaryButton(
        icon: Icons.delete_outline_rounded,
        label: 'حذف',
        color: AppTheme.danger,
        onTap: () => Navigator.pop(context, LessonAction.delete),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // رأس البطاقة
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.16),
                  accent.withValues(alpha: 0.05),
                ],
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                StudentAvatar(name: lesson.studentName, color: accent, size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.studentName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        TimelineFormat.relativeDay(lesson.start),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusChip(status: status),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // معلومات سريعة
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.schedule_rounded,
                  label: 'الوقت',
                  value: TimelineFormat.range(
                    lesson.start,
                    lesson.end,
                    use24h: prefs.use24h,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoTile(
                  icon: Icons.hourglass_bottom_rounded,
                  label: 'المدة',
                  value: TimelineFormat.duration(lesson.minutes),
                ),
              ),
              if (prefs.showAmounts) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoTile(
                    icon: Icons.payments_rounded,
                    label: status == TimelineStatus.ended
                        ? 'المبلغ'
                        : 'تقديري',
                    value: TimelineFormat.money(lesson.displayAmount),
                  ),
                ),
              ],
            ],
          ),

          if (lesson.recurring != null) ...[
            const SizedBox(height: 10),
            _NoteLine(
              icon: Icons.event_repeat_rounded,
              text: 'سلسلة متكررة • ${TimelineFormat.repeatLabel(lesson.recurring!)}',
              color: TimelineStatus.recurring.color,
            ),
          ],
          if (lesson.note.isNotEmpty) ...[
            const SizedBox(height: 10),
            _NoteLine(
              icon: Icons.sticky_note_2_outlined,
              text: lesson.note,
              color: scheme.primary,
            ),
          ],
          if (lesson.cancelReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            _NoteLine(
              icon: Icons.info_outline_rounded,
              text: 'سبب الإلغاء: ${lesson.cancelReason}',
              color: AppTheme.danger,
            ),
          ],
          if (status == TimelineStatus.missed) ...[
            const SizedBox(height: 10),
            _NoteLine(
              icon: Icons.warning_amber_rounded,
              text: 'انقضى وقت هذا الدرس دون تسجيل نتيجته — حدّد إن كان قد تم أو أُلغي.',
              color: AppTheme.warning,
            ),
          ],

          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: actions[i]),
                ],
              ],
            ),
          ],
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: secondary,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: color, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: c,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}

// =====================================================================
// ورقة «تم الإنهاء» — نفس منطق صفحة إضافة درس منتهي
// =====================================================================

Future<EndLessonResult?> showEndLessonSheet(
  BuildContext context, {
  required TimelineLesson lesson,
  required TimelinePreferencesData prefs,
  required Color accent,
}) {
  return showTimelineSheet<EndLessonResult>(
    context,
    builder: (ctx) => _EndLessonSheet(
      lesson: lesson,
      prefs: prefs,
      accent: accent,
    ),
  );
}

class _EndLessonSheet extends StatefulWidget {
  const _EndLessonSheet({
    required this.lesson,
    required this.prefs,
    required this.accent,
  });

  final TimelineLesson lesson;
  final TimelinePreferencesData prefs;
  final Color accent;

  @override
  State<_EndLessonSheet> createState() => _EndLessonSheetState();
}

class _EndLessonSheetState extends State<_EndLessonSheet> {
  late DateTime _start;
  late DateTime _end;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  bool _amountEdited = false;

  static const _presets = [30, 45, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    final l = widget.lesson;
    _start = l.start;
    // للدرس الجاري: النهاية = الآن (كما في صفحة إنهاء الدرس)
    if (l.status == TimelineStatus.started) {
      final now = DateTime.now();
      _end = now.isAfter(_start) ? now : l.end;
    } else {
      _end = l.end;
    }
    _amount = TextEditingController(text: _calcAmount().toStringAsFixed(0));
    _note = TextEditingController(text: l.note);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _minutes => _end.difference(_start).inMinutes;

  double _calcAmount() {
    final rate = widget.lesson.hourlyRate;
    if (_minutes <= 0 || rate <= 0) return 0;
    return double.parse(((_minutes / 60) * rate).toStringAsFixed(2));
  }

  void _syncAmount() {
    if (!_amountEdited) {
      _amount.text = _calcAmount().toStringAsFixed(0);
    }
  }

  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      builder: (ctx, child) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            alwaysUse24HourFormat: widget.prefs.use24h,
          ),
          child: child!,
        ),
      ),
    );
    if (t == null) return;
    setState(() {
      final picked = DateTime(base.year, base.month, base.day, t.hour, t.minute);
      if (isStart) {
        final d = _end.difference(_start);
        _start = picked;
        _end = _start.add(d.inMinutes > 0 ? d : const Duration(hours: 1));
      } else {
        _end = picked.isAfter(_start) ? picked : _start.add(const Duration(minutes: 30));
      }
      _syncAmount();
    });
  }

  void _applyPreset(int m) {
    timelineHaptic(widget.prefs.haptics);
    setState(() {
      _end = _start.add(Duration(minutes: m));
      _amountEdited = false;
      _syncAmount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l = widget.lesson;
    final valid = _end.isAfter(_start);
    final rate = l.hourlyRate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppTheme.success),
            ),
            title: 'تسجيل الدرس كمنتهي',
            subtitle: '${l.studentName} • ${TimelineFormat.relativeDay(l.start)}',
          ),
          const SizedBox(height: 16),

          SheetSection(
            title: 'الوقت الفعلي',
            icon: Icons.schedule_rounded,
            child: Row(
              children: [
                Expanded(
                  child: _TimeButton(
                    label: 'البداية',
                    value: TimelineFormat.time(_start, use24h: widget.prefs.use24h),
                    onTap: () => _pickTime(isStart: true),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_back_rounded, size: 18, color: scheme.outline),
                const SizedBox(width: 8),
                Expanded(
                  child: _TimeButton(
                    label: 'النهاية',
                    value: TimelineFormat.time(_end, use24h: widget.prefs.use24h),
                    onTap: () => _pickTime(isStart: false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final m in _presets) ...[
                  Center(
                    child: PillChoice(
                      label: TimelineFormat.duration(m),
                      selected: _minutes == m,
                      color: widget.accent,
                      onTap: () => _applyPreset(m),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          SheetSection(
            title: 'المبلغ',
            icon: Icons.payments_rounded,
            child: TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() => _amountEdited = true),
              decoration: InputDecoration(
                suffixText: 'ر.ق',
                helperText: rate > 0
                    ? 'محسوب من سعر الساعة (${TimelineFormat.money(rate)}) • ${TimelineFormat.duration(_minutes)}'
                    : 'لم يُحدَّد سعر ساعة للطالب — أدخل المبلغ يدوياً',
                helperMaxLines: 2,
                prefixIcon: IconButton(
                  tooltip: 'إعادة الحساب',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => setState(() {
                    _amountEdited = false;
                    _syncAmount();
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'ملاحظة (اختياري)',
              prefixIcon: Icon(Icons.sticky_note_2_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: !valid
                ? null
                : () {
                    timelineHaptic(widget.prefs.haptics, heavy: true);
                    Navigator.pop(
                      context,
                      EndLessonResult(
                        start: _start,
                        end: _end,
                        amount: double.tryParse(_amount.text.trim()) ??
                            _calcAmount(),
                        note: _note.text.trim(),
                      ),
                    );
                  },
            icon: const Icon(Icons.check_rounded),
            label: Text(
              valid
                  ? 'تأكيد الإنهاء • ${TimelineFormat.money(double.tryParse(_amount.text.trim()) ?? 0)}'
                  : 'وقت النهاية يجب أن يكون بعد البداية',
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// ورقة الإلغاء
// =====================================================================

Future<String?> showCancelLessonSheet(
  BuildContext context, {
  required TimelineLesson lesson,
  required TimelinePreferencesData prefs,
}) {
  return showTimelineSheet<String>(
    context,
    builder: (ctx) => _CancelSheet(lesson: lesson, prefs: prefs),
  );
}

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.lesson, required this.prefs});
  final TimelineLesson lesson;
  final TimelinePreferencesData prefs;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  final _reason = TextEditingController();
  static const _quick = [
    'اعتذار الطالب',
    'ظرف طارئ',
    'مرض',
    'عطلة',
    'تأجيل',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.cancel_rounded, color: AppTheme.danger),
            ),
            title: 'إلغاء الدرس',
            subtitle:
                '${l.studentName} • ${TimelineFormat.time(l.start, use24h: widget.prefs.use24h)} • ${TimelineFormat.relativeDay(l.start)}',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final q in _quick)
                PillChoice(
                  label: q,
                  selected: _reason.text == q,
                  color: AppTheme.danger,
                  onTap: () => setState(() => _reason.text = q),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLines: 2,
            minLines: 1,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'سبب الإلغاء (اختياري)',
              prefixIcon: Icon(Icons.edit_note_rounded),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              timelineHaptic(widget.prefs.haptics, heavy: true);
              Navigator.pop(context, _reason.text.trim());
            },
            icon: const Icon(Icons.cancel_rounded),
            label: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// ورقة تعديل الملاحظة
// =====================================================================

Future<String?> showNoteSheet(BuildContext context, {required String initial}) {
  final c = TextEditingController(text: initial);
  return showTimelineSheet<String>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetHeader(title: 'ملاحظة الدرس'),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            maxLines: 4,
            minLines: 2,
            decoration: const InputDecoration(hintText: 'اكتب ملاحظتك هنا…'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            icon: const Icon(Icons.save_rounded),
            label: const Text('حفظ الملاحظة'),
          ),
        ],
      ),
    ),
  );
}

// =====================================================================
// تأكيد عام
// =====================================================================

Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required IconData icon,
  Color? color,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final c = color ?? scheme.primary;
  final result = await showTimelineSheet<bool>(
    context,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: c, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('رجوع'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: c),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
