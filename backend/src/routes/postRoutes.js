const express = require('express');
const router = express.Router();
const { supabase } = require('../../server');

// GET: Fetchhing all posts for the feed
router.get('/', async (req, res) => {
    try {
        // 1. ask supabase for posts
        const { data, error } = await supabase
            .from('posts') // name of your table in Supabase
            .select('*, profiles(full_name, logic_points)')
            .order('created_at', { ascending: false });

        if (error) throw error;

        // 2. send the data back to the frontend
        res.status(200).json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

router.post('/', async (req, res) => {
    try {
        const { author_id, content, code_body, language, is_bounty } = req.body;

        // 1. Basic Validation (Do't let people post empty content)
        if (!content || !author_id) {
            return res.status(400).json({ error: "Missing content or author_id" });
        }

        // 2. Insert the new post into Supabase
        const { data, error } = await supabase
            .from('posts')
            .insert([
                {
                    author_id,
                    content,
                    code_body,
                    language,
                    is_bounty
                }
            ])
            .select('content, created_at, profiles(full_name)') // Returns the newly created post
            .single(); // We expect only one post to be created

        if (error) throw error;

        // 3. Send the newly created post back to the frontend
        res.status(201).json(data); // 201 = Created, data[0] = the newly created post

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;