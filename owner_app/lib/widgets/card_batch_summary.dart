// lib/widgets/card_batch_summary.dart
import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/card_batch_validator.dart';

/// ملخّص نتيجة التحقق المسبق من دُفعة الكروت.
///
/// يعرض الأعداد وأرقام الأسطر فقط — لا يطبع أي رقم كرت على الشاشة.
class CardBatchValidationSummary extends StatelessWidget {
  final CardBatchValidation validation;

  const CardBatchValidationSummary({super.key, required this.validation});

  @override
  Widget build(BuildContext context) {
    final hasProblems = validation.invalidCount > 0 || validation.exceedsLimit;
    final hasWarnings = hasProblems || validation.duplicateCount > 0;
    final headerColor = hasProblems
        ? AppTheme.error
        : (hasWarnings ? AppTheme.warning : AppTheme.accentDark);

    return Card(
      color: headerColor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ملخّص المعاينة',
              style: TextStyle(fontWeight: FontWeight.bold, color: headerColor),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              icon: Icons.check_circle_outline,
              label: 'كروت صالحة',
              value: '${validation.validCount}',
              color: AppTheme.accentDark,
            ),
            if (validation.duplicateCount > 0)
              _SummaryRow(
                icon: Icons.warning_amber_rounded,
                label: 'مكررة داخل الدفعة (لن تُرفع)',
                value: '${validation.duplicateCount}',
                color: AppTheme.warning,
              ),
            if (validation.invalidCount > 0)
              _SummaryRow(
                icon: Icons.error_outline,
                label: 'غير صالحة (يجب تصحيحها)',
                value: '${validation.invalidCount}',
                color: AppTheme.error,
              ),
            if (validation.emptyLines > 0)
              _SummaryRow(
                icon: Icons.remove_circle_outline,
                label: 'أسطر فارغة',
                value: '${validation.emptyLines}',
                color: AppTheme.textMuted,
              ),
            if (validation.duplicateCount > 0) ...[
              const SizedBox(height: 8),
              _SummaryNote(
                'أسطر مكررة: ${formatLineNumbers(validation.duplicateLines)}',
              ),
            ],
            if (validation.invalidCount > 0) ...[
              const SizedBox(height: 8),
              _SummaryNote(
                'أسطر غير صالحة (أطول من $maxCardPinLength خانة أو فيها '
                'مسافات): ${formatLineNumbers(validation.invalidLines)}',
              ),
            ],
            if (validation.exceedsLimit) ...[
              const SizedBox(height: 8),
              const _SummaryNote(
                'الحد الأقصى للدفعة الواحدة $maxCardBatchSize كرت. '
                'قسّم القائمة على أكثر من دفعة.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// نتيجة الرفع كما أعادها الخادم.
class CardBatchResultCard extends StatelessWidget {
  final CardBatchUploadResult result;

  const CardBatchResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.replayed ? AppTheme.info : AppTheme.accentDark;

    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.replayed ? 'هذه الدفعة سبق رفعها' : 'تم رفع الدفعة',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 8),
            _SummaryRow(
              icon: Icons.check_circle_outline,
              label: 'كروت أُضيفت للمخزون',
              value: '${result.ingestedCount}',
              color: AppTheme.accentDark,
            ),
            _SummaryRow(
              icon: Icons.content_copy_rounded,
              label: 'موجودة مسبقاً (تم تخطيها)',
              value: '${result.duplicatesSkipped}',
              color: result.duplicatesSkipped > 0
                  ? AppTheme.warning
                  : AppTheme.textMuted,
            ),
            if (result.replayed) ...[
              const SizedBox(height: 8),
              const _SummaryNote(
                'لم تُرفع الكروت مرة ثانية؛ هذه نتيجة الرفع الأول.',
              ),
            ],
            if (result.batchId.isNotEmpty) ...[
              const SizedBox(height: 8),
              _SummaryNote('رقم الدفعة: ${result.batchId}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryNote extends StatelessWidget {
  final String text;

  const _SummaryNote(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
    );
  }
}
