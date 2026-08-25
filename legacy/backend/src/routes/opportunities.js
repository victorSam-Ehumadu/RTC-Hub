const express = require('express');
const router = express.Router();
const { supabaseAdmin } = require('../supabaseClient');
const { authenticate, requireRole } = require('../middleware/auth');
const { matchOpportunityToStudents } = require('../services/matchingService');

// GET /api/opportunities — browse (students/alumni see approved)
router.get('/', authenticate, async (req, res) => {
  const { type, faculty, search } = req.query;
  let query = supabaseAdmin
    .from('opportunities')
    .select(`*, business:profiles!business_id(id, full_name, company_name, avatar_url)`)
    .order('created_at', { ascending: false });

  if (req.user.role === 'BUSINESS') {
    query = query.eq('business_id', req.user.id);
  } else {
    query = query.eq('status', 'ACTIVE');
  }

  if (type) query = query.eq('type', type);
  if (faculty) query = query.eq('required_faculty', faculty);
  if (search) query = query.ilike('title', `%${search}%`);

  const { data, error } = await query;
  if (error) return res.status(400).json({ error: error.message });
  res.json({ opportunities: data || [] });
});

// GET /api/opportunities/matched — smart matches for current student
router.get('/matched', authenticate, requireRole(['STUDENT', 'ALUMNI']), async (req, res) => {
  const { data: profile } = await supabaseAdmin
    .from('profiles')
    .select('*, skills(name)')
    .eq('id', req.user.id)
    .single();

  const userSkills = (profile?.skills || []).map(s => s.name.toLowerCase());
  const userFaculty = profile?.faculty;
  const userYear = profile?.academic_year;

  const { data: opps } = await supabaseAdmin
    .from('opportunities')
    .select('*')
    .eq('status', 'ACTIVE');

  const matched = (opps || [])
    .map(opp => {
      let score = 0;
      if (opp.required_faculty === userFaculty) score += 30;
      if (opp.required_year === userYear) score += 20;
      const oppSkills = (opp.required_skills || []).map(s => s.toLowerCase());
      const overlap = oppSkills.filter(s => userSkills.includes(s)).length;
      score += overlap * 10;
      return { ...opp, match_score: score };
    })
    .filter(o => o.match_score > 0)
    .sort((a, b) => b.match_score - a.match_score);

  res.json({ opportunities: matched });
});

// POST /api/opportunities — business posts an opportunity
router.post('/', authenticate, requireRole('BUSINESS'), async (req, res) => {
  const { title, description, type, location, remote, required_skills, required_faculty, required_year, expires_at } = req.body;
  if (!title || !description || !type) return res.status(400).json({ error: 'title, description, type required' });

  const { data, error } = await supabaseAdmin
    .from('opportunities')
    .insert({
      business_id: req.user.id,
      title, description, type, location,
      remote: remote || false,
      required_skills: required_skills || [],
      required_faculty: required_faculty || null,
      required_year: required_year || null,
      expires_at: expires_at || null,
      status: 'PENDING',
    })
    .select().single();
  if (error) return res.status(400).json({ error: error.message });

  // Notify admins
  const { data: admins } = await supabaseAdmin.from('profiles').select('id').eq('role', 'ADMIN');
  if (admins?.length) {
    await supabaseAdmin.from('notifications').insert(
      admins.map(a => ({
        user_id: a.id,
        type: 'OPPORTUNITY_MATCH',
        title: 'New opportunity pending approval',
        body: `${req.user.company_name || req.user.full_name} posted: ${title}`,
        data: { opportunity_id: data.id },
      }))
    );
  }

  res.status(201).json({ opportunity: data });
});

// POST /api/opportunities/:id/apply
router.post('/:id/apply', authenticate, requireRole(['STUDENT', 'ALUMNI']), async (req, res) => {
  const { cover_note } = req.body;
  const { data, error } = await supabaseAdmin
    .from('opportunity_applications')
    .insert({ opportunity_id: req.params.id, applicant_id: req.user.id, cover_note })
    .select().single();
  if (error) return res.status(400).json({ error: error.message });
  res.status(201).json({ application: data });
});

// GET /api/opportunities/:id/applications — business sees applicants
router.get('/:id/applications', authenticate, requireRole(['BUSINESS', 'ADMIN']), async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('opportunity_applications')
    .select(`
      *,
      applicant:profiles!applicant_id(id, full_name, avatar_url, course, faculty, academic_year, cv_url, skills(*))
    `)
    .eq('opportunity_id', req.params.id);
  if (error) return res.status(400).json({ error: error.message });
  res.json({ applications: data || [] });
});

module.exports = router;