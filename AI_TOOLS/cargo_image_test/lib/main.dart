import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'image_compression_stub.dart'
    if (dart.library.html) 'image_compression_web.dart' as image_compression;

const _geminiModel = 'gemini-3.5-flash-lite';
const _geminiRequestTimeout = Duration(seconds: 90);

void main() {
  runApp(const CargoImageApp());
}

class CargoImageApp extends StatelessWidget {
  const CargoImageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cargo AI Analyzer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AnalyzerPage(),
    );
  }
}

class AnalyzerPage extends StatefulWidget {
  const AnalyzerPage({super.key});

  @override
  State<AnalyzerPage> createState() => _AnalyzerPageState();
}

class _AnalyzerPageState extends State<AnalyzerPage> {
  static const vehicleTypes = ['ربع نقل', 'نص نقل', 'نقل', 'تريلله', 'شاحنه'];

  final apiKeyController = TextEditingController();

  Uint8List? imageBytes;
  Uint8List? uploadImageBytes;
  String? imageName;
  String? mimeType;

  List<Map<String, dynamic>> products = [];
  String? errorMessage;

  bool loading = false;
  bool preparingImage = false;
  int? savingProductIndex;
  final Set<int> visibleDisassembly = {};

  // Choose ONE image from Edge, Android, or iPhone.
  // The selected image may contain multiple cargo items.
  Future<void> selectImage() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.image);

      if (files.isEmpty) return;

      setState(() {
        preparingImage = true;
        errorMessage = null;
      });

      final file = files.first;
      final extension = file.extension?.toLowerCase();

      const supportedTypes = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
      };

      if (extension == null || !supportedTypes.containsKey(extension)) {
        setState(() {
          errorMessage =
              'الصيغ المدعومة هي JPG وPNG وWEBP. '
              'حوّل الصورة لصيغة مدعومة وجرب تاني.';
        });
        return;
      }

      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        setState(() {
          errorMessage = 'الصورة فاضية أو تعذّر قراءتها.';
        });
        return;
      }

      final compressedBytes = await image_compression.prepareImageForUpload(
        bytes,
      );

      if (!mounted) return;

      setState(() {
        imageBytes = compressedBytes;
        uploadImageBytes = compressedBytes;
        imageName = file.name;
        mimeType = 'image/jpeg';
        products = [];
        visibleDisassembly.clear();
        errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'حصل خطأ أثناء اختيار الصورة: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          preparingImage = false;
        });
      }
    }
  }

  Future<void> analyzeImage() async {
    final apiKey = apiKeyController.text.trim();

    if (apiKey.isEmpty) {
      setState(() {
        errorMessage = 'اكتب Gemini API Key الأول.';
      });
      return;
    }

    if (uploadImageBytes == null || mimeType == null) {
      setState(() {
        errorMessage = 'اختار صورة الشحنة الأول.';
      });
      return;
    }

    setState(() {
      loading = true;
      products = [];
      visibleDisassembly.clear();
      errorMessage = null;
    });

    try {
      final prompt =
          '''
حلل صورة الشحنة المرفقة واكتشف كل عناصر الشحن الظاهرة فيها.

مهم جداً:
- الصورة الواحدة قد تحتوي على عنصر واحد أو عنصرين أو عدد كبير من العناصر.
- افحص الصورة كاملة وحاول تحديد كل عنصر مميز يمكن شحنه بشكل منفصل.
- لا تدمج عدة عناصر مختلفة في عنصر واحد.
- إذا ظهرت 3 كراتين منفصلة ومتطابقة، يمكنك تسجيلها كعنصر واحد مع توضيح العدد 3 في item_name أو quantity.
- إذا كانت العناصر مختلفة، أنشئ سجلاً منفصلاً لكل عنصر.
- لا تكرر نفس العنصر أكثر من مرة بدون داعٍ.
- لا تخترع عناصر غير ظاهرة في الصورة.
- اكتب النتائج باللغة العربية.
- قدّر طول وعرض وارتفاع كل عنصر بالسنتيمتر.
- قدّر أقل وأعلى وزن محتمل لكل عنصر بالكيلوجرام.
- اختر نوع مركبة واحداً فقط من هذه القائمة: ${vehicleTypes.join('، ')}.
- حدّد الخامة المرجحة لكل عنصر.
- قدّر لكل عنصر هل يمكن تفكيكه عملياً، واشرح السبب باختصار.
- إذا كان قابلاً للتفكيك، قدّر أبعاد أصغر جزء/حزمة بعد التفكيك بالسنتيمتر.
- كن متحفظاً؛ لا تفترض إمكانية التفكيك إذا لم تدعمها الصورة.
- إذا تعذّر تقدير بُعد بعد التفكيك، استخدم null.
- confidence رقم من 0 إلى 1.
- الأبعاد والأوزان تقديرات بصرية وليست قياسات مؤكدة.
- إذا لم تستطع تقدير قيمة رقمية، استخدم null.
- أرجع JSON فقط حسب المخطط المطلوب، دون Markdown.
''';

      final decoded = await _requestGeminiJson(
        apiKey: apiKey,
        prompt: prompt,
        responseSchema: {
          'type': 'OBJECT',
          'properties': {
            'products': {
              'type': 'ARRAY',
              'description': 'قائمة بكل عناصر الشحن المكتشفة في الصورة',
              'items': {
                'type': 'OBJECT',
                'properties': {
                  'item_name': {
                    'type': 'STRING',
                    'description':
                        'اسم العنصر باللغة العربية، مع العدد إذا لزم',
                  },
                  'quantity': {
                    'type': 'INTEGER',
                    'description': 'عدد القطع المتشابهة التي تمثلها النتيجة',
                  },
                  'suitable_vehicle_type': {
                    'type': 'STRING',
                    'enum': vehicleTypes,
                    'description':
                        'نوع مركبة النقل المناسبة من الخيارات المحددة',
                  },
                  'dimensions_cm': {
                    'type': 'OBJECT',
                    'properties': {
                      'length': {'type': 'NUMBER', 'nullable': true},
                      'width': {'type': 'NUMBER', 'nullable': true},
                      'height': {'type': 'NUMBER', 'nullable': true},
                    },
                    'required': ['length', 'width', 'height'],
                  },
                  'estimated_weight_kg': {
                    'type': 'OBJECT',
                    'properties': {
                      'min': {'type': 'NUMBER', 'nullable': true},
                      'max': {'type': 'NUMBER', 'nullable': true},
                    },
                    'required': ['min', 'max'],
                  },
                  'material': {
                    'type': 'STRING',
                    'description': 'الخامة المرجحة',
                  },
                  'confidence': {
                    'type': 'NUMBER',
                    'description': 'الثقة من صفر إلى واحد',
                  },
                  'disassembly_assessment': {
                    'type': 'OBJECT',
                    'properties': {
                      'is_disassemblable': {'type': 'BOOLEAN'},
                      'reason': {
                        'type': 'STRING',
                        'description': 'سبب تقدير قابلية التفكيك',
                      },
                      'dimensions_after_disassembly_cm': {
                        'type': 'OBJECT',
                        'properties': {
                          'length': {'type': 'NUMBER', 'nullable': true},
                          'width': {'type': 'NUMBER', 'nullable': true},
                          'height': {'type': 'NUMBER', 'nullable': true},
                        },
                        'required': ['length', 'width', 'height'],
                      },
                    },
                    'required': [
                      'is_disassemblable',
                      'reason',
                      'dimensions_after_disassembly_cm',
                    ],
                  },
                },
                'required': [
                  'item_name',
                  'quantity',
                  'suitable_vehicle_type',
                  'dimensions_cm',
                  'estimated_weight_kg',
                  'material',
                  'confidence',
                  'disassembly_assessment',
                ],
              },
            },
          },
          'required': ['products'],
        },
      );

      if (decoded['products'] is! List) {
        throw Exception('شكل JSON غير متوقع. جرّب تحليل الصورة مرة أخرى.');
      }

      final detectedProducts = (decoded['products'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

      if (detectedProducts.isEmpty) {
        throw Exception(
          'لم يتم اكتشاف عناصر واضحة. جرّب صورة أوضح '
          'وبإضاءة أفضل.',
        );
      }

      if (!mounted) return;

      setState(() {
        products = detectedProducts;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        errorMessage =
            'استغرق تحليل الصورة وقتاً أطول من المتوقع. '
            'تحقق من اتصال الإنترنت وحاول مرة أخرى.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _requestGeminiJson({
    required String apiKey,
    required String prompt,
    required Map<String, dynamic> responseSchema,
  }) async {
    final bytes = uploadImageBytes;
    final imageMimeType = mimeType;
    if (bytes == null || imageMimeType == null) {
      throw Exception('اختار صورة الشحنة الأول.');
    }

    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$_geminiModel:generateContent',
      {'key': apiKey},
    );
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': imageMimeType,
                'data': base64Encode(bytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 8192,
        'responseMimeType': 'application/json',
        'responseSchema': responseSchema,
      },
    };

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_geminiRequestTimeout);

    dynamic responseData;
    try {
      responseData = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'ردّ الخادم مش بصيغة JSON صحيحة. '
        'راجع إعدادات الاتصال وحاول تاني.',
      );
    }

    if (response.statusCode != 200) {
      var message = response.body;
      if (responseData is Map) {
        final apiError = responseData['error'];
        if (apiError is Map && apiError['message'] is String) {
          message = apiError['message'] as String;
        }
      }
      throw Exception('Gemini API: $message');
    }

    if (responseData is! Map ||
        responseData['candidates'] is! List ||
        (responseData['candidates'] as List).isEmpty) {
      throw Exception('الذكاء الاصطناعي لم يرجع نتيجة. حاول بصورة أوضح.');
    }

    final candidate = (responseData['candidates'] as List).first;
    if (candidate is! Map) {
      throw Exception('الرد لا يحتوي على بيانات التحليل.');
    }
    final content = candidate['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is! List) {
      throw Exception('الرد لا يحتوي على بيانات التحليل.');
    }

    final generatedText = parts
        .whereType<Map>()
        .map((part) => part['text']?.toString() ?? '')
        .join();
    final decoded = jsonDecode(generatedText);
    if (decoded is! Map) {
      throw Exception('شكل JSON غير متوقع من الذكاء الاصطناعي.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  void checkDisassembly(int index) {
    setState(() {
      if (!visibleDisassembly.add(index)) {
        visibleDisassembly.remove(index);
      }
    });
  }

  String formatJson(Map<String, dynamic> product) {
    return const JsonEncoder.withIndent('  ').convert(product);
  }

  Future<void> copyProduct(int index) async {
    await Clipboard.setData(ClipboardData(text: formatJson(products[index])));

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ بيانات العنصر ${index + 1}')),
    );
  }

  Future<void> downloadProduct(int index) async {
    setState(() {
      savingProductIndex = index;
    });

    try {
      final bytes = Uint8List.fromList(
        utf8.encode(formatJson(products[index])),
      );

      await FileSaver.instance.saveFile(
        name: 'cargo_item_${index + 1}',
        bytes: bytes,
        fileExtension: 'json',
        mimeType: MimeType.json,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تجهيز ملف العنصر ${index + 1}')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر حفظ الملف: $e')));
    } finally {
      if (mounted) {
        setState(() {
          savingProductIndex = null;
        });
      }
    }
  }

  Widget buildProductCard(
    BuildContext context,
    Map<String, dynamic> product,
    int index,
  ) {
    final dimensions = product['dimensions_cm'] as Map? ?? {};
    final weight = product['estimated_weight_kg'] as Map? ?? {};
    final disassembly =
        product['disassembly_assessment'] as Map<String, dynamic>?;
    final disassemblyDimensions =
        disassembly?['dimensions_after_disassembly_cm'] as Map? ?? {};

    final json = formatJson(product);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(child: Text('${index + 1}')),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    product['item_name']?.toString() ?? 'عنصر بدون اسم',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _infoRow('العدد', product['quantity']?.toString() ?? 'غير محدد'),
            _infoRow(
              'مركبة النقل',
              product['suitable_vehicle_type']?.toString() ?? 'غير محدد',
            ),
            _infoRow(
              'الأبعاد (سم)',
              'طول: ${dimensions['length'] ?? 'غير محدد'}، '
                  'عرض: ${dimensions['width'] ?? 'غير محدد'}، '
                  'ارتفاع: ${dimensions['height'] ?? 'غير محدد'}',
            ),
            _infoRow(
              'الوزن (كجم)',
              '${weight['min'] ?? 'غير محدد'} - '
                  '${weight['max'] ?? 'غير محدد'}',
            ),
            _infoRow('الخامة', product['material']?.toString() ?? 'غير محدد'),
            _infoRow(
              'مستوى الثقة',
              product['confidence']?.toString() ?? 'غير محدد',
            ),
            if (disassembly != null && visibleDisassembly.contains(index)) ...[
              const Divider(height: 24),
              Text(
                'نتيجة فحص التفكيك',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              _infoRow(
                'قابل للتفكيك',
                disassembly['is_disassemblable'] == true ? 'نعم' : 'لا',
              ),
              _infoRow(
                'السبب',
                disassembly['reason']?.toString() ?? 'غير محدد',
              ),
              if (disassembly['is_disassemblable'] == true)
                _infoRow(
                  'الأبعاد بعد التفكيك (سم)',
                  'طول: ${disassemblyDimensions['length'] ?? 'غير محدد'}، '
                      'عرض: ${disassemblyDimensions['width'] ?? 'غير محدد'}، '
                      'ارتفاع: ${disassemblyDimensions['height'] ?? 'غير محدد'}',
                ),
              const Text(
                'الأبعاد بعد التفكيك تقديرية وقد تختلف عن الواقع.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: disassembly == null
                  ? null
                  : () => checkDisassembly(index),
              icon: const Icon(Icons.build_outlined),
              label: Text(
                visibleDisassembly.contains(index)
                    ? 'إخفاء فحص التفكيك'
                    : 'هل يمكن تفكيكه؟',
              ),
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('عرض JSON'),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    json,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => copyProduct(index),
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ JSON'),
                ),
                FilledButton.tonalIcon(
                  onPressed: savingProductIndex == index
                      ? null
                      : () => downloadProduct(index),
                  icon: savingProductIndex == index
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: const Text('تحميل JSON'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تحليل الشحنات بالذكاء الاصطناعي'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'حلّل صورة واحدة واكتشف كل العناصر الموجودة فيها',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'ارفع صورة تحتوي على عنصر واحد أو عدة عناصر. '
                'سيحاول الذكاء الاصطناعي فصل كل عنصر وعرض '
                'بياناته في بطاقة مستقلة.',
              ),
              const SizedBox(height: 8),
              const Text(
                'سيتم تصغير الصورة لجودة متوسطة وإرسالها مرة واحدة؛ '
                'ويشمل التحليل فحص التفكيك.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: apiKeyController,
                obscureText: true,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Gemini API Key',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: loading || preparingImage ? null : selectImage,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  preparingImage
                      ? 'جاري تجهيز الصورة...'
                      : 'اختيار صورة من الجهاز',
                ),
              ),
              if (imageBytes != null) ...[
                const SizedBox(height: 14),
                Text(
                  'الصورة المختارة: ${imageName ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    imageBytes!,
                    height: 260,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) {
                      return const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('تعذّر عرض معاينة الصورة.'),
                      );
                    },
                  ),
                ),
                TextButton.icon(
                  onPressed: loading || preparingImage
                      ? null
                      : () {
                          setState(() {
                            imageBytes = null;
                            uploadImageBytes = null;
                            imageName = null;
                            mimeType = null;
                            products = [];
                            visibleDisassembly.clear();
                            errorMessage = null;
                          });
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('إزالة الصورة'),
                ),
              ],
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: loading || preparingImage ? null : analyzeImage,
                icon: loading || preparingImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  preparingImage
                      ? 'جاري تجهيز الصورة...'
                      : loading
                      ? 'جاري تحليل الصورة...'
                      : 'حلل الشحنة',
                ),
              ),
              if (loading || preparingImage) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                  'قد يستغرق تجهيز الصورة أو تحليلها بعض الوقت حسب '
                  'حجمها وسرعة الاتصال.',
                  textAlign: TextAlign.center,
                ),
              ],
              if (errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              if (products.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'العناصر المكتشفة: ${products.length}',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...List.generate(
                  products.length,
                  (index) => buildProductCard(context, products[index], index),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ملحوظة: الأبعاد والأوزان تقديرية من الصورة '
                  'وقد تحتاج إلى قياس فعلي قبل الشحن.',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
