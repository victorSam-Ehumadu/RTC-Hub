// ─── events.js ───────────────────────────────────────────────
const express = require('express');
const router = express.Router();
const { supabaseAdmin } = require('../supabaseClient');
const { authenticate, requireRole } = require('../middleware/auth');

router.get('/', authenticate, async (req, res) => {
  const { data } = await supabaseAdmin
    .from('events')
    .select('*')
    .order('event_date', { ascending: true });
  res.json({ events: data || [] });
});

router.post('/', authenticate, requireRole('ADMIN'), async (req, res) => {
  const { title, description, event_date, location, virtual_link, target_roles } = req.body;
  const { data, error } = await supabaseAdmin.from('events').insert({
    admin_id: req.user.id, title, description, event_date, location, virtual_link,
    target_roles: target_roles || null,
  }).select().single();
  if (error) return res.status(400).json({ error: error.message });
  res.status(201).json({ event: data });
});

router.patch('/:id', authenticate, requireRole('ADMIN'), async (req, res) => {
  const { data, error } = await supabaseAdmin.from('events').update(req.body).eq('id', req.params.id).select().single();
  if (error) return res.status(400).json({ error: error.message });
  res.json({ event: data });
});

router.delete('/:id', authenticate, requireRole('ADMIN'), async (req, res) => {
  await supabaseAdmin.from('events').delete().eq('id', req.params.id);
  res.json({ message: 'Event deleted' });
});

module.exports = router;