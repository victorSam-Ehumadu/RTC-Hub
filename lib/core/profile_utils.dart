import '../models/profile.dart';

/// Returns a list of missing profile components for completeness checking.
/// Used by both onboarding and the completeness breakdown screen.
List<String> getMissingProfileComponents(Profile profile, List<Skill> skills) {
  return <String>[
    if ((profile.bio ?? '').isEmpty) 'Add a bio',
    if (skills.isEmpty) 'Add skills',
    if ((profile.cvUrl ?? '').isEmpty) 'Upload a CV',
    if ((profile.portfolioUrl ?? '').isEmpty) 'Add a portfolio link',
  ];
}
