import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/env.dart';
import '../core/supabase.dart';
import '../models/assistant.dart';

/// Stream A: talks to Google's Gemini API, and to `chat_messages` /
/// `onboarding_progress`. Nothing here replaces an old Express route — this
/// feature didn't exist before the Flutter rewrite.
///
/// Two decisions worth recording for the presentation, per CLAUDE.md's rule
/// that a stack deviation needs its reasoning written down:
///
/// 1. The official `google_generative_ai` Dart package is deprecated by
///    Google in favour of the Firebase AI SDK, so this calls the Gemini
///    REST API directly with `http` instead of depending on it.
/// 2. The call is made straight from the client with the key baked in at
///    build time (`Env.geminiApiKey`) rather than proxied through a Supabase
///    Edge Function. That's the fastest path to a working feature; the
///    trade-off is the key ships inside the compiled app, unlike the
///    Supabase anon key, which is *meant* to be public. Fine for a
///    hackathon build — call out the trade-off if asked why.
class AiRepository {
  const AiRepository();

  // One place to change if this needs updating — Google renames/retires
  // model names periodically. Confirming this string is still live is the
  // first thing to check if every AI call starts failing.
  //
  // gemini-2.5-flash was the original choice here but returned a 404 with
  // "no longer available to new users" the first time this was tested for
  // real (12 Sep 2026) — Google's own error pointed at this replacement.
  static const _model = 'gemini-3.6-flash';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  /// This user's chat history with the assistant, oldest first.
  ///
  /// `ascending: true` is required, not a stylistic choice: the
  /// `postgrest` package defaults `.order()` to **descending**
  /// (newest-first) when it's left unspecified — the opposite of what
  /// "oldest first" needs, and the actual cause of messages rendering
  /// backwards until this was traced down.
  Future<List<ChatMessage>> history() async {
    final rows = await db
        .from('chat_messages')
        .select()
        .eq('user_id', requireUserId)
        .order('created_at', ascending: true);
    return rows.map(ChatMessage.fromMap).toList();
  }

  /// Sends [content] as the user, saves both sides of the exchange, and
  /// returns the assistant's reply.
  ///
  /// [systemPrompt] sets the assistant's behaviour for this call — onboarding
  /// and the freeform chat screen pass different ones. [priorTurns] gives it
  /// recent context; keep this short since it is resent on every call.
  Future<ChatMessage> send(
    String content, {
    required String systemPrompt,
    List<ChatMessage> priorTurns = const [],
  }) async {
    final me = requireUserId;

    await db.from('chat_messages').insert({
      'user_id': me,
      'role': 'user',
      'content': content,
    });

    final reply = await _generate(
      systemPrompt: systemPrompt,
      turns: [...priorTurns, _pendingTurn(me, content)],
    );

    final row = await db
        .from('chat_messages')
        .insert({'user_id': me, 'role': 'assistant', 'content': reply})
        .select()
        .single();
    return ChatMessage.fromMap(row);
  }

  /// A one-off call with no saved history — used by CV skill extraction
  /// (Step 6), where the exchange isn't a chat message.
  Future<String> ask(String prompt, {String? systemPrompt}) => _generate(
        systemPrompt: systemPrompt,
        turns: [_pendingTurn(requireUserId, prompt)],
      );

  /// Opens the onboarding conversation with the assistant speaking first,
  /// rather than leaving a new user staring at a blank chat box wondering
  /// what to say. Only called when [history] comes back empty.
  Future<ChatMessage> startOnboarding({required String systemPrompt}) async {
    final me = requireUserId;
    final reply = await _generate(
      systemPrompt: systemPrompt,
      turns: [_pendingTurn(me, 'Begin the onboarding walkthrough.')],
    );
    final row = await db
        .from('chat_messages')
        .insert({'user_id': me, 'role': 'assistant', 'content': reply})
        .select()
        .single();
    return ChatMessage.fromMap(row);
  }

  ChatMessage _pendingTurn(String userId, String content) => ChatMessage(
        id: '',
        userId: userId,
        role: 'user',
        content: content,
        createdAt: DateTime.now(),
      );

  Future<String> _generate({
    String? systemPrompt,
    required List<ChatMessage> turns,
  }) async {
    if (Env.geminiApiKey.isEmpty) {
      throw StateError(
        'GEMINI_API_KEY is missing. Add it to env.json and rerun with '
        '--dart-define-from-file=env.json.',
      );
    }

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': Env.geminiApiKey,
      },
      body: jsonEncode({
        if (systemPrompt != null)
          'systemInstruction': {
            'parts': [
              {'text': systemPrompt},
            ],
          },
        'contents': [
          for (final turn in turns)
            {
              'role': turn.isFromUser ? 'user' : 'model',
              'parts': [
                {'text': turn.content},
              ],
            },
        ],
      }),
    );

    if (response.statusCode == 429) {
      throw StateError(
        "You're sending messages faster than the API key's rate limit "
        'allows. Wait a minute and try again — this is not a bug, just a '
        'free-tier quota.',
      );
    }
    if (response.statusCode != 200) {
      throw StateError(
        'The AI assistant could not be reached (HTTP ${response.statusCode}). '
        'Check GEMINI_API_KEY in env.json, and that "$_model" is still a '
        'valid model name.',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = (body['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      throw StateError('The assistant returned an empty response.');
    }

    final text = _extractText(candidates.first as Map<String, dynamic>);
    if (text == null || text.isEmpty) {
      throw StateError('The assistant returned an empty response.');
    }
    return text;
  }

  /// gemini-3.6-flash is a "thinking" model — a reply can arrive as several
  /// parts, some marked `thought: true` (its internal reasoning, not meant
  /// to be shown). Joining every non-thought part rather than only reading
  /// the first one avoids silently truncating a longer reply.
  String? _extractText(Map<String, dynamic> candidate) {
    final content = candidate['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;

    final joined = parts
        .cast<Map<String, dynamic>>()
        .where((p) => p['thought'] != true)
        .map((p) => p['text'] as String? ?? '')
        .where((t) => t.isNotEmpty)
        .join();
    return joined.isEmpty ? null : joined;
  }

  /// §2.8: NLP-assisted profile building. Sends the CV file itself to
  /// Gemini as an inline attachment (it reads PDFs/docs natively) rather
  /// than trying to extract text ourselves first, and asks for skills *and*
  /// work experience back in one call — one attachment upload, one round
  /// trip, rather than analysing the same file twice. Returns empty lists
  /// rather than throwing if the model's reply can't be parsed — a CV with
  /// nothing detectable is a valid outcome, not a bug.
  Future<CvExtraction> extractFromCv({
    required List<int> bytes,
    required String mimeType,
  }) async {
    if (Env.geminiApiKey.isEmpty) {
      throw StateError(
        'GEMINI_API_KEY is missing. Add it to env.json and rerun with '
        '--dart-define-from-file=env.json.',
      );
    }

    const prompt = '''
Extract from this CV:
1. Professional/technical skills — short names only.
2. Work experience entries — job title, employer, start date, end date, and
   a one-sentence description if one is stated.

Return ONLY a JSON object, nothing else — no markdown fences, no
explanation:
{
  "skills": ["Python", "Figma"],
  "experience": [
    {
      "title": "Junior Developer",
      "company": "Acme Corp",
      "startDate": "2023-01-01",
      "endDate": "2024-06-01",
      "description": "Built internal tooling in Python."
    }
  ]
}

Rules:
- Dates must be "YYYY-MM-DD" (use the 1st of the month when only a month and
  year are given), or null if a date isn't stated.
- A current/ongoing role has "endDate": null.
- If nothing is found for a field, return an empty list for it — never omit
  either key.
''';

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': Env.geminiApiKey,
      },
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {
                'inlineData': {
                  'mimeType': mimeType,
                  'data': base64Encode(bytes),
                },
              },
            ],
          },
        ],
      }),
    );

    if (response.statusCode == 429) {
      throw StateError(
        "You're sending requests faster than the API key's rate limit "
        'allows. Wait a minute and try again.',
      );
    }
    if (response.statusCode != 200) {
      throw StateError(
        'The CV could not be analysed (HTTP ${response.statusCode}).',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = (body['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) return const CvExtraction();

    final text = _extractText(candidates.first as Map<String, dynamic>);
    return text == null ? const CvExtraction() : _parseCvExtraction(text);
  }

  /// Gemini is asked for plain JSON but occasionally wraps it in a
  /// ```json ... ``` fence anyway — strip that before parsing. Anything
  /// that still doesn't parse cleanly, or has an entry missing a title or
  /// company, is dropped rather than surfaced as an error — the user can
  /// just try again.
  CvExtraction _parseCvExtraction(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceAll(RegExp(r'^```[a-zA-Z]*', multiLine: true), '')
          .replaceAll('```', '')
          .trim();
    }
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, dynamic>) return const CvExtraction();

      final skills = (decoded['skills'] as List? ?? const [])
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final experience = (decoded['experience'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) {
            final e = entry.cast<String, dynamic>();
            final title = (e['title'] as String? ?? '').trim();
            final company = (e['company'] as String? ?? '').trim();
            if (title.isEmpty || company.isEmpty) return null;
            return ExtractedExperience(
              title: title,
              company: company,
              startDate: DateTime.tryParse(e['startDate'] as String? ?? ''),
              endDate: DateTime.tryParse(e['endDate'] as String? ?? ''),
              description: (e['description'] as String?)?.trim(),
            );
          })
          .whereType<ExtractedExperience>()
          .toList();

      return CvExtraction(skills: skills, experience: experience);
    } catch (_) {
      return const CvExtraction();
    }
  }

  // ─── Onboarding progress ──────────────────────────────────────

  Future<OnboardingProgress> onboardingProgress() async {
    final row = await db
        .from('onboarding_progress')
        .select()
        .eq('user_id', requireUserId)
        .single();
    return OnboardingProgress.fromMap(row);
  }

  Future<void> setProfileStep(int step) => db
      .from('onboarding_progress')
      .update({'profile_step': step})
      .eq('user_id', requireUserId);

  Future<void> completeTutorial() => db.from('onboarding_progress').update({
        'tutorial_complete': true,
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('user_id', requireUserId);
}
