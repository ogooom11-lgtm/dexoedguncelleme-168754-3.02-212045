import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/role.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';

/// صفحة تسجيل الدخول — تصميم جديد ومتجاوب بالكامل مع الهواتف.
/// ✅ لا يوجد تحقق بريد إلكتروني.
/// ✅ لا يتم تحليل الدروس أو إنشاء أي تنبيهات أثناء الدخول (دخول سريع).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  static const int codeLength = 8;

  final TextEditingController _codeController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _error = '';
  bool _loading = false;

  late final AnimationController _anim;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _anim.forward();
      if (mounted) FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _focusNode.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _tryLogin() async {
    if (_loading) return;
    final code = _codeController.text.trim();

    if (code.length != codeLength || !RegExp(r'^[0-9]+$').hasMatch(code)) {
      setState(() => _error = 'الرجاء إدخال كود صحيح مكوّن من 8 أرقام');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _error = '';
      _loading = true;
    });

    try {
      // ⚡ الدخول = قراءة سجل واحد فقط. لا تحليل دروس ولا جدولة تنبيهات.
      final auth = context.read<AuthProvider>();
      final user = await auth.signInWithCode(code);
      auth.watchDisabled();
      if (!mounted) return;

      final route = switch (user.role) {
        UserRole.admin => '/admin',
        UserRole.teacher => '/teacher',
        UserRole.student => '/student',
      };
      Navigator.pushNamedAndRemoveUntil(context, route, (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _codeController.clear();
      });
      HapticFeedback.mediumImpact();
      FocusScope.of(context).requestFocus(_focusNode);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onCodeChanged(String value) {
    setState(() => _error = '');
    if (value.length == codeLength) {
      _tryLogin();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final compact = MediaQuery.sizeOf(context).height < 700;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.heroGradient(context)),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: Responsive.gutter(context),
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: FadeTransition(
                        opacity: _fade,
                        child: SlideTransition(
                          position: _slide,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _logo(compact),
                              SizedBox(height: compact ? 16 : 28),
                              _card(theme, cs, compact),
                              const SizedBox(height: 18),
                              Text(
                                'كودك الخاص يصلك من المعلم أو المدير',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _logo(bool compact) {
    final size = compact ? 76.0 : 96.0;
    return Column(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(size / 3),
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Icon(Icons.school_rounded,
              size: size * 0.52, color: Colors.white),
        ),
        SizedBox(height: compact ? 10 : 16),
        const Text(
          'دروس خاص',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'إدارة الطلاب والدروس والمدفوعات',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _card(ThemeData theme, ColorScheme cs, bool compact) {
    return Container(
      padding: EdgeInsets.all(compact ? 16 : 22),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? cs.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'تسجيل الدخول',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'أدخل الكود المكوّن من 8 أرقام',
            style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
          ),
          const SizedBox(height: 18),
          _CodeField(
            controller: _codeController,
            focusNode: _focusNode,
            length: codeLength,
            enabled: !_loading,
            hasError: _error.isNotEmpty,
            onChanged: _onCodeChanged,
            onSubmitted: (_) => _tryLogin(),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _error.isEmpty
                ? const SizedBox(height: 14)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusSm),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: cs.onErrorContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error,
                              style: TextStyle(
                                color: cs.onErrorContainer,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loading ? null : _tryLogin,
            icon: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(_loading ? 'جارٍ الدخول...' : 'دخول'),
          ),
        ],
      ),
    );
  }
}

/// حقل إدخال الكود على شكل مربّعات — متجاوب مع عرض الشاشة.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.focusNode,
    required this.length,
    required this.onChanged,
    required this.onSubmitted,
    this.enabled = true,
    this.hasError = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int length;
  final bool enabled;
  final bool hasError;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            const gap = 6.0;
            final boxWidth =
                ((constraints.maxWidth - gap * (length - 1)) / length)
                    .clamp(26.0, 48.0);
            final boxHeight = boxWidth * 1.32;
            final code = controller.text;

            return Stack(
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(length, (i) {
                      final filled = i < code.length;
                      final focused = i == code.length && focusNode.hasFocus;

                      return Padding(
                        padding:
                            EdgeInsets.only(right: i == length - 1 ? 0 : gap),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: boxWidth,
                          height: boxHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: filled
                                ? cs.primary.withValues(alpha: 0.10)
                                : cs.surfaceContainerHighest
                                    .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: hasError
                                  ? cs.error
                                  : focused
                                      ? cs.primary
                                      : cs.outlineVariant,
                              width: focused || hasError ? 1.8 : 1,
                            ),
                          ),
                          child: Text(
                            filled ? code[i] : '',
                            style: TextStyle(
                              fontSize: boxWidth * 0.5,
                              fontWeight: FontWeight.w800,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // الحقل الحقيقي شفاف فوق المربعات لالتقاط الإدخال
                Positioned.fill(
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: length,
                      showCursor: false,
                      style: const TextStyle(fontSize: 1),
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        filled: false,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(length),
                      ],
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
