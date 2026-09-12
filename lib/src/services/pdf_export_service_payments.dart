import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

class PdfExportServicePayments {
  final Map<String, String> students;
  final String? selectedStudentId;

  PdfExportServicePayments({
    required this.students,
    required this.selectedStudentId,
  });

  Future<void> exportPaymentsPdf(
      List<Map<String, dynamic>> payments, {
        required Function(String message) onSuccess,
        required Function(String message) onError,
      }) async {
    if (payments.isEmpty) {
      onError("لا توجد نتائج مطابقة للفلترة");
      return;
    }

    try {
      final bytes = await _buildPdfBytes(payments);
      final fileName =
          "payments_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf";

      await Printing.sharePdf(bytes: bytes, filename: fileName);

      try {
        final dir = await _bestOutputDirectory();
        final file = File("${dir.path}/$fileName");
        await file.writeAsBytes(bytes, flush: true);
        onSuccess("تم حفظ الملف في ${file.path}");
      } catch (e) {
        if (!kIsWeb) {
          onError("فشل الحفظ المحلي: $e");
        }
      }
    } catch (e) {
      onError("فشل التصدير $e");
    }
  }

  Future<Uint8List> _buildPdfBytes(List<Map<String, dynamic>> payments) async {
    final fontData =
    await rootBundle.load('project_root/assets/fonts/cairo-regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    // حساب الإجماليات
    num teacherTotal = 0;
    num studentTotal = 0;

    for (var p in payments) {
      final amount = num.tryParse(p['amount'].toString()) ?? 0;
      if ((p['payer']?.toString() ?? "student") == "teacher") {
        teacherTotal += amount;
      } else {
        studentTotal += amount;
      }
    }

    // المجموع النهائي (طالب موجب + معلم سالب)
    final totalAmount = studentTotal - teacherTotal;

    String studentName = "جميع الطلاب";
    if (selectedStudentId != null && students.containsKey(selectedStudentId)) {
      studentName = students[selectedStudentId]!;
    }

    final pdf = pw.Document();

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
                // ==================== الهيدر (كما كان) ====================
                pw.Text("سجل المدفوعات",
                    style: pw.TextStyle(
                        font: ttf,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center),
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
                      pw.Text("عدد المدفوعات: ${payments.length}",
                          style: pw.TextStyle(font: ttf, fontSize: 12)),
                      pw.Row(children: [
                        pw.Text("إجمالي الطالب: ",
                            style: pw.TextStyle(font: ttf, fontSize: 12)),
                        pw.Text("+$studentTotal ر.ق",
                            style: pw.TextStyle(
                                font: ttf,
                                fontSize: 12,
                                color: PdfColors.green)),
                      ]),
                      pw.Row(children: [
                        pw.Text("إجمالي المعلم: ",
                            style: pw.TextStyle(font: ttf, fontSize: 12)),
                        pw.Text("-$teacherTotal ر.ق",
                            style: pw.TextStyle(
                                font: ttf,
                                fontSize: 12,
                                color: PdfColors.red)),
                      ]),
                    ],
                  ),
                ),

                pw.SizedBox(height: 10),

                /// ==================== الجداول ====================
                ..._buildTablesChunked(
                  payments.map((p) {
                    final student = students[p['studentCode']] ?? "طالب";
                    final date =
                    DateTime.tryParse(p['date']?.toString() ?? "");
                    final formattedDate = date != null
                        ? DateFormat("yyyy-MM-dd HH:mm").format(date)
                        : "";
                    final payerStr =
                    (p['payer']?.toString() ?? 'student') == 'teacher'
                        ? "المعلم"
                        : "الطالب";

                    // طريقة الدفع بالعربي
                    final methodRaw = (p['method'] ?? "").toString().toLowerCase();
                    String method;
                    if (methodRaw == "cash") {
                      method = "كاش";
                    } else if (methodRaw == "bank") {
                      method = "بنك";
                    } else {
                      method = "غير محدد";
                    }

                    // المبلغ مع إشارة + أو -
                    final amount = num.tryParse(p['amount'].toString()) ?? 0;
                    final isTeacher =
                        (p['payer']?.toString() ?? "student") == "teacher";
                    final displayAmount =
                    isTeacher ? "-$amount ر.ق" : "+$amount ر.ق";

                    return [
                      displayAmount,
                      method,
                      payerStr,
                      formattedDate,
                      student,
                    ];
                  }).toList(),
                  ["المبلغ", "طريقة الدفع", "الدافع", "التاريخ", "الطالب"],
                  ttf,
                ),

                pw.SizedBox(height: 12),

                // ==================== المجموع النهائي خارج الفقاعة ====================
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    "المجموع النهائي: $totalAmount ر.ق",
                    style: pw.TextStyle(
                        font: ttf,
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: totalAmount >= 0
                            ? PdfColors.green
                            : PdfColors.red),
                  ),
                ),

                pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    "تاريخ الإنشاء ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}",
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

  /// تقسيم البيانات: أول صفحة 23 صف، باقي الصفحات 25 صف
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

      // حضّر البيانات مع تلوين المبالغ
      final styledData = chunk.map((row) {
        final amountText = row[0];
        pw.Widget amountWidget;

        if (amountText.startsWith("-")) {
          amountWidget = pw.Text(amountText,
              style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColors.red));
        } else if (amountText.startsWith("+")) {
          amountWidget = pw.Text(amountText,
              style: pw.TextStyle(font: ttf, fontSize: 10, color: PdfColors.green));
        } else {
          amountWidget = pw.Text(amountText,
              style: pw.TextStyle(font: ttf, fontSize: 10));
        }

        return [
          amountWidget,
          pw.Text(row[1], style: pw.TextStyle(font: ttf, fontSize: 10)),
          pw.Text(row[2], style: pw.TextStyle(font: ttf, fontSize: 10)),
          pw.Text(row[3], style: pw.TextStyle(font: ttf, fontSize: 10)),
          pw.Text(row[4], style: pw.TextStyle(font: ttf, fontSize: 10)),
        ];
      }).toList();

      tables.add(
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo50),
          headerStyle: pw.TextStyle(
              font: ttf, fontWeight: pw.FontWeight.bold, fontSize: 11),
          headers: headers,
          cellAlignment: pw.Alignment.centerRight,
          data: styledData,
        ),
      );

      tables.add(pw.SizedBox(height: 10));

      i += rowsPerPage;
      isFirst = false;
    }

    return tables;
  }

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
}
