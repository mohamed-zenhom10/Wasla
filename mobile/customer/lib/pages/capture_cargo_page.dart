import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:main/components/cargo_components.dart';
import 'package:main/models/shipment.dart';
import 'package:main/pages/ai_estimating_page.dart';
import 'package:main/pages/vehicle_small_page.dart';
import 'package:main/services/cargo_order_service.dart';
import 'package:main/services/shipment_service.dart';
import 'package:main/theme/app_theme.dart';

class CaptureCargoPage extends StatefulWidget {
  const CaptureCargoPage({super.key, required this.draft});

  final CargoOrderDraft draft;

  @override
  State<CaptureCargoPage> createState() => _CaptureCargoPageState();
}

class _CaptureCargoPageState extends State<CaptureCargoPage> {
  final _picker = ImagePicker();
  final _service = ShipmentService();
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _errorField;

  int get _photoCount =>
      (widget.draft.shipment?.photos.length ?? 0) + widget.draft.photos.length;

  Future<void> _capturePhoto({int? replaceIndex}) async {
    if (_photoCount >= 10 && replaceIndex == null) {
      _showError('A shipment can have up to 10 photos.', field: 'photos');
      return;
    }
    try {
      final file = await _picker.pickImage(source: ImageSource.camera);
      if (file == null || !mounted) return;
      final contentType = _contentType(file);
      if (contentType == null) {
        _showError(
          'This image format is not supported. Use JPEG, PNG, or WebP.',
          field: 'photos',
        );
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        _showError('Each photo must be smaller than 5 MB.', field: 'photos');
        return;
      }
      final photo = CargoPhotoDraft(
        bytes: bytes,
        contentType: contentType,
        fileName: file.name,
      );
      setState(() {
        if (replaceIndex == null) {
          widget.draft.photos.add(photo);
        } else {
          widget.draft.photos[replaceIndex] = photo;
        }
        _errorMessage = null;
        _errorField = null;
      });
    } on PlatformException catch (error) {
      final denied = error.code.toLowerCase().contains('permission');
      _showError(
        denied
            ? 'Camera permission was denied. Allow camera access in device settings to take a cargo photo.'
            : 'The camera could not be opened. ${error.message ?? 'Try again.'}',
        field: 'photos',
      );
    } catch (error) {
      _showError('The photo could not be read. $error', field: 'photos');
    }
  }

  String? _contentType(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (const {'image/jpeg', 'image/png', 'image/webp'}.contains(mime)) {
      return mime;
    }
    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return null;
  }

  Future<void> _createAndRequestQuotes() async {
    if (_isSubmitting) return;
    if (widget.draft.stops.isNotEmpty) {
      _showError(
        'The shipment API does not accept additional stops. Remove the extra stops before creating this shipment.',
        field: 'stops',
      );
      return;
    }
    if (widget.draft.photos.isEmpty &&
        (widget.draft.shipment?.photos.isEmpty ?? true)) {
      _showError(
        'Capture at least one cargo photo to continue.',
        field: 'photos',
      );
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _errorField = null;
    });
    try {
      final existingShipment = widget.draft.shipment;
      late Shipment shipment;
      if (existingShipment == null) {
        final catalog = widget.draft.catalog;
        final categoryId = widget.draft.categoryId;
        if (catalog == null || categoryId == null) {
          throw const ShipmentApiException(
            code: 'INVALID_INPUT',
            field: 'cargoCategoryId',
            message: 'Select a cargo category from the catalog.',
          );
        }
        final pickupLatitude = widget.draft.pickupLatitude;
        final pickupLongitude = widget.draft.pickupLongitude;
        final dropoffLatitude = widget.draft.dropoffLatitude;
        final dropoffLongitude = widget.draft.dropoffLongitude;
        if (pickupLatitude == null ||
            pickupLongitude == null ||
            dropoffLatitude == null ||
            dropoffLongitude == null) {
          throw const ShipmentApiException(
            code: 'INVALID_INPUT',
            field: 'pickup',
            message: 'Select pickup and drop-off points on the map.',
          );
        }
        shipment = await _service.createDraft(
          catalog: catalog,
          cargoCategoryId: categoryId,
          sizeOptionId: widget.draft.sizeOptionId,
          cargoDescription: widget.draft.description,
          itemCount: widget.draft.itemCount,
          isFragile: widget.draft.isFragile,
          weightKg: widget.draft.weightKg,
          helpersCount: widget.draft.helpersCount,
          pickup: ShipmentLocation(
            address: widget.draft.pickup,
            latitude: pickupLatitude,
            longitude: pickupLongitude,
            notes: widget.draft.pickupNotes.isEmpty
                ? null
                : widget.draft.pickupNotes,
          ),
          dropoff: ShipmentLocation(
            address: widget.draft.destination,
            latitude: dropoffLatitude,
            longitude: dropoffLongitude,
            notes: widget.draft.dropoffNotes.isEmpty
                ? null
                : widget.draft.dropoffNotes,
          ),
          pickupType: widget.draft.pickupType,
          pickupAt: widget.draft.scheduledAt,
          paymentMethod: widget.draft.paymentMethod,
          farePaidBy: widget.draft.farePaidBy,
          recipientName: widget.draft.recipientName,
          recipientPhone: widget.draft.recipientPhone,
        );
        widget.draft.shipment = shipment;
      } else {
        shipment = existingShipment;
        final changes = _draftChanges(shipment);
        if (changes.isNotEmpty) {
          shipment = await _service.updateDraft(shipment, changes);
          widget.draft.shipment = shipment;
        }
      }
      while (widget.draft.photos.isNotEmpty) {
        final photo = widget.draft.photos.first;
        shipment = await _service.uploadPhoto(
          shipment: shipment,
          bytes: photo.bytes,
          contentType: photo.contentType,
        );
        widget.draft.shipment = shipment;
        widget.draft.photos.removeAt(0);
        if (mounted) setState(() {});
      }

      shipment = await _service.requestQuotes(shipment);
      widget.draft.shipment = shipment;
      if (!mounted) return;
      final nextPage = widget.draft.useAiEstimate
          ? AiEstimatingPage(draft: widget.draft)
          : VehiclesSmallPage(draft: widget.draft);
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => nextPage));
    } on ShipmentApiException catch (error) {
      widget.draft.fieldErrors[error.field ?? 'shipment'] = error.message;
      _showError(error.message, field: error.field);
    } catch (error) {
      _showError('The shipment could not be saved. $error');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Map<String, dynamic> _draftChanges(Shipment shipment) {
    final draft = widget.draft;
    final changes = <String, dynamic>{};
    if (draft.categoryId != shipment.cargoCategoryId) {
      changes['cargoCategoryId'] = draft.categoryId;
    }
    if (draft.sizeOptionId != shipment.sizeOptionId) {
      changes['sizeOptionId'] = draft.sizeOptionId;
    }
    if (draft.description.trim() != shipment.cargoDescription) {
      changes['cargoDescription'] = draft.description.trim();
    }
    if (draft.itemCount != shipment.itemCount) {
      changes['itemCount'] = draft.itemCount;
    }
    if (draft.isFragile != shipment.isFragile) {
      changes['isFragile'] = draft.isFragile;
    }
    if (draft.weightKg != shipment.weightKg) {
      changes['weightKg'] = draft.weightKg;
    }
    if (draft.helpersCount != shipment.helpersCount) {
      changes['helpersCount'] = draft.helpersCount;
    }
    if (draft.pickup != shipment.pickup?.address ||
        draft.pickupLatitude != shipment.pickup?.latitude ||
        draft.pickupLongitude != shipment.pickup?.longitude ||
        draft.pickupNotes != (shipment.pickup?.notes ?? '')) {
      changes['pickup'] = ShipmentLocation(
        address: draft.pickup,
        latitude: draft.pickupLatitude ?? 0,
        longitude: draft.pickupLongitude ?? 0,
        notes: draft.pickupNotes,
      ).toJson();
    }
    if (draft.destination != shipment.dropoff?.address ||
        draft.dropoffLatitude != shipment.dropoff?.latitude ||
        draft.dropoffLongitude != shipment.dropoff?.longitude ||
        draft.dropoffNotes != (shipment.dropoff?.notes ?? '')) {
      changes['dropoff'] = ShipmentLocation(
        address: draft.destination,
        latitude: draft.dropoffLatitude ?? 0,
        longitude: draft.dropoffLongitude ?? 0,
        notes: draft.dropoffNotes,
      ).toJson();
    }
    if (draft.pickupType != shipment.pickupType) {
      changes['pickupType'] = draft.pickupType;
    }
    if (draft.pickupType == 'scheduled' &&
        draft.scheduledAt != shipment.pickupAt) {
      changes['pickupAt'] = draft.scheduledAt?.toUtc().toIso8601String();
    }
    if (draft.paymentMethod != shipment.paymentMethod) {
      changes['paymentMethod'] = draft.paymentMethod;
    }
    if (draft.farePaidBy != shipment.farePaidBy) {
      changes['farePaidBy'] = draft.farePaidBy;
    }
    if (draft.recipientName != (shipment.recipientName ?? '')) {
      changes['recipientName'] = draft.recipientName;
    }
    if (draft.recipientPhone != (shipment.recipientPhone ?? '')) {
      changes['recipientPhone'] = draft.recipientPhone;
    }
    return changes;
  }

  Future<void> _removeUploadedPhoto(ShipmentPhoto photo) async {
    final shipment = widget.draft.shipment;
    if (shipment == null) return;
    setState(() => _isSubmitting = true);
    try {
      widget.draft.shipment = await _service.removePhoto(
        shipment: shipment,
        photoId: photo.id,
      );
    } on ShipmentApiException catch (error) {
      _showError(error.message, field: error.field);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message, {String? field}) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _errorField = field;
      if (field != null) widget.draft.fieldErrors[field] = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shipment = widget.draft.shipment;
    return CargoPageScaffold(
      title: 'Add cargo photos',
      step: 5,
      buttonText: _isSubmitting
          ? 'Saving shipment...'
          : shipment == null
          ? 'Create draft and request quotes'
          : 'Upload photos and request quotes',
      buttonEnabled: !_isSubmitting,
      onContinue: _createAndRequestQuotes,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Capture up to 10 JPEG, PNG, or WebP cargo photos. Each photo must be no larger than 5 MB.',
            style: AppTypography.bodySm,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : () => _capturePhoto(),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Open camera'),
          ),
          const SizedBox(height: 12),
          if (widget.draft.photos.isEmpty && (shipment?.photos.isEmpty ?? true))
            _emptyPhotoState()
          else ...[
            for (var index = 0; index < widget.draft.photos.length; index++)
              _pendingPhotoCard(index),
            for (final photo in shipment?.photos ?? const <ShipmentPhoto>[])
              _uploadedPhotoCard(photo),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.light,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _errorField == null
                        ? 'Unable to continue'
                        : 'Check $_errorField',
                    style: AppTypography.labelSm,
                  ),
                  const SizedBox(height: 6),
                  Text(_errorMessage!, style: AppTypography.bodySm),
                  if (_errorField != null && _errorField != 'photos')
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('Edit shipment details'),
                    ),
                ],
              ),
            ),
          ],
          if (shipment != null) ...[
            const SizedBox(height: 16),
            Text(
              'Draft shipment #${shipment.id} · ${shipment.status}',
              style: AppTypography.labelSm,
            ),
            const SizedBox(height: 4),
            Text(
              'The server draft is reused if you retry; a second shipment will not be created.',
              style: AppTypography.bodyXs,
            ),
          ],
          const SizedBox(height: 20),
          const CargoSectionLabel('Move summary'),
          _SummaryRow(label: 'Cargo', value: widget.draft.category),
          _SummaryRow(label: 'From', value: widget.draft.pickup),
          _SummaryRow(label: 'To', value: widget.draft.destination),
        ],
      ),
    );
  }

  Widget _emptyPhotoState() => Container(
    width: double.infinity,
    height: 150,
    decoration: BoxDecoration(
      color: AppColors.light,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFCDD1CE)),
    ),
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo_outlined, size: 38, color: AppColors.darkGreen),
        SizedBox(height: 8),
        Text('No cargo photos captured'),
      ],
    ),
  );

  Widget _pendingPhotoCard(int index) {
    final photo = widget.draft.photos[index];
    return Card(
      child: Column(
        children: [
          Image.memory(
            photo.bytes,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox(
              height: 180,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
          Row(
            children: [
              Expanded(child: Text(photo.fileName, maxLines: 1)),
              IconButton(
                tooltip: 'Retake photo',
                onPressed: _isSubmitting
                    ? null
                    : () => _capturePhoto(replaceIndex: index),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Remove photo',
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() => widget.draft.photos.removeAt(index)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _uploadedPhotoCard(ShipmentPhoto photo) => Card(
    child: Column(
      children: [
        Image.network(
          photo.url,
          width: double.infinity,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox(
            height: 180,
            child: Center(child: Icon(Icons.image_outlined)),
          ),
        ),
        Row(
          children: [
            const Expanded(
              child: Text('Uploaded photo (temporary URL, valid for 1 hour)'),
            ),
            IconButton(
              tooltip: 'Remove uploaded photo',
              onPressed: _isSubmitting
                  ? null
                  : () => _removeUploadedPhoto(photo),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 84,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.darkGreen, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? 'Not provided' : value,
            style: const TextStyle(
              color: AppColors.darkGreen,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
