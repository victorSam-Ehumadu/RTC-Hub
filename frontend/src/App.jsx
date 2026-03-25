import React from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './hooks/useAuth'; 
import Navbar from './components/Navbar'; 

import LandingPage from './pages/LandingPage';
import FeedPage from './pages/FeedPage';
import BountyPage from './pages/BountyPage';
import ProfilePage from './pages/ProfilePage';
import MentorshipPage from './pages/MentorshipPage';
import MessagingPage from './pages/MesssagingPage'; 
import AnalyticsPage from './pages/AnalyticsPage';
import EventsPage from './pages/EventsPage';

export default function App() {
  const { user, login, logout, darkMode, toggleDarkMode } = useAuth();

  return (
    <Router>
      <div className="min-h-screen bg-gray-50 dark:bg-gray-950 font-sans text-gray-900">
        {user ? (
          <>
            <Navbar user={user} logout={logout} darkMode={darkMode} toggleDarkMode={toggleDarkMode} />
            <main className="pb-10">
              <Routes>
                <Route path="/" element={<FeedPage user={user} />} />
                <Route path="/bounties" element={<BountyPage />} />
                <Route path="/profile" element={<ProfilePage user={user} />} />
                <Route path="/mentorship" element={<MentorshipPage user={user} />} />
                <Route path="/messages" element={<MessagingPage user={user} />} />
                <Route path="/analytics" element={<AnalyticsPage user={user} />} />
                <Route path="/events" element={<EventsPage />} />
                <Route path="*" element={<Navigate to="/" />} />
              </Routes>
            </main>
          </>
        ) : (
          <Routes>
            <Route path="/login" element={<LandingPage onLogin={login} />} />
            <Route path="*" element={<Navigate to="/login" />} />
          </Routes>
        )}
      </div>
    </Router>
  );
}