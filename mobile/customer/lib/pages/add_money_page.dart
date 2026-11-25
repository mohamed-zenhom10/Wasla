import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:main/components/app_page_header.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/services/wallet_service.dart';
import 'package:main/theme/app_theme.dart';

class AddMoneyPage extends StatefulWidget {
  const AddMoneyPage({super.key, this.onSubmitted});

  final VoidCallback? onSubmitted;

  @override
  State<AddMoneyPage> createState() => _AddMoneyPageState();
}

class _AddMoneyPageState extends State<AddMoneyPage> {
  final _service = WalletService();
  final _catalogService = ShipmentService();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _picker = ImagePicker();

  bool _isLoadingCatalog = true;
  String? _error;
  String? _instapayHandle;
  double? _minAmount;
  double? _maxAmount;
  Uint8List? _receiptBytes;
  String? _receiptContentType;
  bool _isSubmitting = false;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() => _isLoadingCatalog = true);
    try {
      final catalog = await _catalogService.getCatalog();
      if (!mounted) return;
      final min = catalog.minTopupAmount;
      final max = catalog.maxTopupAmount;
      final handle = catalog.companyInstapayHandle;
      if (min == null || max == null || handle == null || handle.trim().isEmpty) {
        setState(() => _error = 'Top-up configuration is unavailable.');
      } else {
        setState(() {
          _instapayHandle = handle;
          _minAmount = min;
          _maxAmount = max;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isLoadingCatalog = false);
    }
  }

  Future<void> _pickReceipt(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      setState(() => _error = 'Receipt image must be 5 MB or smaller.');
      return;
    }
    final name = file.name.toLowerCase();
    String contentType = 'image/jpeg';
    if (name.endsWith('.png')) contentType = 'image/png';
    if (name.endsWith('.webp')) contentType = 'image/webp';
    if (contentType == 'image/jpeg' && !name.endsWith('.jpg') && !name.endsWith('.jpeg')) {
      // Fall back to mime type from picker when extension is unavailable.
      contentType = file.mimeType ?? contentType;
    }
    if (!['image/jpeg', 'image/png', 'image/webp'].contains(contentType)) {
      setState(() => _error = 'Only JPEG, PNG, or WebP receipts are supported.');
      return;
    }
    setState(() {
      _receiptBytes = bytes;
      _receiptContentType = contentType;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (_minAmount == null || _maxAmount == null) {
      setState(() => _error = 'Top-up limits are unavailable.');
      return;
    }
    if (amount == null || amount < _minAmount! || amount > _maxAmount!) {
      setState(() => _error = 'Enter an amount between $_minAmount and $_maxAmount.');
      return;
    }
    if (_receiptBytes == null || _receiptContentType == null) {
      setState(() => _error = 'Upload a receipt image.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
      _successMessage = null;
    });
    try {
      final topup = await _service.createTopup(
        amount: amount.toStringAsFixed(2),
        reference: _referenceController.text,
        bytes: _receiptBytes!,
        contentType: _receiptContentType!,
      );
      if (!mounted) return;
      setState(() {
        _successMessage = 'Top-up request submitted. Status: ${topup.status}.';
        _receiptBytes = null;
      });
      widget.onSubmitted?.call();
    } catch (error) {
      if (mounted) setState(() => _error = WalletService.readableError(error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        children: [
          const AppPageHeader(title: 'Add money'),
          const SizedBox(height: 18),
          if (_isLoadingCatalog)
            const Center(child: CircularProgressIndicator())
          else ...[
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: AppColors.accent)),
              const SizedBox(height: 12),
            ],
            if (_successMessage != null) ...[
              Text(_successMessage!, style: const TextStyle(color: AppColors.darkGreen)),
              const SizedBox(height: 12),
            ],
            Text('InstaPay handle: ${_instapayHandle ?? 'Not available'}', style: AppTypography.bodyMd),
            const SizedBox(height: 8),
            Text(
              'Transfer the money using InstaPay, then upload the receipt. Your balance will increase after verification.',
              style: AppTypography.bodySm,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(labelText: 'Transaction reference (optional)'),
            ),
            const SizedBox(height: 12),
            if (_receiptBytes != null)
              Image.memory(_receiptBytes!, height: 180, fit: BoxFit.cover),
            Row(
              children: [
                TextButton(
                  onPressed: () => _pickReceipt(ImageSource.camera),
                  child: const Text('Camera'),
                ),
                TextButton(
                  onPressed: () => _pickReceipt(ImageSource.gallery),
                  child: const Text('Gallery'),
                ),
                if (_receiptBytes != null)
                  TextButton(
                    onPressed: () => setState(() => _receiptBytes = null),
                    child: const Text('Remove'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: Text(_isSubmitting ? 'Submitting...' : 'Submit top-up'),
              ),
          ],
        ],
      ),
    ),
  );
}
}
