import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Owner photos remain previews until upload rules are verified and enabled.
/// Public places only display reviewed/published logo URLs.
class DedaPlaceLogoService {
  static const bool uploadsEnabled = bool.fromEnvironment(
    'DEDA_OWNER_PLACE_LOGO_UPLOADS_LIVE',
    defaultValue: false,
  );

  static Future<XFile?> chooseLogo() =>
      ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 55,
        maxWidth: 640,
        maxHeight: 640,
      );

  static Future<String> uploadForReview(String imagePath) async {
    if (!uploadsEnabled) throw StateError('owner-logo-uploads-disabled');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('owner-login-required');
    final photo = File(imagePath);
    final bytes = await photo.readAsBytes();
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw StateError('logo-must-be-under-1mb');
    }
    final ref = FirebaseStorage.instance.ref().child(
      'owner_place_logos/' +
          user.uid +
          '/' +
          DateTime.now().microsecondsSinceEpoch.toString() +
          '.jpg',
    );
    await ref.putData(
      bytes,
      SettableMetadata(
        contentType: 'image/jpeg',
        customMetadata: {'uploadedByUid': user.uid},
      ),
    );
    return ref.getDownloadURL();
  }
}

class DedaOwnerPlaceLogo extends StatelessWidget {
  final String localFilePath;
  final String publishedUrl;
  final IconData fallbackIcon;
  final Color accent;
  final double radius;

  const DedaOwnerPlaceLogo({
    super.key,
    this.localFilePath = '',
    this.publishedUrl = '',
    required this.fallbackIcon,
    required this.accent,
    this.radius = 40,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      fallbackIcon,
      size: radius * 0.90,
      color: accent,
    );
    final safeUrl = Uri.tryParse(publishedUrl);
    Widget picture = fallback;
    if (localFilePath.isNotEmpty && File(localFilePath).existsSync()) {
      picture = Image.file(
        File(localFilePath),
        fit: BoxFit.cover,
        width: radius * 2,
        height: radius * 2,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else if (safeUrl != null && safeUrl.scheme == 'https') {
      picture = Image.network(
        publishedUrl,
        fit: BoxFit.cover,
        width: radius * 2,
        height: radius * 2,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    return Container(
      width: radius * 2,
      height: radius * 2,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withOpacity(0.45), width: 2),
      ),
      child: Center(child: picture),
    );
  }
}
