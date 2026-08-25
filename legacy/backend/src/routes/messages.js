const express = require('express');
const router = express.Router();
const { supabaseAdmin } = require('../supabaseClient');
const { authenticate } = require('../middleware/auth');

// GET /api/messages/conversations
router.get('/conversations', authenticate, async (req, res) => {
  const { data } = await supabaseAdmin
    .from('messages')
    .select(`
      *,
      sender:profiles!sender_id(id, full_name, avatar_url),
      receiver:profiles!receiver_id(id, full_name, avatar_url)
    `)
    .or(`sender_id.eq.${req.user.id},receiver_id.eq.${req.user.id}`)
    .order('created_at', { ascending: false });

  // Deduplicate into unique conversations
  const seen = new Set();
  const convos = (data || []).filter(m => {
    const key = [m.sender_id, m.receiver_id].sort().join('_');
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  res.json({ conversations: convos });
});

// GET /api/messages/:userId — thread with a user
router.get('/:userId', authenticate, async (req, res) => {
  const { data } = await supabaseAdmin
    .from('messages')
    .select(`
      *,
      sender:profiles!sender_id(id, full_name, avatar_url)
    `)
    .or(
      `and(sender_id.eq.${req.user.id},receiver_id.eq.${req.params.userId}),` +
      `and(sender_id.eq.${req.params.userId},receiver_id.eq.${req.user.id})`
    )
    .order('created_at', { ascending: true });

  // Mark messages as read
  await supabaseAdmin.from('messages')
    .update({ read: true })
    .eq('sender_id', req.params.userId)
    .eq('receiver_id', req.user.id);

  res.json({ messages: data || [] });
});

// POST /api/messages — send a message
router.post('/', authenticate, async (req, res) => {
  const { receiver_id, content } = req.body;
  if (!receiver_id || !content) return res.status(400).json({ error: 'receiver_id and content required' });

  // Verify connection
  const { data: conn } = await supabaseAdmin
    .from('connections')
    .select('id')
    .or(
      `and(sender_id.eq.${req.user.id},receiver_id.eq.${receiver_id}),` +
      `and(sender_id.eq.${receiver_id},receiver_id.eq.${req.user.id})`
    )
    .eq('status', 'ACCEPTED')
    .single();

  if (!conn) return res.status(403).json({ error: 'You must be connected to message this user' });

  const { data, error } = await supabaseAdmin
    .from('messages')
    .insert({ sender_id: req.user.id, receiver_id, content })
    .select().single();

  if (error) return res.status(400).json({ error: error.message });

  // Real-time via socket
  const io = req.app.get('io');
  io?.to(receiver_id).emit('new_message', { message: data });

  // Notification
  await supabaseAdmin.from('notifications').insert({
    user_id: receiver_id,
    type: 'NEW_MESSAGE',
    title: `New message from ${req.user.full_name}`,
    body: content.substring(0, 100),
    data: { sender_id: req.user.id },
  });

  res.status(201).json({ message: data });
});

module.exports = router;