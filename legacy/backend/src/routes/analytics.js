const express = require('express');
const router = express.Router();
const { supabaseAdmin } = require('../supabaseClient');
const { authenticate, requireRole } = require('../middleware/auth');

// Student analytics
router.get('/student', authenticate, requireRole(['STUDENT', 'ALUMNI']), async (req, res) => {
  const userId = req.user.id;
  const [
    { data: analytics },
    { data: connections },
    { data: posts },
    { data: profile },
    { data: points },
  ] = await Promise.all([
    supabaseAdmin.from('profile_analytics').select('*').eq('user_id', userId).order('date', { ascending: false }).limit(30),
    supabaseAdmin.from('connections').select('id').or(`sender_id.eq.${userId},receiver_id.eq.${userId}`).eq('status', 'ACCEPTED'),
    supabaseAdmin.from('posts').select('id, post_reactions(count), comments(count)').eq('author_id', userId),
    supabaseAdmin.from('profiles').select('profile_completeness, faculty, course').eq('id', userId).single(),
    supabaseAdmin.from('logic_points').select('amount').eq('user_id', userId),
  ]);

  const totalPoints = (points || []).reduce((s, p) => s + p.amount, 0);
  res.json({
    profile_views: analytics || [],
    connection_count: connections?.length || 0,
    post_count: posts?.length || 0,
    total_reactions: (posts || []).reduce((s, p) => s + (p.post_reactions?.[0]?.count || 0), 0),
    profile_completeness: profile?.data?.profile_completeness || 0,
    logic_points: totalPoints,
  });
});

// Business analytics
router.get('/business', authenticate, requireRole('BUSINESS'), async (req, res) => {
  const { data: opps } = await supabaseAdmin
    .from('opportunities')
    .select(`
      id, title, type, created_at,
      opportunity_applications(
        id, status, created_at,
        applicant:profiles!applicant_id(faculty, academic_year, course, skills(name))
      )
    `)
    .eq('business_id', req.user.id);

  const pipeline = (opps || []).map(o => ({
    id: o.id,
    title: o.title,
    type: o.type,
    total_applicants: o.opportunity_applications?.length || 0,
    by_status: o.opportunity_applications?.reduce((acc, a) => {
      acc[a.status] = (acc[a.status] || 0) + 1; return acc;
    }, {}),
    faculty_breakdown: o.opportunity_applications?.reduce((acc, a) => {
      const f = a.applicant?.faculty || 'UNKNOWN';
      acc[f] = (acc[f] || 0) + 1; return acc;
    }, {}),
  }));

  res.json({ pipeline });
});

// Leaderboard
router.get('/leaderboard', authenticate, async (req, res) => {
  const { faculty } = req.query;
  let query = supabaseAdmin.from('leaderboard').select('*').limit(20);
  if (faculty) query = query.eq('faculty', faculty);
  const { data } = await query;
  res.json({ leaderboard: data || [] });
});

module.exports = router;