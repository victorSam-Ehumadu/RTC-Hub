import 'dart:io';

import '../core/supabase.dart';
import '../models/verification.dart';
import 'storage_repository.dart';

/// Alumni identity verification (§2.1).
///
/// The flow this implements, and why, is argued in migration 0014. In short:
/// the institution's strongest signal — the student mailbox — is exactly
/// what has expired for this user group, and there is no student-records API
/// to query, so the app collects a claim plus a document and puts a human in
/// the loop. Everything that would make that theatre (self-approval, editing
/// the claim after review) is blocked by trigger rather than by this class.
class VerificationRepository {
  const VerificationRepository();

  /// The signed-in user's own submission, if they have made one.
  Future<AlumniVerification?> mine() async {
    final row = await db
        .from('alumni_verifications')
        .select()
        .eq('user_id', requireUserId)
        .maybeSingle();
    return row == null ? null : AlumniVerification.fromMap(row);
  }

  /// Uploads the evidence and files the claim.
  ///
  /// The document goes to the private `verification` bucket, whose policies
  /// (migration 0002) restrict reads to the owner and administrators. Only
  /// the *path* is stored — a signed URL would expire mid-review, and one
  /// that did not would be a transcript sitting on a guessable link.
  Future<void> submit({
    required File evidence,
    required String studentNumber,
    required int graduationYear,
    required String evidenceKind,
    String? course,
    String? campus,
    String? note,
  }) async {
    final path = await const StorageRepository().uploadAndKeepPath(
      evidence,
      bucket: StorageRepository.verification,
    );

    await db.from('alumni_verifications').upsert({
      'user_id': requireUserId,
      'claimed_student_number': studentNumber.trim(),
      'claimed_graduation_year': graduationYear,
      'claimed_course': course,
      'claimed_campus': campus,
      'evidence_kind': evidenceKind,
      'evidence_path': path,
      'note': note?.trim(),
    }, onConflict: 'user_id');
  }

  // ─── Administrator side ────────────────────────────────────

  /// The review queue. Returns nothing at all for a non-admin — the SQL
  /// gates on `is_admin()` inside the function rather than filtering after.
  Future<List<AlumniVerification>> queue({String status = 'PENDING'}) async {
    final rows = await db.rpc(
      'alumni_review_queue',
      params: {'p_status': status},
    ) as List;
    return rows
        .cast<Map<String, dynamic>>()
        .map(AlumniVerification.fromMap)
        .toList();
  }

  /// Approve or reject. Approving is what activates the account —
  /// `trg_alumni_verification_reviewed` copies the claim onto the profile
  /// and flips its status, so a reviewer cannot accept the evidence and
  /// leave the person locked out.
  Future<void> decide(
    String verificationId, {
    required bool approve,
    String? reviewerNote,
  }) =>
      db.from('alumni_verifications').update({
        'status': approve ? 'APPROVED' : 'REJECTED',
        'reviewer_note': reviewerNote?.trim(),
      }).eq('id', verificationId);

  /// A short-lived link to one document, minted when a reviewer opens it.
  Future<String> evidenceUrl(String verificationId) async {
    final path =
        await db.rpc('alumni_evidence_path', params: {
      'p_verification': verificationId,
    });
    if (path == null) {
      throw StateError('That document is not available.');
    }
    return const StorageRepository().signedUrlFor(
      StorageRepository.verification,
      path as String,
      // Long enough to read, short enough that a shared screenshot of the
      // URL is worthless by the time anyone else tries it.
      validFor: const Duration(minutes: 15),
    );
  }
}
