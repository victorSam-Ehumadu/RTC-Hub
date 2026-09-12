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
  static const documents = 'documents';
  static const verification = 'verification';

  /// Bounty answers. Private: readable by anyone who can read the
  /// bounty, which routes through posts_select and so inherits the
  /// faculty scoping from migration 0007.
  static const submissions = 'submissions';

  /// Uploads [file] and returns a URL usable by the app: a public URL for the
  /// open buckets, a time-limited signed URL for the private ones.
  ///
  /// **Do not persist the result for a private bucket.** The signed URL
  /// expires in a week, and `profiles.cv_url` used to store one — so a
  /// recruiter opening an application eight days later got a 400. Use
  /// [uploadAndKeepPath] for anything written to a column, and sign it on
  /// read with [signedUrlFor].
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

  Future<String> uploadSubmission(File file) =>
      upload(file, bucket: submissions);

  /// Uploads and returns the storage *path*, which does not expire.
  ///
  /// This is what belongs in a database column. A CV uploaded in March and
  /// read in April has to still resolve, and a signed URL will not.
  Future<String> uploadAndKeepPath(File file, {required String bucket}) async {
    final uid = requireUserId;
    final name =
        '${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
    final path = '$uid/$name';
    await db.storage.from(bucket).upload(path, file);
    return path;
  }

  /// Mints a fresh signed URL for a stored path. Short-lived on purpose:
  /// it is generated at the moment of use, so there is no reason for it to
  /// outlive the screen that asked for it.
  Future<String> signedUrlFor(String bucket, String path,
          {Duration validFor = const Duration(hours: 2)}) =>
      db.storage.from(bucket).createSignedUrl(path, validFor.inSeconds);

  /// Re-signs a private URL that has expired.
  Future<String> refreshSignedUrl(String bucket, String path) =>
      db.storage.from(bucket).createSignedUrl(path, 60 * 60 * 24 * 7);

  Future<void> remove(String bucket, String path) =>
      db.storage.from(bucket).remove([path]);
}
