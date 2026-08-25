const express = require('express');
const router = express.Router();
const { supabaseAdmin } = require('../supaBaseClient');
const { authenticate, requireRole } = require('../middleware/auth');

// GET /api/posts/feed — personalised feed
router.get('/feed', authenticate, async (req, res) => {
  const { page = 1, limit = 20 } = req.query;
  const offset = (page - 1) * limit;

  // Get connection IDs
  const { data: conns } = await supabaseAdmin
    .from('connections')
    .select('sender_id, receiver_id')
    .or(`sender_id.eq.${req.user.id},receiver_id.eq.${req.user.id}`)
    .eq('status', 'ACCEPTED');

  const connectedIds = (conns || []).map(c =>
    c.sender_id === req.user.id ? c.receiver_id : c.sender_id
  );
  connectedIds.push(req.user.id);

  let query = supabaseAdmin
    .from('posts')
    .select(`
      *,
      author:profiles!author_id(id, full_name, avatar_url, role, course),
      post_reactions(count),
      comments(count)
    `)
    .eq('is_flagged', false)
    .in('author_id', connectedIds)
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  const { data, error } = await query;
  if (error) return res.status(400).json({ error: error.message });
  res.json({ posts: data });
});

// GET /api/posts/bounties — bounty board
router.get('/bounties', authenticate, async (req, res) => {
  const { faculty } = req.query;
  let query = supabaseAdmin
    .from('posts')
    .select(`
      *,
      author:profiles!author_id(id, full_name, avatar_url, faculty, course)
    `)
    .eq('is_bounty', true)
    .eq('bounty_solved', false)
    .eq('is_flagged', false)
    .order('bounty_points', { ascending: false });

  const { data, error } = await query;
  if (error) return res.status(400).json({ error: error.message });
  res.json({ bounties: data });
});

// GET /api/posts/:id
router.get('/:id', authenticate, async (req, res) => {
  const { data, error } = await supabaseAdmin
    .from('posts')
    .select(`
      *,
      author:profiles!author_id(id, full_name, avatar_url, role),
      post_reactions(*),
      comments(*, author:profiles!author_id(id, full_name, avatar_url))
    `)
    .eq('id', req.params.id)
    .single();
  if (error) return res.status(404).json({ error: 'Post not found' });
  res.json({ post: data });
});

// POST /api/posts
router.post('/', authenticate, async (req, res) => {
  const {
    type, content, code_language, code_snippet,
    video_url, thumbnail_url,
    is_bounty, bounty_module
  } = req.body;

  if (!content) return res.status(400).json({ error: 'Content required' });

  const { data, error } = await supabaseAdmin
    .from('posts')
    .insert({
      author_id: req.user.id,
      type: type || 'TEXT',
      content,
      code_language: code_language || null,
      code_snippet: code_snippet || null,
      video_url: video_url || null,
      thumbnail_url: thumbnail_url || null,
      is_bounty: is_bounty || false,
      bounty_points: is_bounty ? 10 : 0,
      bounty_module: bounty_module || null,
    })
    .select()
    .single();

  if (error) return res.status(400).json({ error: error.message });

  // Broadcast to followers via socket
  const io = req.app.get('io');
  io?.emit('new_post', { post: data });

  res.status(201).json({ post: data });
});

// POST /api/posts/:id/react
router.post('/:id/react', authenticate, async (req, res) => {
  const { emoji = '👍' } = req.body;
  const { data: existing } = await supabaseAdmin
    .from('post_reactions')
    .select('id')
    .eq('post_id', req.params.id)
    .eq('user_id', req.user.id)
    .single();

  if (existing) {
    await supabaseAdmin.from('post_reactions').delete().eq('id', existing.id);
    return res.json({ message: 'Reaction removed' });
  }

  const { data, error } = await supabaseAdmin
    .from('post_reactions')
    .insert({ post_id: req.params.id, user_id: req.user.id, emoji })
    .select().single();
  if (error) return res.status(400).json({ error: error.message });

  // Notify post author
  const { data: post } = await supabaseAdmin.from('posts').select('author_id').eq('id', req.params.id).single();
  if (post && post.author_id !== req.user.id) {
    await supabaseAdmin.from('notifications').insert({
      user_id: post.author_id,
      type: 'POST_REACTION',
      title: 'Someone reacted to your post',
      body: `${req.user.full_name} reacted ${emoji} to your post.`,
      data: { post_id: req.params.id, reactor_id: req.user.id },
    });
    req.app.get('io')?.to(post.author_id).emit('notification', { type: 'POST_REACTION' });
  }

  res.status(201).json({ reaction: data });
});

// POST /api/posts/:id/comments
router.post('/:id/comments', authenticate, async (req, res) => {
  const { content, parent_id, is_solution } = req.body;
  if (!content) return res.status(400).json({ error: 'Content required' });

  const { data, error } = await supabaseAdmin
    .from('comments')
    .insert({
      post_id: req.params.id,
      author_id: req.user.id,
      content,
      parent_id: parent_id || null,
      is_solution: is_solution || false,
    })
    .select()
    .single();
  if (error) return res.status(400).json({ error: error.message });

  // If marking as bounty solution, award logic points
  if (is_solution) {
    const { data: post } = await supabaseAdmin.from('posts').select('*').eq('id', req.params.id).single();
    if (post?.is_bounty && !post.bounty_solved && post.author_id !== req.user.id) {
      await supabaseAdmin.from('posts').update({ bounty_solved: true }).eq('id', req.params.id);
      await supabaseAdmin.from('logic_points').insert({
        user_id: req.user.id,
        amount: post.bounty_points,
        reason: `Solved bounty: ${post.content.substring(0, 50)}`,
        post_id: req.params.id,
      });
      await supabaseAdmin.from('notifications').insert({
        user_id: req.user.id,
        type: 'BOUNTY_SOLVED',
        title: `You earned ${post.bounty_points} Logic Points!`,
        body: 'Your answer was accepted as the bounty solution.',
      });
      req.app.get('io')?.to(req.user.id).emit('notification', { type: 'BOUNTY_SOLVED', points: post.bounty_points });
    }
  }

  res.status(201).json({ comment: data });
});

// DELETE /api/posts/:id
router.delete('/:id', authenticate, async (req, res) => {
  const { data: post } = await supabaseAdmin.from('posts').select('author_id').eq('id', req.params.id).single();
  if (!post) return res.status(404).json({ error: 'Post not found' });
  if (post.author_id !== req.user.id && req.user.role !== 'ADMIN') {
    return res.status(403).json({ error: 'Unauthorized' });
  }
  await supabaseAdmin.from('posts').delete().eq('id', req.params.id);
  res.json({ message: 'Post deleted' });
});

module.exports = router;