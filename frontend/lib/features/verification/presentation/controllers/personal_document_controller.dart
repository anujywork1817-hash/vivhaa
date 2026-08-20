import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/exceptions/app_exception.dart';
import '../../data/api_verification_repository.dart';
import '../../domain/verification_repository.dart';

enum PersonalDocumentStatus { idle, picking, uploading, success, error }

class PersonalDocumentState {
  final PersonalDocumentStatus status;
  final String? pickedFilename;
  final AppFailure? failure;

  const PersonalDocumentState({
    this.status = PersonalDocumentStatus.idle,
    this.pickedFilename,
    this.failure,
  });

  PersonalDocumentState copyWith({
    PersonalDocumentStatus? status,
    String? pickedFilename,
    AppFailure? failure,
  }) {
    return PersonalDocumentState(
      status: status ?? this.status,
      pickedFilename: pickedFilename ?? this.pickedFilename,
      failure: failure,
    );
  }
}

/// Drives the mandatory "upload personal document" onboarding step: the
/// user picks either a gallery photo or a PDF, and it's uploaded as a
/// `personal_document` verification submission. Like the selfie step,
/// the backend review is async — a successful upload here means the
/// document is pending admin review, not that it's approved.
class PersonalDocumentController extends StateNotifier<PersonalDocumentState> {
  final VerificationRepository _repository;

  PersonalDocumentController(this._repository) : super(const PersonalDocumentState());

  Future<void> pickAndUploadFromGallery() async {
    state = state.copyWith(status: PersonalDocumentStatus.picking);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (picked == null) {
        state = state.copyWith(status: PersonalDocumentStatus.idle);
        return;
      }
      final bytes = await picked.readAsBytes();
      final filename = picked.name.isNotEmpty ? picked.name : 'document.jpg';
      final contentType = _imageContentType(filename);
      await _upload(bytes: bytes, filename: filename, contentType: contentType);
    } catch (_) {
      state = state.copyWith(
        status: PersonalDocumentStatus.error,
        failure: AppFailure.unknown('Could not access the gallery. Please try again.'),
      );
    }
  }

  Future<void> pickAndUploadPdf() async {
    state = state.copyWith(status: PersonalDocumentStatus.picking);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        state = state.copyWith(status: PersonalDocumentStatus.idle);
        return;
      }
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        state = state.copyWith(
          status: PersonalDocumentStatus.error,
          failure: AppFailure.unknown('Could not read the selected PDF. Please try again.'),
        );
        return;
      }
      final filename = file.name.isNotEmpty ? file.name : 'document.pdf';
      await _upload(bytes: bytes, filename: filename, contentType: 'application/pdf');
    } catch (_) {
      state = state.copyWith(
        status: PersonalDocumentStatus.error,
        failure: AppFailure.unknown('Could not access files. Please try again.'),
      );
    }
  }

  Future<void> _upload({
    required List<int> bytes,
    required String filename,
    required String contentType,
  }) async {
    const maxBytes = 10 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      state = state.copyWith(
        status: PersonalDocumentStatus.error,
        failure: AppFailure.validation('That file is larger than 10MB. Please choose a smaller file.'),
      );
      return;
    }

    state = state.copyWith(status: PersonalDocumentStatus.uploading, pickedFilename: filename);
    final result = await _repository.submitDocument(
      documentType: 'personal_document',
      bytes: bytes,
      filename: filename,
      contentType: contentType,
    );
    result.when(
      success: (_) {
        state = state.copyWith(status: PersonalDocumentStatus.success, pickedFilename: filename);
      },
      failure: (failure) {
        state = state.copyWith(status: PersonalDocumentStatus.error, failure: failure);
      },
    );
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
