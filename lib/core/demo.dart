import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState;

import '../data/admin_repository.dart';
import '../data/auth_repository.dart';
import '../data/opportunity_repository.dart';
import '../data/post_repository.dart';
import '../data/profile_repository.dart';
import '../data/social_repository.dart';
import '../data/storage_repository.dart';
import '../models/opportunity.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/social.dart';
import '../providers.dart';

/// Offline sample data, for `--dart-define=DEMO=true`.
///
/// The point is to walk the UI without a Supabase project: `main()` skips
/// `Supabase.initialize` entirely in demo mode, so `db` is never touched and no
/// network call is made. Everything here is in-memory and resets on restart.
///
/// This is a *presentation* aid, not a test double. It deliberately shows the
/// app populated rather than empty, and it bypasses the RLS boundary that is
/// the whole security model — so nothing seen in demo mode proves anything
/// about authorization. Never demo a permissions claim from here.

// ─── Change bus ───────────────────────────────────────────────
// Screens vary in whether they invalidate a provider after a mutation, so the
// demo repositories ping this and the stream overrides re-yield.

final _bus = StreamController<void>.broadcast();
void _ping() => _bus.add(null);

DateTime _minsAgo(int m) => DateTime.now().subtract(Duration(minutes: m));
DateTime _hoursAgo(int h) => DateTime.now().subtract(Duration(hours: h));
DateTime _daysAgo(int d) => DateTime.now().subtract(Duration(days: d));
DateTime _daysAhead(int d) => DateTime.now().add(Duration(days: d));

// ─── People ───────────────────────────────────────────────────

final demoMe = Profile(
  id: 'u-me',
  email: '202312345@richfield.ac.za',
  fullName: 'Thabo Mokoena',
  role: 'STUDENT',
  status: 'ACTIVE',
  studentNumber: '202312345',
  bio: 'Third-year software dev. Flutter, Postgres, and far too much coffee. '
      'Currently building an attendance app for the campus library.',
  faculty: 'IT',
  course: 'BSc IT (Bachelor of Science in Information Technology)',
  academicYear: '3rd Year',
  graduationYear: 2026,
  portfolioUrl: 'https://github.com/thabom',
  profileCompleteness: 85,
  createdAt: _daysAgo(420),
);

final demoNaledi = Profile(
  id: 'u-naledi',
  email: '202298117@richfield.ac.za',
  fullName: 'Naledi Dlamini',
  role: 'STUDENT',
  status: 'ACTIVE',
  studentNumber: '202298117',
  bio: 'Data science student. I like graphs more than people.',
  faculty: 'IT',
  course: 'BSc IT (Bachelor of Science in Information Technology)',
  academicYear: '2nd Year',
  graduationYear: 2027,
  profileCompleteness: 72,
  createdAt: _daysAgo(300),
);

final demoSipho = Profile(
  id: 'u-sipho',
  email: 'sipho.khumalo@gmail.com',
  fullName: 'Sipho Khumalo',
  role: 'ALUMNI',
  status: 'ACTIVE',
  bio: 'Class of 2021. Backend engineer at Standard Bank. Happy to review CVs '
      'and mock-interview anyone who asks.',
  faculty: 'IT',
  course: 'BSc IT (Bachelor of Science in Information Technology)',
  graduationYear: 2021,
  profileCompleteness: 90,
  createdAt: _daysAgo(900),
);

final demoAisha = Profile(
  id: 'u-aisha',
  email: '202401882@richfield.ac.za',
  fullName: 'Aisha Patel',
  role: 'STUDENT',
  status: 'ACTIVE',
  studentNumber: '202401882',
  bio: 'First-year. Learning Java the hard way.',
  faculty: 'IT',
  course: 'DIT (Diploma in Information Technology)',
  academicYear: '1st Year',
  graduationYear: 2028,
  profileCompleteness: 41,
  createdAt: _daysAgo(120),
);

final demoBusiness = Profile(
  id: 'u-nexford',
  email: 'careers@nexforddigital.co.za',
  fullName: 'Lerato Sithole',
  role: 'BUSINESS',
  status: 'ACTIVE',
  companyName: 'Nexford Digital',
  industry: 'Software & Cloud Services',
  companyLocation: 'Sandton, Johannesburg',
  talentDescription: 'We hire junior Flutter and Node developers every intake.',
  profileCompleteness: 78,
  createdAt: _daysAgo(200),
);

final demoPendingBusiness = Profile(
  id: 'u-pending',
  email: 'hr@brightpathsolutions.co.za',
  fullName: 'Kagiso Mabaso',
  role: 'BUSINESS',
  status: 'PENDING',
  companyName: 'BrightPath Solutions',
  industry: 'Fintech',
  companyLocation: 'Durban',
  profileCompleteness: 35,
  createdAt: _daysAgo(2),
);

final demoPeople = <Profile>[
  demoMe,
  demoNaledi,
  demoSipho,
  demoAisha,
  demoBusiness,
  demoPendingBusiness,
];

Profile _person(String id) =>
    demoPeople.firstWhere((p) => p.id == id, orElse: () => demoMe);

// ─── Posts ────────────────────────────────────────────────────

final demoPosts = <Post>[
  Post(
    id: 'p-1',
    authorId: demoNaledi.id,
    author: demoNaledi,
    type: 'BOUNTY',
    content: 'My Flutter ListView rebuilds every single item when one row '
        'changes and the scroll stutters badly on my phone. I have already '
        'tried const constructors. What am I missing?',
    createdAt: _minsAgo(25),
    isBounty: true,
    bountyPoints: 25,
    bountyModule: 'Mobile Application Development',
    codeLanguage: 'dart',
    codeSnippet: '''ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) {
    return ItemTile(
      item: items[i],
      onTap: () => setState(() => selected = i),
    );
  },
)''',
    reactionCount: 4,
    commentCount: 2,
  ),
  Post(
    id: 'p-2',
    authorId: demoMe.id,
    author: demoMe,
    type: 'CODE',
    content: 'Finally got row-level security working on the messages table. '
        'One policy replaced about 200 lines of middleware. Posting it because '
        'it took me two days to get right.',
    createdAt: _hoursAgo(3),
    codeLanguage: 'sql',
    codeSnippet: '''create policy messages_select on public.messages
for select using (
  auth.uid() = sender_id or auth.uid() = receiver_id
);''',
    reactionCount: 12,
    commentCount: 3,
    myReaction: '🔥',
  ),
  Post(
    id: 'p-3',
    authorId: demoSipho.id,
    author: demoSipho,
    type: 'TEXT',
    content: 'Reminder to the third-years: graduate programme applications for '
        'the big four banks open in March, not June. Everyone I mentor finds '
        'this out in July. Set a calendar reminder now.',
    createdAt: _hoursAgo(9),
    reactionCount: 31,
    commentCount: 5,
  ),
  Post(
    id: 'p-4',
    authorId: demoAisha.id,
    author: demoAisha,
    type: 'BOUNTY',
    content: 'Getting a NullPointerException on line 14 and I genuinely cannot '
        'see why. The array is definitely initialised in the constructor.',
    createdAt: _daysAgo(1),
    isBounty: true,
    bountyPoints: 10,
    bountySolved: true,
    bountyModule: 'Advanced Java',
    codeLanguage: 'java',
    codeSnippet: '''public class Register {
    private String[] names;

    public Register(int size) {
        String[] names = new String[size];
    }

    public void add(int i, String n) {
        names[i] = n;
    }
}''',
    reactionCount: 6,
    commentCount: 4,
  ),
  Post(
    id: 'p-5',
    authorId: demoBusiness.id,
    author: demoBusiness,
    type: 'TEXT',
    content: 'We are running a free two-hour Git and code review workshop on '
        'campus next Thursday. No sign-up, just show up. Bring a laptop.',
    createdAt: _daysAgo(2),
    reactionCount: 18,
    commentCount: 1,
  ),
];

final demoComments = <String, List<Comment>>{
  'p-1': [
    Comment(
      id: 'c-1',
      postId: 'p-1',
      authorId: demoMe.id,
      author: demoMe,
      content: 'Your onTap closure captures setState, so every tile gets a new '
          'callback identity on rebuild. Give ItemTile a stable key and move '
          'the selection into a ValueNotifier.',
      createdAt: _minsAgo(18),
    ),
    Comment(
      id: 'c-2',
      postId: 'p-1',
      authorId: demoSipho.id,
      author: demoSipho,
      content: 'Also worth profiling on the DevTools timeline before you '
          'optimise. You may be fighting the wrong frame.',
      createdAt: _minsAgo(11),
    ),
  ],
  'p-4': [
    Comment(
      id: 'c-3',
      postId: 'p-4',
      authorId: demoNaledi.id,
      author: demoNaledi,
      content: 'Line 5 shadows the field. You declare a *local* String[] names '
          'inside the constructor, so the field stays null. Drop the type: '
          'names = new String[size];',
      createdAt: _daysAgo(1),
      isSolution: true,
    ),
    Comment(
      id: 'c-4',
      postId: 'p-4',
      authorId: demoAisha.id,
      author: demoAisha,
      content: 'That was it. Two days. Thank you.',
      createdAt: _daysAgo(1),
    ),
  ],
};

// ─── Social ───────────────────────────────────────────────────

final demoConnections = <Connection>[
  Connection(
    id: 'cn-1',
    senderId: demoMe.id,
    receiverId: demoNaledi.id,
    sender: demoMe,
    receiver: demoNaledi,
    status: 'ACCEPTED',
    createdAt: _daysAgo(40),
  ),
  Connection(
    id: 'cn-2',
    senderId: demoSipho.id,
    receiverId: demoMe.id,
    sender: demoSipho,
    receiver: demoMe,
    status: 'ACCEPTED',
    createdAt: _daysAgo(30),
  ),
  Connection(
    id: 'cn-3',
    senderId: demoBusiness.id,
    receiverId: demoMe.id,
    sender: demoBusiness,
    receiver: demoMe,
    status: 'ACCEPTED',
    createdAt: _daysAgo(12),
  ),
  Connection(
    id: 'cn-4',
    senderId: demoAisha.id,
    receiverId: demoMe.id,
    sender: demoAisha,
    receiver: demoMe,
    status: 'PENDING',
    createdAt: _hoursAgo(5),
  ),
];

final demoMessages = <Message>[
  Message(
    id: 'm-1',
    senderId: demoSipho.id,
    receiverId: demoMe.id,
    content: 'Saw your RLS post. That policy is the right shape.',
    createdAt: _hoursAgo(2),
    read: true,
  ),
  Message(
    id: 'm-2',
    senderId: demoMe.id,
    receiverId: demoSipho.id,
    content: 'Thanks! Took a while to stop thinking in Express middleware.',
    createdAt: _hoursAgo(2),
    read: true,
  ),
  Message(
    id: 'm-3',
    senderId: demoSipho.id,
    receiverId: demoMe.id,
    content: 'Send me your CV this week and I will mark it up before the '
        'Nexford applications close.',
    createdAt: _minsAgo(40),
  ),
  Message(
    id: 'm-4',
    senderId: demoNaledi.id,
    receiverId: demoMe.id,
    content: 'Are you going to the Git workshop on Thursday?',
    createdAt: _minsAgo(12),
  ),
];

final demoNotifications = <AppNotification>[
  AppNotification(
    id: 'n-1',
    type: 'MESSAGE',
    title: 'Naledi Dlamini sent you a message',
    body: 'Are you going to the Git workshop on Thursday?',
    createdAt: _minsAgo(12),
    data: {'sender_id': demoNaledi.id},
  ),
  AppNotification(
    id: 'n-2',
    type: 'CONNECTION',
    title: 'Aisha Patel wants to connect',
    createdAt: _hoursAgo(5),
    data: {'sender_id': demoAisha.id},
  ),
  AppNotification(
    id: 'n-3',
    type: 'BOUNTY',
    title: 'You earned 15 Logic Points',
    body: 'Your answer was accepted on "Recursion base case never hits".',
    createdAt: _daysAgo(1),
    data: {'post_id': 'p-4'},
  ),
  AppNotification(
    id: 'n-4',
    type: 'REACTION',
    title: 'Sipho Khumalo reacted 🔥 to your post',
    createdAt: _daysAgo(2),
    read: true,
    data: {'post_id': 'p-2'},
  ),
];

// ─── Opportunities and events ─────────────────────────────────

final demoOpportunities = <Opportunity>[
  Opportunity(
    id: 'o-1',
    businessId: demoBusiness.id,
    business: demoBusiness,
    title: 'Junior Flutter Developer (Internship)',
    description: 'Six-month paid internship on our mobile team. You will ship '
        'to production in your first month, with a senior reviewing every pull '
        'request. We look for people who can read code, not just write it.',
    type: 'INTERNSHIP',
    status: 'ACTIVE',
    createdAt: _daysAgo(3),
    location: 'Sandton, Johannesburg',
    requiredSkills: ['Dart', 'Flutter', 'Git'],
    requiredFaculty: 'Information Technology',
    requiredYear: '3rd Year',
    expiresAt: _daysAhead(21),
    applicationCount: 34,
    matchScore: 92,
  ),
  Opportunity(
    id: 'o-2',
    businessId: demoBusiness.id,
    business: demoBusiness,
    title: 'Backend Learnership — Node & Postgres',
    description: 'Twelve-month NQF Level 5 learnership with a stipend. No '
        'prior professional experience required, but you must be comfortable '
        'with SQL joins before you start.',
    type: 'LEARNERSHIP',
    status: 'ACTIVE',
    createdAt: _daysAgo(8),
    location: 'Remote',
    remote: true,
    requiredSkills: ['SQL', 'JavaScript'],
    requiredFaculty: 'Information Technology',
    expiresAt: _daysAhead(9),
    applicationCount: 61,
    hasApplied: true,
    matchScore: 68,
  ),
  Opportunity(
    id: 'o-3',
    businessId: demoPendingBusiness.id,
    business: demoPendingBusiness,
    title: 'Part-time Data Capturer',
    description: 'Fifteen hours a week, flexible around lectures.',
    type: 'PART_TIME',
    status: 'PENDING',
    createdAt: _hoursAgo(6),
    location: 'Durban',
    matchScore: 40,
  ),
];

final demoApplications = <Application>[
  Application(
    id: 'a-1',
    opportunityId: 'o-2',
    applicantId: demoMe.id,
    applicant: demoMe,
    opportunity: demoOpportunities[1],
    status: 'SHORTLISTED',
    createdAt: _daysAgo(6),
    coverNote: 'I have been running Postgres for the campus library project '
        'and wrote the RLS layer myself.',
  ),
  Application(
    id: 'a-2',
    opportunityId: 'o-1',
    applicantId: demoNaledi.id,
    applicant: demoNaledi,
    opportunity: demoOpportunities[0],
    status: 'APPLIED',
    createdAt: _daysAgo(1),
  ),
];

final demoEvents = <CampusEvent>[
  CampusEvent(
    id: 'e-1',
    title: 'Git & Code Review Workshop',
    eventDate: _daysAhead(4),
    description: 'Two hours, hands-on. Bring a laptop with Git installed.',
    location: 'Lab 3, Richfield Sandton',
    targetRoles: const ['STUDENT'],
  ),
  CampusEvent(
    id: 'e-2',
    title: 'Alumni Career Panel',
    eventDate: _daysAhead(11),
    description: 'Six graduates from the last five years answer anything.',
    virtualLink: 'https://meet.example.com/rtc-alumni',
    targetRoles: const ['STUDENT', 'ALUMNI'],
  ),
  CampusEvent(
    id: 'e-3',
    title: 'Richfield Hackathon 2026 — Campus Round',
    eventDate: DateTime(2026, 9, 15, 8),
    description: 'Campus round of the national hackathon.',
    location: 'Main Auditorium',
    targetRoles: const ['STUDENT'],
  ),
];

// ─── Profile detail ───────────────────────────────────────────

final demoSkills = <Skill>[
  Skill(
    id: 's-1',
    userId: demoMe.id,
    name: 'Dart',
    verified: true,
    moduleRef: 'Mobile Application Development',
    endorsements: 7,
  ),
  Skill(
    id: 's-2',
    userId: demoMe.id,
    name: 'PostgreSQL',
    verified: true,
    moduleRef: 'Database Systems',
    endorsements: 5,
  ),
  Skill(id: 's-3', userId: demoMe.id, name: 'Flutter', endorsements: 4),
  Skill(id: 's-4', userId: demoMe.id, name: 'Git', endorsements: 3),
  Skill(id: 's-5', userId: demoMe.id, name: 'Python', endorsements: 1),
];

final demoExperience = <WorkExperience>[
  WorkExperience(
    id: 'w-1',
    userId: demoMe.id,
    title: 'Student Assistant — Computer Labs',
    company: 'Richfield College',
    startDate: _daysAgo(400),
    description: 'Ran first-year help desk sessions twice a week.',
  ),
  WorkExperience(
    id: 'w-2',
    userId: demoMe.id,
    title: 'Freelance Web Developer',
    company: 'Self-employed',
    startDate: _daysAgo(700),
    endDate: _daysAgo(420),
    description: 'Built and maintained sites for three local businesses.',
  ),
];

final demoLeaderboard = <LeaderboardEntry>[
  LeaderboardEntry(
    id: demoSipho.id,
    fullName: 'Sipho Khumalo',
    totalPoints: 480,
    course: 'BSc IT (Bachelor of Science in Information Technology)',
    skillCount: 12,
  ),
  LeaderboardEntry(
    id: demoNaledi.id,
    fullName: 'Naledi Dlamini',
    totalPoints: 355,
    course: 'BSc IT (Bachelor of Science in Information Technology)',
    skillCount: 9,
  ),
  LeaderboardEntry(
    id: demoMe.id,
    fullName: 'Thabo Mokoena',
    totalPoints: 310,
    course: 'BSc IT (Bachelor of Science in Information Technology)',
    skillCount: 5,
  ),
  LeaderboardEntry(
    id: demoAisha.id,
    fullName: 'Aisha Patel',
    totalPoints: 95,
    course: 'DIT (Diploma in Information Technology)',
    skillCount: 3,
  ),
];

final demoPointsLedger = <Map<String, dynamic>>[
  {
    'id': 'lp-1',
    'user_id': demoMe.id,
    'points': 15,
    'reason': 'Bounty solved: Advanced Java',
    'created_at': _daysAgo(1).toIso8601String(),
  },
  {
    'id': 'lp-2',
    'user_id': demoMe.id,
    'points': 10,
    'reason': 'Bounty solved: Recursion',
    'created_at': _daysAgo(6).toIso8601String(),
  },
  {
    'id': 'lp-3',
    'user_id': demoMe.id,
    'points': 5,
    'reason': 'Skill endorsed',
    'created_at': _daysAgo(14).toIso8601String(),
  },
];

final demoStudentStats = StudentStats(
  logicPoints: 310,
  posts: 14,
  skills: 5,
  connections: 3,
  profileViews: 128,
  newConnections: 3,
  postReactions: 41,
  viewsByDay: [
    for (var i = 29; i >= 0; i--)
      DailyMetric(date: _daysAgo(i), value: 2 + ((i * 7) % 9)),
  ],
  connectionsByDay: [
    for (var i = 29; i >= 0; i--)
      DailyMetric(date: _daysAgo(i), value: i % 6 == 0 ? 1 : 0),
  ],
  engagementByDay: [
    for (var i = 29; i >= 0; i--)
      DailyMetric(date: _daysAgo(i), value: (i * 3) % 5),
  ],
  myCompleteness: 72,
  programmeAvgCompleteness: 61,
  programmePeerCount: 24,
  mySearchedSkills: [
    SkillCount(skill: 'Flutter', count: 6),
    SkillCount(skill: 'SQL', count: 4),
    SkillCount(skill: 'Python', count: 2),
  ],
);

const demoWantedSkills = [
  SkillCount(skill: 'Flutter', count: 11),
  SkillCount(skill: 'SQL', count: 9),
  SkillCount(skill: 'Python', count: 8),
  SkillCount(skill: 'React', count: 6),
  SkillCount(skill: 'Java', count: 5),
  SkillCount(skill: 'UI/UX Design', count: 4),
];

final demoBusinessStats = BusinessStats(
  pipeline: const [
    ListingPipeline(
      title: 'Junior Flutter Developer (Internship)',
      status: 'ACTIVE',
      applicants: 34,
      reach: 210,
    ),
    ListingPipeline(
      title: 'Backend Learnership — Node & Postgres',
      status: 'ACTIVE',
      applicants: 61,
      reach: 340,
    ),
  ],
  candidateSkills: const [
    CandidateSkill(skill: 'Flutter', count: 22, topCourse: 'BSc IT'),
    CandidateSkill(skill: 'SQL', count: 18, topCourse: 'BSc IT'),
    CandidateSkill(skill: 'JavaScript', count: 9, topCourse: 'Dip. Software Dev'),
  ],
  applicantDemographics: const [
    CategoryCount(label: 'BSc IT · 3rd Year', count: 28),
    CategoryCount(label: 'BSc IT · 2nd Year', count: 15),
    CategoryCount(label: 'Dip. Software Dev · Final Year', count: 9),
  ],
  profileViews: 96,
  viewsByDay: [
    for (var i = 29; i >= 0; i--)
      DailyMetric(date: _daysAgo(i), value: 1 + ((i * 5) % 7)),
  ],
);

const demoAdminStats = AdminStats(
  totalUsers: 486,
  pendingUsers: 7,
  totalPosts: 1249,
  bounties: 213,
  pendingOpportunities: 3,
  openFlags: 2,
);

final demoFlags = <Map<String, dynamic>>[
  {
    'id': 'f-1',
    'reason': 'Sharing a full assignment solution before the due date.',
    'created_at': _hoursAgo(4).toIso8601String(),
    'resolved': false,
    'post_id': 'p-5',
    'reporter': {'id': demoNaledi.id, 'full_name': demoNaledi.fullName},
    'post': {
      'id': 'p-5',
      'content': demoPosts[4].content,
      'author_id': demoBusiness.id,
    },
  },
];

// ─── Derived views ────────────────────────────────────────────

List<Message> demoThread(String otherId) =>
    demoMessages.where((m) => m.inThread(demoMe.id, otherId)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

List<Conversation> demoConversations() {
  final latest = <String, Message>{};
  final unread = <String, int>{};

  final newestFirst = List.of(demoMessages)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  for (final m in newestFirst) {
    final other = m.senderId == demoMe.id ? m.receiverId : m.senderId;
    latest.putIfAbsent(other, () => m);
    if (!m.read && m.receiverId == demoMe.id) {
      unread[other] = (unread[other] ?? 0) + 1;
    }
  }

  return [
    for (final entry in latest.entries)
      Conversation(
        other: _person(entry.key),
        lastMessage: entry.value,
        unread: unread[entry.key] ?? 0,
      ),
  ]..sort((a, b) => b.lastMessage.createdAt.compareTo(a.lastMessage.createdAt));
}

int _unreadNotifications() => demoNotifications.where((n) => !n.read).length;

// ─── Repositories ─────────────────────────────────────────────

class DemoAuthRepository extends AuthRepository {
  const DemoAuthRepository();

  @override
  Stream<AuthState> get changes => const Stream<AuthState>.empty();

  @override
  Future<Profile?> currentProfile() async => demoMe;

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? faculty,
    String? course,
    String? academicYear,
    int? graduationYear,
    String? studentNumber,
    String? companyName,
    String? industry,
  }) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> sendPasswordReset(String email) async {}
}

class DemoPostRepository extends PostRepository {
  const DemoPostRepository();

  @override
  Future<List<Post>> feed({int page = 0, int pageSize = 20}) async =>
      List.of(demoPosts);

  @override
  Future<List<Post>> discover({int page = 0, int pageSize = 20}) async =>
      List.of(demoPosts);

  @override
  Future<List<Post>> bounties({String? faculty}) async {
    final open = demoPosts.where((p) => p.isOpenBounty).toList()
      ..sort((a, b) => b.bountyPoints.compareTo(a.bountyPoints));
    if (faculty == null) return open;
    return open.where((p) => p.author?.faculty == faculty).toList();
  }

  @override
  Future<List<Post>> byAuthor(String userId) async =>
      demoPosts.where((p) => p.authorId == userId).toList();

  @override
  Future<Post> byId(String postId) async =>
      demoPosts.firstWhere((p) => p.id == postId);

  @override
  Future<Post> create({
    required String content,
    String type = 'TEXT',
    String? codeLanguage,
    String? codeSnippet,
    String? videoUrl,
    String? thumbnailUrl,
    bool isBounty = false,
    String? bountyModule,
  }) async {
    final post = Post(
      id: 'p-${DateTime.now().millisecondsSinceEpoch}',
      authorId: demoMe.id,
      author: demoMe,
      type: type,
      content: content.trim(),
      createdAt: DateTime.now(),
      codeLanguage: codeLanguage,
      codeSnippet: codeSnippet,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      isBounty: isBounty,
      // 10 is what trg_posts_guard would set.
      bountyPoints: isBounty ? 10 : 0,
      bountyModule: bountyModule,
    );
    demoPosts.insert(0, post);
    _ping();
    return post;
  }

  @override
  Future<void> delete(String postId) async {
    demoPosts.removeWhere((p) => p.id == postId);
    _ping();
  }

  @override
  Future<String?> toggleReaction(String postId, {String emoji = '👍'}) async {
    final i = demoPosts.indexWhere((p) => p.id == postId);
    if (i < 0) return null;

    final post = demoPosts[i];
    final removing = post.myReaction == emoji;
    demoPosts[i] = post.copyWith(
      reactionCount: post.reactionCount +
          (removing ? -1 : (post.myReaction == null ? 1 : 0)),
      myReaction: removing ? null : emoji,
      clearMyReaction: removing,
    );
    _ping();
    return removing ? null : emoji;
  }

  @override
  Future<List<Comment>> comments(String postId) async =>
      List.of(demoComments[postId] ?? const <Comment>[]);

  @override
  Future<Comment> addComment(
    String postId, {
    required String content,
    String? parentId,
  }) async {
    final comment = Comment(
      id: 'c-${DateTime.now().millisecondsSinceEpoch}',
      postId: postId,
      authorId: demoMe.id,
      author: demoMe,
      content: content.trim(),
      createdAt: DateTime.now(),
      parentId: parentId,
    );
    (demoComments[postId] ??= <Comment>[]).add(comment);

    final i = demoPosts.indexWhere((p) => p.id == postId);
    if (i >= 0) {
      demoPosts[i] =
          demoPosts[i].copyWith(commentCount: demoPosts[i].commentCount + 1);
    }
    _ping();
    return comment;
  }

  @override
  Future<void> deleteComment(String commentId) async {
    for (final list in demoComments.values) {
      list.removeWhere((c) => c.id == commentId);
    }
    _ping();
  }

  @override
  Future<void> acceptSolution(String commentId) async {
    for (final entry in demoComments.entries) {
      final i = entry.value.indexWhere((c) => c.id == commentId);
      if (i < 0) continue;

      final c = entry.value[i];
      entry.value[i] = Comment(
        id: c.id,
        postId: c.postId,
        authorId: c.authorId,
        content: c.content,
        createdAt: c.createdAt,
        author: c.author,
        isSolution: true,
        parentId: c.parentId,
      );

      final p = demoPosts.indexWhere((post) => post.id == entry.key);
      if (p >= 0) demoPosts[p] = demoPosts[p].copyWith(bountySolved: true);
      _ping();
      return;
    }
  }

  @override
  Future<void> flagPost(String postId, String reason) async {}
}

class DemoProfileRepository extends ProfileRepository {
  const DemoProfileRepository();

  @override
  Future<Profile> byId(String userId) async => _person(userId);

  @override
  Future<Profile> update(Profile profile) async => profile;

  @override
  Future<List<Profile>> search(
    String term, {
    String? role,
    int limit = 30,
  }) async {
    final clean = term.trim().toLowerCase();
    return demoPeople
        .where((p) {
          if (p.id == demoMe.id) return false;
          if (role != null && p.role != role) return false;
          if (clean.isEmpty) return true;
          return p.displayName.toLowerCase().contains(clean) ||
              (p.course ?? '').toLowerCase().contains(clean) ||
              (p.bio ?? '').toLowerCase().contains(clean);
        })
        .take(limit)
        .toList();
  }

  @override
  Future<List<Profile>> mentorsFor(Profile me, {int limit = 20}) async =>
      demoPeople.where((p) => p.isAlumni).take(limit).toList();

  @override
  Future<int> logicPoints(String userId) async => demoLeaderboard
      .firstWhere(
        (e) => e.id == userId,
        orElse: () =>
            const LeaderboardEntry(id: '', fullName: '', totalPoints: 0),
      )
      .totalPoints;

  @override
  Future<List<Map<String, dynamic>>> pointsLedger(String userId) async =>
      List.of(demoPointsLedger);

  @override
  Future<void> recordView(String userId) async {}

  @override
  Future<List<Skill>> skills(String userId) async =>
      demoSkills.where((s) => s.userId == userId).toList();

  @override
  Future<void> addSkill(String name, {String? moduleRef}) async {
    demoSkills.add(Skill(
      id: 's-${DateTime.now().millisecondsSinceEpoch}',
      userId: demoMe.id,
      name: name.trim(),
      moduleRef: moduleRef,
    ));
    _ping();
  }

  @override
  Future<void> removeSkill(String skillId) async {
    demoSkills.removeWhere((s) => s.id == skillId);
    _ping();
  }

  @override
  Future<void> endorse(String skillId, {String? note}) async {}

  @override
  Future<List<WorkExperience>> experience(String userId) async =>
      demoExperience.where((w) => w.userId == userId).toList();

  @override
  Future<void> addExperience({
    required String title,
    required String company,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
  }) async {
    demoExperience.insert(
      0,
      WorkExperience(
        id: 'w-${DateTime.now().millisecondsSinceEpoch}',
        userId: demoMe.id,
        title: title.trim(),
        company: company.trim(),
        startDate: startDate,
        endDate: endDate,
        description: description,
      ),
    );
    _ping();
  }

  @override
  Future<void> removeExperience(String id) async {
    demoExperience.removeWhere((w) => w.id == id);
    _ping();
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard({int limit = 25}) async =>
      demoLeaderboard.take(limit).toList();
}

class DemoConnectionRepository extends ConnectionRepository {
  const DemoConnectionRepository();

  @override
  Future<List<Connection>> accepted() async =>
      demoConnections.where((c) => c.isAccepted).toList();

  @override
  Future<List<Connection>> incomingRequests() async => demoConnections
      .where((c) => c.isPending && c.receiverId == demoMe.id)
      .toList();

  @override
  Future<Connection?> between(String otherId) async {
    for (final c in demoConnections) {
      if (c.senderId == otherId || c.receiverId == otherId) return c;
    }
    return null;
  }

  @override
  Future<void> request(String targetId) async {
    demoConnections.add(Connection(
      id: 'cn-${DateTime.now().millisecondsSinceEpoch}',
      senderId: demoMe.id,
      receiverId: targetId,
      sender: demoMe,
      receiver: _person(targetId),
      status: 'PENDING',
      createdAt: DateTime.now(),
    ));
    _ping();
  }

  @override
  Future<void> respond(String connectionId, {required bool accept}) async {
    final i = demoConnections.indexWhere((c) => c.id == connectionId);
    if (i < 0) return;

    final c = demoConnections[i];
    demoConnections[i] = Connection(
      id: c.id,
      senderId: c.senderId,
      receiverId: c.receiverId,
      sender: c.sender,
      receiver: c.receiver,
      status: accept ? 'ACCEPTED' : 'DECLINED',
      createdAt: c.createdAt,
    );
    _ping();
  }

  @override
  Future<void> remove(String connectionId) async {
    demoConnections.removeWhere((c) => c.id == connectionId);
    _ping();
  }
}

class DemoMessageRepository extends MessageRepository {
  const DemoMessageRepository();

  @override
  Future<List<Conversation>> conversations() async => demoConversations();

  @override
  Future<List<Message>> thread(String otherId) async => demoThread(otherId);

  @override
  Future<Message> send(String toId, String content) async {
    final message = Message(
      id: 'm-${DateTime.now().millisecondsSinceEpoch}',
      senderId: demoMe.id,
      receiverId: toId,
      content: content.trim(),
      createdAt: DateTime.now(),
      read: true,
    );
    demoMessages.add(message);
    _ping();
    return message;
  }

  @override
  Future<void> markThreadRead(String otherId) async {
    for (var i = 0; i < demoMessages.length; i++) {
      final m = demoMessages[i];
      if (m.senderId != otherId || m.receiverId != demoMe.id || m.read) {
        continue;
      }
      demoMessages[i] = Message(
        id: m.id,
        senderId: m.senderId,
        receiverId: m.receiverId,
        content: m.content,
        createdAt: m.createdAt,
        read: true,
      );
    }
    _ping();
  }
}

class DemoNotificationRepository extends NotificationRepository {
  const DemoNotificationRepository();

  @override
  Future<List<AppNotification>> list({int limit = 50}) async =>
      demoNotifications.take(limit).toList();

  @override
  Future<int> unreadCount() async => _unreadNotifications();

  @override
  Future<void> markRead(String id) async {
    final i = demoNotifications.indexWhere((n) => n.id == id);
    if (i >= 0) demoNotifications[i] = _asRead(demoNotifications[i]);
    _ping();
  }

  @override
  Future<void> markAllRead() async {
    for (var i = 0; i < demoNotifications.length; i++) {
      demoNotifications[i] = _asRead(demoNotifications[i]);
    }
    _ping();
  }

  @override
  Future<void> remove(String id) async {
    demoNotifications.removeWhere((n) => n.id == id);
    _ping();
  }

  AppNotification _asRead(AppNotification n) => AppNotification(
        id: n.id,
        type: n.type,
        title: n.title,
        createdAt: n.createdAt,
        body: n.body,
        data: n.data,
        read: true,
      );
}

class DemoOpportunityRepository extends OpportunityRepository {
  const DemoOpportunityRepository();

  @override
  Future<List<Opportunity>> browse({String? type}) async => demoOpportunities
      .where((o) => o.isActive && (type == null || o.type == type))
      .toList();

  @override
  Future<List<Opportunity>> matched() async =>
      demoOpportunities.where((o) => o.isActive).toList()
        ..sort((a, b) => (b.matchScore ?? 0).compareTo(a.matchScore ?? 0));

  @override
  Future<List<Opportunity>> mine() async => List.of(demoOpportunities);

  @override
  Future<Opportunity> create({
    required String title,
    required String description,
    required String type,
    String? location,
    bool remote = false,
    List<String> requiredSkills = const [],
    String? requiredFaculty,
    String? requiredYear,
    DateTime? expiresAt,
  }) async {
    final opportunity = Opportunity(
      id: 'o-${DateTime.now().millisecondsSinceEpoch}',
      businessId: demoBusiness.id,
      business: demoBusiness,
      title: title.trim(),
      description: description.trim(),
      type: type,
      // PENDING is what trg_opportunities_guard would force.
      status: 'PENDING',
      createdAt: DateTime.now(),
      location: location,
      remote: remote,
      requiredSkills: requiredSkills,
      requiredFaculty: requiredFaculty,
      requiredYear: requiredYear,
      expiresAt: expiresAt,
    );
    demoOpportunities.insert(0, opportunity);
    _ping();
    return opportunity;
  }

  @override
  Future<void> apply(String opportunityId, {String? coverNote}) async {
    final i = demoOpportunities.indexWhere((o) => o.id == opportunityId);
    if (i >= 0) {
      demoOpportunities[i] = demoOpportunities[i]
          .withMatch(demoOpportunities[i].matchScore ?? 0, applied: true);
    }
    _ping();
  }

  @override
  Future<List<Application>> applicationsFor(String opportunityId) async =>
      demoApplications.where((a) => a.opportunityId == opportunityId).toList();

  @override
  Future<List<Application>> myApplications() async =>
      demoApplications.where((a) => a.applicantId == demoMe.id).toList();

  @override
  Future<void> setApplicationStatus(
    String applicationId,
    String status,
  ) async {}
}

class DemoEventRepository extends EventRepository {
  const DemoEventRepository();

  @override
  Future<List<CampusEvent>> upcoming() async =>
      demoEvents.where((e) => !e.isPast).toList()
        ..sort((a, b) => a.eventDate.compareTo(b.eventDate));

  @override
  Future<List<CampusEvent>> past({int limit = 20}) async =>
      demoEvents.where((e) => e.isPast).take(limit).toList();

  @override
  Future<void> create({
    required String title,
    required DateTime eventDate,
    String? description,
    String? location,
    String? virtualLink,
    List<String>? targetRoles,
  }) async {
    demoEvents.add(CampusEvent(
      id: 'e-${DateTime.now().millisecondsSinceEpoch}',
      title: title.trim(),
      eventDate: eventDate,
      description: description,
      location: location,
      virtualLink: virtualLink,
      targetRoles: targetRoles ?? const [],
    ));
    _ping();
  }

  @override
  Future<void> remove(String id) async {
    demoEvents.removeWhere((e) => e.id == id);
    _ping();
  }
}

class DemoAdminRepository extends AdminRepository {
  const DemoAdminRepository();

  @override
  Future<List<Profile>> users({String? status, String? role}) async =>
      demoPeople.where((p) {
        if (status != null && p.status != status) return false;
        if (role != null && p.role != role) return false;
        return true;
      }).toList();

  @override
  Future<void> setUserStatus(String userId, String status) async {}

  @override
  Future<void> deleteUser(String userId) async {}

  @override
  Future<List<Opportunity>> pendingOpportunities() async =>
      demoOpportunities.where((o) => o.status == 'PENDING').toList();

  @override
  Future<void> setOpportunityStatus(String id, String status) async {}

  @override
  Future<List<Map<String, dynamic>>> openFlags() async => List.of(demoFlags);

  @override
  Future<void> resolveFlag(
    String flagId, {
    String? postId,
    bool hidePost = false,
  }) async {
    demoFlags.removeWhere((f) => f['id'] == flagId);
    _ping();
  }

  @override
  Future<void> confirmEmail(String userId) async {}

  @override
  Future<void> resetPassword(String userId, String newPassword) async {}

  @override
  Future<void> announce({
    required String title,
    required String body,
    List<String>? targetRoles,
  }) async {}

  @override
  Future<AdminStats> stats() async => demoAdminStats;
}

class DemoAnalyticsRepository extends AnalyticsRepository {
  const DemoAnalyticsRepository();

  @override
  Future<StudentStats> forStudent(String userId) async => demoStudentStats;

  @override
  Future<List<SkillCount>> wantedSkills() async => demoWantedSkills;

  @override
  Future<BusinessStats> forBusiness(String userId) async => demoBusinessStats;
}

class DemoStorageRepository extends StorageRepository {
  const DemoStorageRepository();

  @override
  Future<String> upload(File file, {required String bucket}) async =>
      'https://example.invalid/$bucket/${demoMe.id}/demo';

  @override
  Future<String> refreshSignedUrl(String bucket, String path) async =>
      'https://example.invalid/$bucket/$path';

  @override
  Future<void> remove(String bucket, String path) async {}
}

// ─── Overrides ────────────────────────────────────────────────

/// Swapped into the root `ProviderScope` when demo mode is on.
///
/// The last four entries are here because those providers read `db` directly:
/// with Supabase uninitialised, leaving them alone would throw on first build.
final demoOverrides = <Override>[
  authRepoProvider.overrideWithValue(const DemoAuthRepository()),
  profileRepoProvider.overrideWithValue(const DemoProfileRepository()),
  postRepoProvider.overrideWithValue(const DemoPostRepository()),
  connectionRepoProvider.overrideWithValue(const DemoConnectionRepository()),
  messageRepoProvider.overrideWithValue(const DemoMessageRepository()),
  notificationRepoProvider.overrideWithValue(const DemoNotificationRepository()),
  opportunityRepoProvider.overrideWithValue(const DemoOpportunityRepository()),
  eventRepoProvider.overrideWithValue(const DemoEventRepository()),
  adminRepoProvider.overrideWithValue(const DemoAdminRepository()),
  analyticsRepoProvider.overrideWithValue(const DemoAnalyticsRepository()),
  storageRepoProvider.overrideWithValue(const DemoStorageRepository()),

  isSignedInProvider.overrideWithValue(true),
  myProfileProvider.overrideWith((ref) async => demoMe),
  threadProvider.overrideWith((ref, String otherId) async* {
    yield demoThread(otherId);
    yield* _bus.stream.map((_) => demoThread(otherId));
  }),
  unreadCountProvider.overrideWith((ref) async* {
    yield _unreadNotifications();
    yield* _bus.stream.map((_) => _unreadNotifications());
  }),
];
