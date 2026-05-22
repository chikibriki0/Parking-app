import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Стиль уведомления-диалога.
enum ResultDialogKind { success, info, warning, error }

extension on ResultDialogKind {
  Color get color {
    switch (this) {
      case ResultDialogKind.success:
        return AppTheme.success;
      case ResultDialogKind.info:
        return AppTheme.primary;
      case ResultDialogKind.warning:
        return AppTheme.warning;
      case ResultDialogKind.error:
        return AppTheme.danger;
    }
  }

  IconData get icon {
    switch (this) {
      case ResultDialogKind.success:
        return Icons.check_rounded;
      case ResultDialogKind.info:
        return Icons.info_outline_rounded;
      case ResultDialogKind.warning:
        return Icons.schedule_rounded;
      case ResultDialogKind.error:
        return Icons.close_rounded;
    }
  }
}

/// Диалог-уведомление в стиле «Парковка забронирована!»: круглая иконка
/// с цветной заливкой, заголовок, описание, одна (или две) кнопки.
///
/// Используется вместо snackbar, чтобы не перекрывать нижнюю action-панель.
Future<String?> showResultDialog(
  BuildContext context, {
  required ResultDialogKind kind,
  required String title,
  required String message,
  String primaryLabel = 'OK',
  String? secondaryLabel,
  bool barrierDismissible = true,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Theme.of(ctx).colorScheme.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: kind.color.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(kind.icon, color: kind.color, size: 32),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: kind.color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, 'primary'),
                      child: Text(primaryLabel),
                    ),
                  ),
                  if (secondaryLabel != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kind.color.withOpacity(0.12),
                          foregroundColor: kind.color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx, 'secondary'),
                        child: Text(secondaryLabel),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 14,
              right: 14,
              child: _CloseButton(onTap: () => Navigator.pop(ctx, null)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.close_rounded,
            size: 18,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
