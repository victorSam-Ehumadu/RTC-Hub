const express = require('express');
const router = express.Router();
const { supabase } = require('../../server');

// GET: Fetching all posts with profile info
router.get('/', async (req, res) => {
    try {
        const { data, error } = await supabase
            .from('posts')
            .select('*, profiles(full_name, logic_points)')
            .order('created_at', { ascending: false });

        if (error) throw error;
        res.status(200).json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// POST: Create a new post
router.post('/', async (req, res) => {
    try {
        // author_id comes from the logged-in user's ID
        const { author_id, content, code, type, language } = req.body;

        if (!content || !author_id) {
            return res.status(400).json({ error: "Missing content or author_id" });
        }

        const { data, error } = await supabase
            .from('posts')
            .insert([
                {
                    author_id,
                    content,
                    code_body: code, // mapping 'code' from frontend to 'code_body' in DB
                    language: language || 'plain_text',
                    is_bounty: type === 'bounty' // Automatically set true if type is bounty
                }
            ])
            .select('*, profiles(full_name)')
            .single();

        if (error) throw error;
        res.status(201).json(data);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;