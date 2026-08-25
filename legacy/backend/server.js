require('dotenv').config();
const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

// Routes
const authRoutes        = require('./src/routes/auth');
const profileRoutes     = require('./src/routes/profiles');
const postRoutes        = require('./src/routes/posts');
const connectionRoutes  = require('./src/routes/connections');
const messageRoutes     = require('./src/routes/messages');
const opportunityRoutes = require('./src/routes/opportunities');
const adminRoutes       = require('./src/routes/admin');
const eventRoutes       = require('./src/routes/events');
const analyticsRoutes   = require('./src/routes/analytics');
const notifRoutes       = require('./src/routes/notifications');
const onboardingRoutes  = require('./src/routes/onboarding');
const uploadRoutes      = require('./src/routes/uploads');

const { setupSocketHandlers } = require('./src/services/socketService');

const app = express();
const server = http.createServer(app);

// ─── Socket.IO (WebSockets for real-time) ─────────────────────
const io = new Server(server, {
  cors: {
    origin: process.env.FRONTEND_URL || 'http://localhost:5173',
    credentials: true,
  },
});
setupSocketHandlers(io);
app.set('io', io); // make io accessible in routes

// ─── Middleware ───────────────────────────────────────────────
app.use(helmet());
app.use(cors({
  origin: process.env.FRONTEND_URL || 'http://localhost:5173',
  credentials: true,
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Rate limiting
const limiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 200 });
const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 20 });
app.use('/api/', limiter);
app.use('/api/auth/', authLimiter);

// ─── Routes ───────────────────────────────────────────────────
app.use('/api/auth',         authRoutes);
app.use('/api/profiles',     profileRoutes);
app.use('/api/posts',        postRoutes);
app.use('/api/connections',  connectionRoutes);
app.use('/api/messages',     messageRoutes);
app.use('/api/opportunities', opportunityRoutes);
app.use('/api/admin',        adminRoutes);
app.use('/api/events',       eventRoutes);
app.use('/api/analytics',    analyticsRoutes);
app.use('/api/notifications', notifRoutes);
app.use('/api/onboarding',   onboardingRoutes);
app.use('/api/upload',       uploadRoutes);

app.get('/api/health', (req, res) => res.json({ status: 'ok', ts: new Date() }));

// ─── Global error handler ─────────────────────────────────────
app.use((err, req, res, next) => {
  console.error(err);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => console.log(`🚀 RichConnect server running on port ${PORT}`));