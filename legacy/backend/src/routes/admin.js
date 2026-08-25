const express = require('express');
const router = express.Router();
const { supabaseAdmin } = require('../supabaseClient');
const { authenticate, requireRole } = require('../middleware/auth');

const adminOnly = [authenticate, requireRole('ADMIN')];

// ─── User Management ─────────────────────────────────────────
router.get('/users', ...adminOnly, async (req, res) => {
  const { role, status, search } = req.query;
  let query = supabaseAdmin
    .from('profiles')
    .select('*')
    .order('created_at', { ascending: false });
  if (role) query = query.eq('role', role);
  if (status) query = query.eq('status', status);
  if (search) query = query.ilike('full_name', `%${search}%`);
  const { data, error } = await query;
  if (error) return res.status(400).json({ error: error.message });
  res.json({ users: data || [] });
});

router.patch('/users/:id/status', ...adminOnly, async (req, res) => {
  const { status } = req.body; // ACTIVE, SUSPENDED, REJECTED
  const { data, error } = await supabaseAdmin
    .from('profiles')
    .update({ status })
    .eq('id', req.params.id)
    .select().single();
  if (error) return res.status(400).json({ error: error.message });

  // Notify the user
  const notifTitle = status === 'ACTIVE' ? 'Account approved!' : `Account ${status.toLowerCase()}`;
  await supabaseAdmin.from('notifications').insert({
    user_id: req.params.id,
    type: 'ACCOUNT_APPROVED',
    title: notifTitle,
    body: status === 'ACTIVE' ? 'Your account has been approved. Welcome!' : 'Your account status has changed.',
  });
  req.app.get('io')?.to(req.params.id).emit('notification', { type: 'ACCOUNT_APPROVED', status });

  res.json({ user: data });
});

router.delete('/users/:id', ...adminOnly, async (req, res) => {
  await supabaseAdmin.auth.admin.deleteUser(req.params.id);
  res.json({ message: 'User deleted' });
});

// ─── Content Moderation ───────────────────────────────────────
router.get('/flags', ...adminOnly, async (req, res) => {
  const { data } = await supabaseAdmin
    .from('content_flags')
    .select(`
      *,
      reporter:profiles!reporter_id(id, full_name),
      post:posts(*),
      comment:comments(*)
    `)
    .eq('resolved', false)
    .order('created_at', { ascending: false });
  res.json({ flags: data || [] });
});

router.patch('/flags/:id/resolve', ...adminOnly, async (req, res) => {
  const { action } = req.body; // 'REMOVE_CONTENT' or 'DISMISS'
  const { data: flag } = await supabaseAdmin.from('content_flags').select('*').eq('id', req.params.id).single();

  if (action === 'REMOVE_CONTENT') {
    if (flag?.post_id) await supabaseAdmin.from('posts').update({ is_flagged: true }).eq('id', flag.post_id);
    if (flag?.comment_id) await supabaseAdmin.from('comments').update({ is_flagged: true }).eq('id', flag.comment_id);
  }

  await supabaseAdmin.from('content_flags').update({ resolved: true, resolved_by: req.user.id }).eq('id', req.params.id);
  res.json({ message: 'Flag resolved' });
});

// ─── Opportunity Approval ─────────────────────────────────────
router.patch('/opportunities/:id', ...adminOnly, async (req, res) => {
  const { status } = req.body; // ACTIVE or REJECTED
  const { data, error } = await supabaseAdmin
    .from('opportunities')
    .update({ status })
    .eq('id', req.params.id)
    .select().single();
  if (error) return res.status(400).json({ error: error.message });

  if (status === 'ACTIVE') {
    // Smart matching: notify eligible students
    const { data: allStudents } = await supabaseAdmin
      .from('profiles')
      .select('id, skills(name), faculty, academic_year')
      .eq('role', 'STUDENT')
      .eq('status', 'ACTIVE');

    const opp = data;
    const eligible = (allStudents || []).filter(s => {
      const match = (!opp.required_faculty || s.faculty === opp.required_faculty) &&
        (!opp.required_year || s.academic_year === opp.required_year);
      if (!match) return false;
      if (!opp.required_skills?.length) return true;
      const sSkills = (s.skills || []).map(sk => sk.name.toLowerCase());
      return opp.required_skills.some(rs => sSkills.includes(rs.toLowerCase()));
    });

    if (eligible.length) {
      await supabaseAdmin.from('notifications').insert(
        eligible.map(s => ({
          user_id: s.id,
          type: 'OPPORTUNITY_MATCH',
          title: 'New opportunity matches your profile!',
          body: opp.title,
          data: { opportunity_id: opp.id },
        }))
      );
      eligible.forEach(s => {
        req.app.get('io')?.to(s.id).emit('notification', { type: 'OPPORTUNITY_MATCH' });
      });
    }
  }

  res.json({ opportunity: data });
});

// ─── Announcements ────────────────────────────────────────────
router.post('/announcements', ...adminOnly, async (req, res) => {
  const { title, body, target_roles } = req.body;
  const { data, error } = await supabaseAdmin
    .from('announcements')
    .insert({ admin_id: req.user.id, title, body, target_roles: target_roles || null })
    .select().single();
  if (error) return res.status(400).json({ error: error.message });

  // Push to matching users
  let uQuery = supabaseAdmin.from('profiles').select('id').eq('status', 'ACTIVE');
  if (target_roles?.length) uQuery = uQuery.in('role', target_roles);
  const { data: targets } = await uQuery;

  if (targets?.length) {
    await supabaseAdmin.from('notifications').insert(
      targets.map(t => ({
        user_id: t.id,
        type: 'ADMIN_ANNOUNCEMENT',
        title,
        body,
        data: { announcement_id: data.id },
      }))
    );
    req.app.get('io')?.emit('announcement', { title, body, target_roles });
  }

  res.status(201).json({ announcement: data });
});

// ─── Platform Analytics ───────────────────────────────────────
router.get('/analytics', ...adminOnly, async (req, res) => {
  const [
    { count: totalUsers },
    { data: byRole },
    { data: recentRegistrations },
    { count: totalPosts },
    { count: pendingFlags },
    { count: pendingOpps },
  ] = await Promise.all([
    supabaseAdmin.from('profiles').select('*', { count: 'exact', head: true }),
    supabaseAdmin.from('profiles').select('role').then(r => ({ data: r.data })),
    supabaseAdmin.from('profiles').select('created_at, role')
      .gte('created_at', new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString()),
    supabaseAdmin.from('posts').select('*', { count: 'exact', head: true }),
    supabaseAdmin.from('content_flags').select('*', { count: 'exact', head: true }).eq('resolved', false),
    supabaseAdmin.from('opportunities').select('*', { count: 'exact', head: true }).eq('status', 'PENDING'),
  ]);

  const roleCounts = (byRole || []).reduce((acc, p) => {
    acc[p.role] = (acc[p.role] || 0) + 1;
    return acc;
  }, {});

  res.json({
    total_users: totalUsers,
    role_counts: roleCounts,
    recent_registrations: recentRegistrations || [],
    total_posts: totalPosts,
    pending_flags: pendingFlags,
    pending_opportunities: pendingOpps,
  });
});

module.exports = router;