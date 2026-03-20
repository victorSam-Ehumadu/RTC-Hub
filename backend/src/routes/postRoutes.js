const express = require('express');
const router = express.Router();
const { supabase } = require('../../server');

// GET: Fetchhing all posts for the feed
router.get('/', async (req, res) => {
    try {
        // 1. ask supabase for posts
        const { data, error } = await supabase
            .from('posts') // name of your table in Supabase
            .select('*')
            .order('created_at', { ascending: false });

        if (error) throw error;

        // 2. send the data back to the frontend
        res.status(200).json(data);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;