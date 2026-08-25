const jwt = require('jsonwebtoken');
const { supabaseAdmin } = require('../supaBaseClient');

/**
 * Verifies the Supabase JWT from the Authorization header.
 * Attaches req.user = { id, role, status } on success.
 */
const authenticate = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Missing or invalid Authorization header' });
  }

  const token = authHeader.split(' ')[1];
  try {
    // Verify with Supabase (this validates the Supabase JWT)
    const { data: { user }, error } = await supabaseAdmin.auth.getUser(token);
    if (error || !user) throw new Error('Invalid token');

    // Fetch profile for role/status
    const { data: profile, error: pErr } = await supabaseAdmin
      .from('profiles')
      .select('id, role, status, full_name')
      .eq('id', user.id)
      .single();

    if (pErr || !profile) throw new Error('Profile not found');
    if (profile.status === 'SUSPENDED') return res.status(403).json({ error: 'Account suspended' });
    if (profile.status === 'PENDING' && profile.role !== 'STUDENT') {
      return res.status(403).json({ error: 'Account pending admin approval' });
    }

    req.user = profile;
    req.token = token;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'Unauthorized: ' + err.message });
  }
};

/**
 * Role guard factory — use after authenticate()
 * requireRole('ADMIN') or requireRole(['ADMIN','STUDENT'])
 */
const requireRole = (roles) => (req, res, next) => {
  const allowed = Array.isArray(roles) ? roles : [roles];
  if (!allowed.includes(req.user.role)) {
    return res.status(403).json({ error: 'Insufficient permissions' });
  }
  next();
};

module.exports = { authenticate, requireRole };