import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PdfExportService {
  final Map<String, String> students;
  final String? selectedStudentId;

  PdfExportService({
    required this.students,
    this.selectedStudentId,
  });

  /// ✅ التصدير مع نافذة اختيار الأعمدة
  Future<void> exportCurrentFilteredPdf(
      BuildContext context,
      List<Map<String, dynamic>> lessons,
      ) async {
    final scaffold = ScaffoldMessenger.of(context);

    if (lessons.isEmpty) {
      scaffold.showSnackBar(
        const SnackBar(content: Text("لا توجد نتائج مطابقة للفلترة")),
      );
      return;
    }

    // 🔹 تحميل التفضيلات المحفوظة
    final prefs = await SharedPreferences.getInstance();
    final savedColumns = prefs.getStringList("selected_columns");

    final defaultColumns = {
      "amount": "المبلغ",
      "duration": "المدة",
      "time": "الوقت",
      "date": "التاريخ",
      "status": "الحالة",
      "student": "الطالب",
    };

    final selectedColumns = await _showColumnSelectionDialog(
      context,
      availableColumns: defaultColumns,
      preselected: savedColumns?.toSet() ?? defaultColumns.keys.toSet(),
    );

    if (selectedColumns == null) return; // المستخدم لغى العملية

    // 🔹 حفظ التفضيلات
    await prefs.setStringList("selected_columns", selectedColumns.toList());

    try {
      final bytes = await buildPdfBytes(
        lessons,
        selectedColumns: selectedColumns,
      );

      final fileName =
          "lessons_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf";

      await Printing.sharePdf(bytes: bytes, filename: fileName);

      try {
        final dir = await _bestOutputDirectory();
        final file = File("${dir.path}/$fileName");
        await file.writeAsBytes(bytes, flush: true);
        scaffold.showSnackBar(
          SnackBar(content: Text("تم حفظ الملف في: ${file.path}")),
        );
      } catch (e) {
        if (!kIsWeb) {
          scaffold.showSnackBar(
            SnackBar(content: Text("فشل الحفظ المحلي: $e")),
          );
        }
      }
    } catch (e) {
      scaffold.showSnackBar(
        SnackBar(content: Text("فشل التصدير: $e")),
      );
    }
  }

  /// ✅ إنشاء ملف PDF مع ترتيب + أعمدة مختارة
  Future<Uint8List> buildPdfBytes(
      List<Map<String, dynamic>> lessons, {
        required Set<String> selectedColumns,
      }) async {
    final fontData =
    await rootBundle.load('project_root/assets/fonts/cairo-regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    final pdf = pw.Document();

    // 🔹 الترتيب من الأجدد للأقدم
    lessons.sort((a, b) {
      final da =
          DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(1970);
      final db =
          DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(1970);
      return db.compareTo(da);
    });

    final totalAmount = lessons.fold<num>(
        0,
            (prev, e) =>
        prev + (num.tryParse(e['amount']?.toString() ?? '0') ?? 0));

    String studentName = "جميع الطلاب";
    if (selectedStudentId != null && students.containsKey(selectedStudentId)) {
      studentName = students[selectedStudentId]!;
    }

    // 🔹 إعداد الأعمدة حسب اختيار المستخدم
    final headers = <String>[];
    if (selectedColumns.contains("amount")) headers.add("المبلغ");
    if (selectedColumns.contains("duration")) headers.add("المدة");
    if (selectedColumns.contains("time")) headers.add("الوقت");
    if (selectedColumns.contains("date")) headers.add("التاريخ");
    if (selectedColumns.contains("status")) headers.add("الحالة");
    if (selectedColumns.contains("student")) headers.add("الطالب");

    final rows = lessons.map<List<String>>((e) {
      final studentName =
          students[(e['student'] ?? '').toString()] ?? "طالب";
      final date = (e['date'] ?? '').toString();
      final start = _formatTime(e['startTime']);
      final end = _formatTime(e['endTime']);
      final dur = _formatDuration(e['duration']);
      final amount = (e['amount'] ?? '').toString();
      final status = _statusLabel((e['status'] ?? '').toString());

      final row = <String>[];
      if (selectedColumns.contains("amount")) row.add("$amount ر.ق");
      if (selectedColumns.contains("duration")) row.add(dur);
      if (selectedColumns.contains("time")) row.add("($start) حتى ($end)");
      if (selectedColumns.contains("date")) row.add(date);
      if (selectedColumns.contains("status")) row.add(status);
      if (selectedColumns.contains("student")) row.add(studentName);

      return row;
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  "سجل الدروس ($studentName)",
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 10),
                pw.Container(
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    borderRadius: pw.BorderRadius.circular(6),
                    color: PdfColors.indigo50,
                    border: pw.Border.all(color: PdfColors.indigo100),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("عدد الدروس: ${lessons.length}",
                          style: pw.TextStyle(font: ttf, fontSize: 12)),
                      pw.Text("إجمالي المبالغ: $totalAmount ر.ق",
                          style: pw.TextStyle(
                              font: ttf,
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),

                ..._buildTablesChunked(rows, headers, ttf),

                pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    "تاريخ الإنشاء: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}",
                    style: pw.TextStyle(
                        font: ttf, fontSize: 9, color: PdfColors.grey700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// ✅ نافذة اختيار الأعمدة مع التفضيلات
  Future<Set<String>?> _showColumnSelectionDialog(
      BuildContext context, {
        required Map<String, String> availableColumns,
        required Set<String> preselected,
      }) async {
    final selected = Set<String>.from(preselected);

    return showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text("اختر الأعمدة"),
          content: StatefulBuilder(
            builder: (ctx, setState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: availableColumns.entries.map((entry) {
                    return CheckboxListTile(
                      title: Text(entry.value),
                      value: selected.contains(entry.key),
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            selected.add(entry.key);
                          } else {
                            selected.remove(entry.key);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              child: const Text("إلغاء"),
              onPressed: () => Navigator.pop(ctx, null),
            ),
            ElevatedButton(
              child: const Text("تصدير"),
              onPressed: () => Navigator.pop(ctx, selected),
            ),
          ],
        );
      },
    );
  }

  /// ✅ تقسيم البيانات: أول صفحة 23 صف، باقي الصفحات 25 صف
  List<pw.Widget> _buildTablesChunked(
      List<List<String>> rows,
      List<String> headers,
      pw.Font ttf,
      ) {
    const firstPageRows = 23;
    const otherPagesRows = 25;
    List<pw.Widget> tables = [];

    int i = 0;
    bool isFirst = true;

    while (i < rows.length) {
      final rowsPerPage = isFirst ? firstPageRows : otherPagesRows;
      final chunk = rows.sublist(
        i,
        i + rowsPerPage > rows.length ? rows.length : i + rowsPerPage,
      );

      tables.add(
        pw.Table.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
          headerStyle: pw.TextStyle(
              font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 11),
          cellStyle: pw.TextStyle(font: ttf, fontSize: 10),
          cellAlignment: pw.Alignment.centerRight,
          headers: headers,
          data: chunk,
        ),
      );

      tables.add(pw.SizedBox(height: 10));

      i += rowsPerPage;
      isFirst = false;
    }

    return tables;
  }

  /// ✅ مجلد الحفظ حسب النظام
  Future<Directory> _bestOutputDirectory() async {
    if (kIsWeb) {
      return await getTemporaryDirectory();
    }

    try {
      if (Platform.isAndroid || Platform.isWindows || Platform.isLinux) {
        final downloads = Directory("/storage/emulated/0/Download");
        if (await downloads.exists()) return downloads;
      }

      if (Platform.isMacOS) {
        final downloads =
        Directory("${Platform.environment['HOME']}/Downloads");
        if (await downloads.exists()) return downloads;
      }

      if (Platform.isIOS) {
        return await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      return await getTemporaryDirectory();
    }

    return await getTemporaryDirectory();
  }

  /// ✅ تنسيق الوقت
  String _formatTime(dynamic isoString) {
    if (isoString == null || isoString.toString().isEmpty) return "--:--";
    try {
      final dt = DateTime.parse(isoString.toString());
      return DateFormat('HH:mm').format(dt);
    } catch (_) {
      return "--:--";
    }
  }

  /// ✅ تنسيق المدة
  String _formatDuration(dynamic duration) {
    if (duration == null) return "--:--:--";
    final totalSeconds = int.tryParse(duration.toString()) ?? 0;
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  /// ✅ ترجمة الحالة
  String _statusLabel(String status) {
    switch (status) {
      case "scheduled":
        return "مجدولة";
      case "started":
        return "جارية";
      case "ended":
        return "منتهية";
      case "canceled":
        return "ملغاة";
      case "pending":
        return "بانتظار";
      default:
        return "غير معروف";
    }
  }
}
