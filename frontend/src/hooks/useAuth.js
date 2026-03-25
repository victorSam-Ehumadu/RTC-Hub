import { useState, useEffect } from 'react';

export const useAuth = () => {
  const [user, setUser] = useState(() => {
    const saved = localStorage.getItem('rtc_user');
    return saved ? JSON.parse(saved) : null;
  });

  const [darkMode, setDarkMode] = useState(() => {
    return localStorage.getItem('rtc_dark_mode') === 'true';
  });

  useEffect(() => {
    if (darkMode) document.documentElement.classList.add('dark');
    else document.documentElement.classList.remove('dark');
    localStorage.setItem('rtc_dark_mode', darkMode);
  }, [darkMode]);

  const login = (userData) => {
    localStorage.setItem('rtc_user', JSON.stringify(userData));
    setUser(userData);
  };

  const logout = () => {
    localStorage.removeItem('rtc_user');
    setUser(null);
  };

  return { user, login, logout, darkMode, toggleDarkMode: () => setDarkMode(!darkMode) };
};