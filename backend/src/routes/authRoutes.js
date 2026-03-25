const express = require('express');
const router = express.Router();
const { supabase } = require('../../server'); // Ensure this points to your supabase client

// 1. SIGN UP ROUTE
router.post('/signup', async (req, res) => {
    try {
        const { email, password, full_name, student_number, role, faculty, course, academic_year } = req.body;

        // Create user in Supabase Auth (This handles the email/password security)
        const { data: authData, error: authError } = await supabase.auth.signUp({
            email,
            password,
        });

        if (authError) throw authError;

        // Create the profile in your custom 'profiles' table linked by the ID
        const { data: profileData, error: profileError } = await supabase
            .from('profiles')
            .insert([{
                id: authData.user.id,
                full_name,
                student_id: student_number,
                role: role || 'Student',
                faculty,
                course,
                academic_year: parseInt(academic_year) || 1,
                logic_points: 0
            }])
            .select()
            .single();

        if (profileError) throw profileError;

        res.status(201).json({ user: profileData });

    } catch (error) {
        res.status(400).json({ error: error.message });
    }
});

// 2. LOGIN ROUTE
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        // Authenticate with Supabase
        const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
            email,
            password,
        });

        if (authError) throw authError;

        // Fetch the profile data for the logged-in user
        const { data: profileData, error: profileError } = await supabase
            .from('profiles')
            .select('*')
            .eq('id', authData.user.id)
            .single();

        if (profileError) throw profileError;

        res.status(200).json({ user: profileData });

    } catch (error) {
        res.status(401).json({ error: error.message });
    }
});

module.exports = router;