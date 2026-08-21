import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../data/api_verification_repository.dart';
import '../../domain/verification_repository.dart';

enum PersonalDocumentStatus { idle, picking, uploading, success, error }

/// The two document types this step accepts — each is independently
/// optional, but the user must submit at least one to continue (enforced
/// by the screen, not here).
enum PersonalDocumentKind { aadhaar, pan }

extension PersonalDocumentKindX on PersonalDocumentKind {
  String get documentType => switch (this) {
        PersonalDocumentKind.aadhaar => 'aadhaar',
        PersonalDocumentKind.pan => 'pan',
      };

  String get label => switch (this) {
        PersonalDocumentKind.aadhaar => 'Aadhaar Card',
        PersonalDocumentKind.pan => 'PAN Card',
      };
}

class PersonalDocumentSlotState {
  final PersonalDocumentStatus status;
  final String? pickedFilename;
  final AppFailure? failure;

  const PersonalDocumentSlotState({
    this.status = PersonalDocumentStatus.idle,
    this.pickedFilename,
    this.failure,
  });

  PersonalDocumentSlotState copyWith({
    PersonalDocumentStatus? status,
    String? pickedFilename,
    AppFailure? failure,
  }) {
    return PersonalDocumentSlotState(
      status: status ?? this.status,
      pickedFilename: pickedFilename ?? this.pickedFilename,
      failure: failure,
    );
  }
}

class PersonalDocumentState {
  final PersonalDocumentSlotState aadhaar;
  final PersonalDocumentSlotState pan;

  const PersonalDocumentState({
    this.aadhaar = const PersonalDocumentSlotState(),
    this.pan = const PersonalDocumentSlotState(),
  });

  bool get hasAtLeastOne =>
      aadhaar.status == PersonalDocumentStatus.success || pan.status == PersonalDocumentStatus.success;

  PersonalDocumentSlotState slot(PersonalDocumentKind kind) =>
      kind == PersonalDocumentKind.aadhaar ? aadhaar : pan;

  PersonalDocumentState copyWithSlot(PersonalDocumentKind kind, PersonalDocumentSlotState slot) {
    return switch (kind) {
      PersonalDocumentKind.aadhaar => PersonalDocumentState(aadhaar: slot, pan: pan),
      PersonalDocumentKind.pan => PersonalDocumentState(aadhaar: aadhaar, pan: slot),
    };
  }
}

/// Drives the "upload a personal document" onboarding step: the user can
/// submit Aadhaar and/or PAN, each as either a gallery photo or a PDF.
/// Both are independently optional, but at least one is required overall
/// (enforced by the screen). Like the selfie step, the backend review is
/// async — a successful upload here means the document is pending admin
/// review, not that it's approved.
class PersonalDocumentController extends StateNotifier<PersonalDocumentState> {
  final VerificationRepository _repository;

  PersonalDocumentController(this._repository) : super(const PersonalDocumentState());

  Future<void> pickAndUploadFromGallery(PersonalDocumentKind kind) async {
    _setSlot(kind, state.slot(kind).copyWith(status: PersonalDocumentStatus.picking));
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null) {
        _setSlot(kind, state.slot(kind).copyWith(status: PersonalDocumentStatus.idle));
        return;
      }
      final bytes = await picked.readAsBytes();
      final filename = picked.name.isNotEmpty ? picked.name : 'document.jpg';
      final contentType = _imageContentType(filename);
      await _upload(kind: kind, bytes: bytes, filename: filename, contentType: contentType);
    } catch (_) {
      _setSlot(
        kind,
        state.slot(kind).copyWith(
              status: PersonalDocumentStatus.error,
              failure: AppFailure.unknown('Could not access the gallery. Please try again.'),
            ),
      );
    }
  }

  Future<void> pickAndUploadPdf(PersonalDocumentKind kind) async {
    _setSlot(kind, state.slot(kind).copyWith(status: PersonalDocumentStatus.picking));
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        _setSlot(kind, state.slot(kind).copyWith(status: PersonalDocumentStatus.idle));
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        _setSlot(
          kind,
          state.slot(kind).copyWith(
                status: PersonalDocumentStatus.error,
                failure: AppFailure.unknown('Could not read the selected PDF. Please try again.'),
              ),
        );
        return;
      }
      final filename = file.name.isNotEmpty ? file.name : 'document.pdf';
      await _upload(kind: kind, bytes: bytes, filename: filename, contentType: 'application/pdf');
    } catch (_) {
      _setSlot(
        kind,
        state.slot(kind).copyWith(
              status: PersonalDocumentStatus.error,
              failure: AppFailure.unknown('Could not access files. Please try again.'),
            ),
      );
    }
  }

  Future<void> _upload({
    required PersonalDocumentKind kind,
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    const maxBytes = 10 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      _setSlot(
        kind,
        state.slot(kind).copyWith(
              status: PersonalDocumentStatus.error,
              failure: AppFailure.validation('That file is larger than 10MB. Please choose a smaller file.'),
            ),
      );
      return;
    }

    _setSlot(
      kind,
      state.slot(kind).copyWith(status: PersonalDocumentStatus.uploading, pickedFilename: filename),
    );
    final result = await _repository.submitDocument(
      documentType: kind.documentType,
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    );
    result.when(
      success: (_) {
        _setSlot(
          kind,
          state.slot(kind).copyWith(status: PersonalDocumentStatus.success, pickedFilename: filename),
        );
      },
      failure: (failure) {
        _setSlot(kind, state.slot(kind).copyWith(status: PersonalDocumentStatus.error, failure: failure));
      },
    );
  }

  void _setSlot(PersonalDocumentKind kind, PersonalDocumentSlotState slot) {
    state = state.copyWithSlot(kind, slot);
  }

  String _imageContentType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }
}

final personalDocumentControllerProvider =
    StateNotifierProvider.autoDispose<PersonalDocumentController, PersonalDocumentState>((ref) {
  return PersonalDocumentController(ref.watch(verificationRepositoryProvider));
});
