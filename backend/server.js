const express = require('express');
const cors = require('cors');
const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// 1. Initialize Supabase Engine FIRST
const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_ANON_KEY
);

// 2. EXPORT IT IMMEDIATELY (Before routes use it)
module.exports = { supabase }; 

// 3. NOW bring in the routes
const postRoutes = require('./src/routes/postRoutes');
const profileRoutes = require('./src/routes/profileRoutes');
const authRoutes = require('./src/routes/authRoutes');

// 4. Use the routes
app.use('/api/posts', postRoutes);
app.use('/api/profiles', profileRoutes);
app.use('/api/auth', authRoutes);

// 5. Test and Listen
const testConnection = async () => {
    const { data, error } = await supabase.from('profiles').select('*').limit(1);
    if (error) console.log('❌ Error:', error.message);
    else console.log('✅ Connected to RTC Hub Database!');
};
testConnection();

app.get('/', (req, res) => res.send('RTC Hub Backend is running! 🚀'));

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`🚀 Server on http://localhost:${PORT}`));