// ─── connections.js ──────────────────────────────────────────
const express = require('express');
const router = express.Router();
const { supabaseAdmin } = require('../supabaseClient');
const { authenticate } = require('../middleware/auth');

router.post('/request/:targetId', authenticate, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('connections')
    .insert({ sender_id: req.user.id, receiver_id: req.params.targetId })
    .select().single();
  if (error) return res.status(400).json({ error: error.message });

  await supabaseAdmin.from('notifications').insert({
    user_id: req.params.targetId,
    type: 'CONNECTION_REQUEST',
    title: 'New connection request',
    body: `${req.user.full_name} wants to connect with you.`,
    data: { sender_id: req.user.id, connection_id: data.id },
  });
  req.app.get('io')?.to(req.params.targetId).emit('notification', { type: 'CONNECTION_REQUEST' });
  res.status(201).json({ connection: data });
});

router.patch('/:id', authenticate, async (req, res) => {
  const { status } = req.body; // ACCEPTED or DECLINED
  const { data, error } = await supabaseAdmin
    .from('connections')
    .update({ status })
    .eq('id', req.params.id)
    .eq('receiver_id', req.user.id)
    .select().single();
  if (error) return res.status(400).json({ error: error.message });

  if (status === 'ACCEPTED') {
    await supabaseAdmin.from('notifications').insert({
      user_id: data.sender_id,
      type: 'CONNECTION_ACCEPTED',
      title: 'Connection accepted!',
      body: `${req.user.full_name} accepted your connection request.`,
    });
    req.app.get('io')?.to(data.sender_id).emit('notification', { type: 'CONNECTION_ACCEPTED' });
  }
  res.json({ connection: data });
});

router.get('/my', authenticate, async (req, res) => {
  const { data } = await supabaseAdmin
    .from('connections')
    .select(`
      *,
      sender:profiles!sender_id(id, full_name, avatar_url, role),
      receiver:profiles!receiver_id(id, full_name, avatar_url, role)
    `)
    .or(`sender_id.eq.${req.user.id},receiver_id.eq.${req.user.id}`)
    .eq('status', 'ACCEPTED');
  res.json({ connections: data || [] });
});

router.get('/pending', authenticate, async (req, res) => {
  const { data } = await supabaseAdmin
    .from('connections')
    .select(`*, sender:profiles!sender_id(id, full_name, avatar_url, role)`)
    .eq('receiver_id', req.user.id)
    .eq('status', 'PENDING');
  res.json({ requests: data || [] });
});

module.exports = router;