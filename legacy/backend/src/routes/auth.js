const express = require('express');
const router = express.Router();
const { supabase, supabaseAdmin } = require('../supaBaseClient');
const { authenticate, requireRole } = require('../middleware/auth');

// ─── SIGNUP ──────────────────────────────────────────────────
router.post('/signup', async (req, res) => {
  const {
    email, password, full_name, role,
    faculty, course, academic_year, graduation_year,
    company_name, industry, verification_photo_url,
    student_number
  } = req.body;

  if (!email || !password || !full_name || !role) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  // Domain enforcement for students
  if (role === 'STUDENT') {
    const clean = email.trim().toLowerCase();
    if (!clean.endsWith('@my.richfield.ac.za') && !clean.endsWith('@richfield.ac.za')) {
      return res.status(400).json({ error: 'Student registration requires @richfield.ac.za email' });
    }
    const prefix = clean.split('@')[0];
    if (!/^\d{9}$/.test(prefix)) {
      return res.status(400).json({ error: 'Student email prefix must be exactly 9 digits' });
    }
  }

  // Create auth user
  const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
    email: email.trim().toLowerCase(),
    password,
    email_confirm: true,
  });
  if (authError) return res.status(400).json({ error: authError.message });

  // Determine initial status
  const status = (role === 'STUDENT') ? 'ACTIVE' : 'PENDING';

  // Insert profile
  const { error: profileError } = await supabaseAdmin.from('profiles').insert({
    id: authData.user.id,
    email: email.trim().toLowerCase(),
    full_name: full_name.trim(),
    role,
    status,
    faculty: faculty || null,
    course: course || null,
    academic_year: academic_year || null,
    graduation_year: graduation_year ? parseInt(graduation_year) : null,
    company_name: company_name || null,
    industry: industry || null,
    student_number: student_number || null,
    verification_photo_url: verification_photo_url || null,
  });

  if (profileError) {
    // Rollback auth user
    await supabaseAdmin.auth.admin.deleteUser(authData.user.id);
    return res.status(400).json({ error: profileError.message });
  }

  // Create onboarding record
  await supabaseAdmin.from('onboarding_progress').insert({ user_id: authData.user.id });

  // Notify admins of pending accounts
  if (status === 'PENDING') {
    const { data: admins } = await supabaseAdmin
      .from('profiles').select('id').eq('role', 'ADMIN');
    if (admins?.length) {
      await supabaseAdmin.from('notifications').insert(
        admins.map(a => ({
          user_id: a.id,
          type: 'ACCOUNT_APPROVED',
          title: 'New account pending approval',
          body: `${full_name} registered as ${role} and needs review.`,
          data: { pending_user_id: authData.user.id },
        }))
      );
    }
  }

  res.status(201).json({
    message: status === 'ACTIVE'
      ? 'Registration successful!'
      : 'Registration submitted. Awaiting admin approval.',
    user: { id: authData.user.id, email, role, status },
  });
});

// ─── LOGIN ────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'Email and password required' });

  const { data, error } = await supabase.auth.signInWithPassword({
    email: email.trim().toLowerCase(),
    password,
  });
  if (error) return res.status(401).json({ error: 'Invalid credentials' });

  // Fetch profile
  const { data: profile } = await supabaseAdmin
    .from('profiles')
    .select('*')
    .eq('id', data.user.id)
    .single();

  if (!profile) return res.status(404).json({ error: 'Profile not found' });
  if (profile.status === 'SUSPENDED') return res.status(403).json({ error: 'Account suspended' });

  res.json({
    session: data.session,
    user: profile,
  });
});

// ─── LOGOUT ───────────────────────────────────────────────────
router.post('/logout', authenticate, async (req, res) => {
  await supabase.auth.signOut();
  res.json({ message: 'Logged out' });
});

// ─── ME ───────────────────────────────────────────────────────
router.get('/me', authenticate, async (req, res) => {
  const { data: profile } = await supabaseAdmin
    .from('profiles')
    .select('*')
    .eq('id', req.user.id)
    .single();
  res.json({ user: profile });
});

// ─── ADMIN: provision an admin account (protected — service role) ──
// Call this once manually or via a trusted script with SUPABASE_SERVICE_ROLE_KEY
router.post('/provision-admin', async (req, res) => {
  const secret = req.headers['x-provision-secret'];
  if (secret !== process.env.ADMIN_PROVISION_SECRET) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const { email, password, full_name } = req.body;
  const { data: authData, error } = await supabaseAdmin.auth.admin.createUser({
    email, password, email_confirm: true,
  });
  if (error) return res.status(400).json({ error: error.message });

  await supabaseAdmin.from('profiles').insert({
    id: authData.user.id,
    email,
    full_name,
    role: 'ADMIN',
    status: 'ACTIVE',
  });

  res.status(201).json({ message: 'Admin provisioned', id: authData.user.id });
});

module.exports = router;