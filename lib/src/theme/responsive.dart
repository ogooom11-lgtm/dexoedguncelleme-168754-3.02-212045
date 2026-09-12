import 'package:flutter/material.dart';

/// أدوات بسيطة لجعل كل الشاشات متوافقة مع الهواتف والأجهزة اللوحية.
class Responsive {
  Responsive._();

  static const double phoneMax = 600;
  static const double tabletMax = 1000;

  static double width(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isPhone(BuildContext context) => width(context) < phoneMax;
  static bool isTablet(BuildContext context) =>
      width(context) >= phoneMax && width(context) < tabletMax;
  static bool isDesktop(BuildContext context) => width(context) >= tabletMax;

  /// هامش أفقي مناسب لحجم الشاشة (هواتف صغيرة → 12، شاشات كبيرة → 24).
  static double gutter(BuildContext context) {
    final w = width(context);
    if (w < 360) return 12;
    if (w < phoneMax) return 16;
    return 24;
  }

  static EdgeInsets pagePadding(BuildContext context) => EdgeInsets.symmetric(
        horizontal: gutter(context),
        vertical: 16,
      );

  /// عدد الأعمدة المناسب للشبكات.
  static int gridColumns(BuildContext context, {double itemWidth = 190}) {
    final available = width(context) - gutter(context) * 2;
    return (available / itemWidth).floor().clamp(1, 4);
  }

  /// أقصى عرض للمحتوى حتى لا يتمدّد على الشاشات الكبيرة.
  static double maxContentWidth(BuildContext context) =>
      isPhone(context) ? double.infinity : 620;

  /// حجم خط متجاوب مع عرض الشاشة.
  static double scaleText(BuildContext context, double size) {
    final w = width(context);
    if (w < 340) return size * 0.88;
    if (w < 400) return size * 0.95;
    return size;
  }
}

/// يوسّط المحتوى ويحدّ عرضه على الشاشات الكبيرة (مع بقاء تجربة الهاتف كما هي).
class AdaptiveBody extends StatelessWidget {
  const AdaptiveBody({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? Responsive.maxContentWidth(context),
          ),
          child: Padding(
            padding: padding ?? Responsive.pagePadding(context),
            child: child,
          ),
        ),
      ),
    );
  }
}
