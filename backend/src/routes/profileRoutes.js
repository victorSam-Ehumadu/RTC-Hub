const express = require('express');
const router = express.Router();
const { supabase } = require('../../server');

// GET: Fetching a specific profile by ID
router.get('/:id', async (req, res) => {
    try {

        const { id } = req.params;

        // 1. ask supabase for the profile with the given ID
        const { data, error } = await supabase
            .from('profiles')
            .select('*')
            .eq('id', id)
            .single();

        if (error) throw error;

        // 2. send the data back to the frontend
        res.status(200).json(data);

    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// allowing the user to update their profile (name, bio, etc.)
router.put('/:id', async (req, res) => {
    try{
        const { id } = req.params;
        const {
            full_name,
            bio,
            academic_year,
        } = req.body;

        // 1. Update the profile in Supabase
        const { data, error } = await supabase
            .from('profiles')
            .update({
                full_name,
                bio,
                academic_year
            })
            .eq('id', id)
            .select()
            .single();

        if (error) throw error;

        // 2. Send the updated profile back to the frontend
        res.status(200).json(data);
        
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

module.exports = router;