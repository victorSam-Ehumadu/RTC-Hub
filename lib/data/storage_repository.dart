import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/supabase.dart';

/// Replaces `/api/upload` (multer + sharp).
///
/// Files go straight from the device to Supabase Storage. The policies in
/// migration 0002 key ownership off the first path segment, so every object
/// **must** be written as `<uid>/<filename>` — anything else is rejected.
class StorageRepository {
  const StorageRepository();

  static const avatars = 'avatars';
  static const postMedia = 'post-media';
  static const postAttachments = 'post-attachments';
  static const documents = 'documents';
  static const verification = 'verification';

  /// Uploads [file] and returns a URL usable by the app: a public URL for the
  /// open buckets, a time-limited signed URL for the private ones.
  Future<String> upload(File file, {required String bucket}) async {
    final uid = requireUserId;
    final name = '${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
    final path = '$uid/$name';

    await db.storage.from(bucket).upload(path, file);

    final isPublic = bucket == avatars || bucket == postMedia;
    if (isPublic) {
      return db.storage.from(bucket).getPublicUrl(path);
    }
    return db.storage.from(bucket).createSignedUrl(path, 60 * 60 * 24 * 7);
  }

  Future<String> uploadAvatar(File file) => upload(file, bucket: avatars);
  Future<String> uploadPostMedia(File file) => upload(file, bucket: postMedia);
  Future<String> uploadCv(File file) => upload(file, bucket: documents);
  Future<String> uploadVerification(File file) =>
      upload(file, bucket: verification);

  /// Re-signs a private URL that has expired.
  Future<String> refreshSignedUrl(String bucket, String path) =>
      db.storage.from(bucket).createSignedUrl(path, 60 * 60 * 24 * 7);

  Future<void> remove(String bucket, String path) =>
      db.storage.from(bucket).remove([path]);
}
