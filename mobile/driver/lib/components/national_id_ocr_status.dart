import 'package:driver/data/national_id_ocr.dart';
import 'package:flutter/material.dart';

class NationalIdOcrStatus extends StatelessWidget {
  const NationalIdOcrStatus({
    super.key,
    required this.isReading,
    required this.recognizedId,
    required this.enteredId,
    required this.error,
  });

  final bool isReading;
  final String? recognizedId;
  final String enteredId;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (isReading) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Expanded(child: Text('جاري قراءة الرقم القومي من الصورة...')),
          ],
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(error!, style: TextStyle(color: Colors.red.shade700)),
      );
    }

    if (recognizedId == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Text('ارفع صورة الوجه الأمامي للبطاقة للتحقق من الرقم القومي.'),
      );
    }

    final matches = NationalIdOcrService.matches(enteredId, recognizedId!);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الرقم المستخرج من الصورة:',
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              recognizedId!,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            enteredId.trim().isEmpty
                ? 'اكتب الرقم يدويًا للمقارنة.'
                : matches
                ? 'الرقم المكتوب مطابق للصورة.'
                : 'الرقم المكتوب لا يطابق الصورة. صححه قبل المتابعة.',
            style: TextStyle(
              color: matches ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
