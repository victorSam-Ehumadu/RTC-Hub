import React, { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { Home, Award, Users, LayoutDashboard, BookOpen, MessageSquare, Bell, TrendingUp, User, LogOut, Search, ShieldCheck } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { cn } from '../lib/utils';

const Navbar = ({ user, logout, darkMode, toggleDarkMode }) => {
  const location = useLocation();
  const [showNotifications, setShowNotifications] = useState(false);
  
  const navItems = [
    { icon: Home, label: 'Home', path: '/' },
    { icon: Award, label: 'Bounties', path: '/bounties' },
    { icon: Users, label: 'Mentorship', path: '/mentorship' },
    { icon: LayoutDashboard, label: 'Analytics', path: '/analytics' },
    { icon: BookOpen, label: 'Events', path: '/events' },
  ];

  if (user?.role === 'Admin') navItems.push({ icon: ShieldCheck, label: 'Admin', path: '/admin' });

  return (
    <nav className="fixed top-0 w-full bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-800 z-50 px-8 h-14 flex items-center justify-between">
      <div className="flex items-center gap-8">
        <Link to="/" className="flex items-center gap-2">
          <div className="bg-blue-600 text-white p-1 rounded font-bold text-xl">R</div>
          <span className="font-bold text-gray-800 dark:text-gray-100 tracking-tight">RTC Hub</span>
        </Link>
      </div>

      <div className="flex items-center gap-4">
        {navItems.map((item) => (
          <Link 
            key={item.path} 
            to={item.path}
            className={cn(
              "flex flex-col items-center justify-center text-gray-500 hover:text-blue-600 transition-colors",
              location.pathname === item.path && "text-blue-600"
            )}
          >
            <item.icon className="w-5 h-5" />
            <span className="text-[10px] mt-1">{item.label}</span>
          </Link>
        ))}
        
        <div className="h-8 w-px bg-gray-200 dark:bg-gray-700 mx-2" />
        
        <button onClick={logout} className="text-red-500 hover:bg-red-50 p-2 rounded-lg transition-colors">
          <LogOut className="w-5 h-5" />
        </button>
      </div>
    </nav>
  );
};
export default Navbar;