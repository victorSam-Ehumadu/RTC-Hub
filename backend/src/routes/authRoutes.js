const express = require('express');
const router = express.Router();
const { supabase } = require('../../server'); // Ensure this points to your supabase client

// 1. SIGN UP ROUTE
router.post('/signup', async (req, res) => {
    try {
        // Updated destructuring to include business and alumni specific fields [cite: 42, 44]
        const { 
            email, 
            password, 
            full_name, 
            student_number, 
            role, 
            faculty, 
            course, 
            academic_year,
            company_name,
            graduation_year,
            verification_photo_url // From your new alumni photo upload logic [cite: 21]
        } = req.body;

        // Create user in Supabase Auth (Handles core security/authentication) [cite: 28]
        const { data: authData, error: authError } = await supabase.auth.signUp({
            email,
            password,
        });

        if (authError) throw authError;

        // FIXED: Using 'student_number' to match your schema and resolve the error
        // Role-based data insertion for the substantive profiles requirement [cite: 41]
        const { data: profileData, error: profileError } = await supabase
            .from('profiles')
            .insert([{
                id: authData.user.id,
                full_name: full_name.trim(),
                email: email.trim(),
                role: role, // Requirement: Distinct user types [cite: 16]
                faculty: faculty, // Used for IT vs Business content filtering
                course: course,
                academic_year: academic_year,
                
                // Student Extraction Logic (mapped to student_number column)
                student_number: student_number, 
                
                // Business Specifics [cite: 44]
                company_name: role === 'BUSINESS' ? company_name : null,
                is_approved_business: false, // Requirement: Approval step needed [cite: 23]
                
                // Alumni Specifics [cite: 42]
                graduation_year: role === 'ALUMNI' ? graduation_year : null,
                verification_photo_url: role === 'ALUMNI' ? verification_photo_url : null,
                alumni_status: role === 'ALUMNI' ? 'PENDING' : 'VERIFIED', // [cite: 33]
                
                logic_points: 0
            }])
            .select()
            .single();

        if (profileError) throw profileError;

        res.status(201).json({ user: profileData });

    } catch (error) {
        // Log details to help Part 4 debugging
        console.error("Signup Route Error:", error.message);
        res.status(400).json({ error: error.message });
    }
});

// 2. LOGIN ROUTE
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        // Authenticate with Supabase [cite: 28]
        const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
            email: email.trim(),
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

        // Requirement: Enforce verification checks 
        if (profileData.role === 'BUSINESS' && !profileData.is_approved_business) {
            // Optional: Allow login but restrict access via frontend
            // Or block here: throw new Error("Account pending administrator approval.");
        }

        res.status(200).json({ user: profileData });

    } catch (error) {
        res.status(401).json({ error: error.message });
    }
});

module.exports = router;