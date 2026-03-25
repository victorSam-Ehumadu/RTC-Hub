import React, { useState } from 'react';
import { motion } from 'motion/react';
import { Search } from 'lucide-react';
import { FACULTIES, ROLES, YEARS } from '../constants';
import { cn } from '../lib/utils';
import axios from 'axios';

const LandingPage = ({ onLogin }) => {
  const [isLogin, setIsLogin] = useState(true);
  const [courseSearch, setCourseSearch] = useState('');
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState({
    email: '',
    password: '',
    full_name: '',
    student_number: '',
    role: 'Student',
    faculty: 'IT',
    course: '',
    academic_year: '1st Year'
  });

  const filteredCourses = FACULTIES[formData.faculty].courses.filter(c => 
    c.toLowerCase().includes(courseSearch.toLowerCase())
  );

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);

    try {
      const endpoint = isLogin ? '/auth/login' : '/auth/signup';
      // Sending request to your Express backend
      const { data } = await axios.post(`http://localhost:5000/api/auth/signup`, formData);
      
      // Data contains the user object and the session/token
      alert(isLogin ? 'Welcome back!' : 'Account created successfully!');
      onLogin(data.user); 
    } catch (error) {
      alert(error.response?.data?.error || 'Authentication failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center p-4">
      <motion.div 
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        className="w-full max-w-md bg-white rounded-2xl shadow-2xl overflow-hidden border border-gray-100 p-8"
      >
        <div className="flex items-center justify-center gap-3 mb-8">
          <div className="bg-blue-600 text-white p-2 rounded-xl font-black text-3xl rotate-3 shadow-lg">R</div>
          <h1 className="text-3xl font-black text-gray-900 tracking-tighter italic">RTC Hub</h1>
        </div>

        <h2 className="text-xl font-bold text-center mb-6 text-gray-700 uppercase tracking-tight">
          {isLogin ? 'Scholar Login' : 'Join the Network'}
        </h2>

        <form onSubmit={handleSubmit} className="space-y-4">
          {!isLogin && (
            <div className="grid grid-cols-2 gap-4">
              <input 
                type="text" 
                placeholder="Full Name" 
                required
                className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
                onChange={(e) => setFormData({...formData, full_name: e.target.value})}
              />
              <input 
                type="text" 
                placeholder="Student #" 
                required
                className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
                onChange={(e) => setFormData({...formData, student_number: e.target.value})}
              />
            </div>
          )}
          
          <input 
            type="email" 
            placeholder="Richfield Email" 
            required
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
            onChange={(e) => setFormData({...formData, email: e.target.value})}
          />
          <input 
            type="password" 
            placeholder="Password" 
            required
            className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
            onChange={(e) => setFormData({...formData, password: e.target.value})}
          />

          {!isLogin && (
            <div className="space-y-3 pt-2">
              <div className="flex gap-2">
                <select 
                  className="flex-1 px-4 py-2 rounded-xl border border-gray-200 text-xs font-bold"
                  onChange={(e) => setFormData({...formData, role: e.target.value})}
                >
                  {ROLES.map(role => <option key={role} value={role}>{role}</option>)}
                </select>
                <select 
                  className="flex-1 px-4 py-2 rounded-xl border border-gray-200 text-xs font-bold"
                  onChange={(e) => setFormData({...formData, faculty: e.target.value})}
                >
                  <option value="IT">IT Faculty</option>
                  <option value="BUSINESS">Business Faculty</option>
                </select>
              </div>

              <div className="relative">
                <Search className="absolute left-3 top-3 w-4 h-4 text-gray-400" />
                <input 
                  type="text" 
                  placeholder="Search course..." 
                  className="w-full px-10 py-2 rounded-xl border border-gray-200 text-xs"
                  value={courseSearch}
                  onChange={(e) => setCourseSearch(e.target.value)}
                />
                <div className="mt-2 max-h-32 overflow-y-auto border border-gray-100 rounded-xl p-1 bg-gray-50">
                  {filteredCourses.map(course => (
                    <button
                      key={course}
                      type="button"
                      onClick={() => { setFormData({...formData, course}); setCourseSearch(course); }}
                      className={cn(
                        "w-full text-left px-3 py-2 rounded-lg text-[10px] transition-colors",
                        formData.course === course ? "bg-blue-600 text-white" : "hover:bg-white"
                      )}
                    >
                      {course}
                    </button>
                  ))}
                </div>
              </div>

              <select 
                className="w-full px-4 py-2 rounded-xl border border-gray-200 text-xs font-bold"
                onChange={(e) => setFormData({...formData, academic_year: e.target.value})}
              >
                {YEARS.map(year => <option key={year} value={year}>{year}</option>)}
              </select>
            </div>
          )}

          <button 
            type="submit"
            disabled={loading}
            className="w-full bg-blue-600 text-white py-4 rounded-xl font-bold hover:bg-blue-700 transition-all shadow-xl active:scale-95 disabled:bg-gray-400"
          >
            {loading ? 'Processing...' : (isLogin ? 'Sign In' : 'Create Account')}
          </button>
        </form>

        <div className="mt-8 text-center">
          <button 
            onClick={() => setIsLogin(!isLogin)}
            className="text-blue-600 font-bold text-sm hover:underline"
          >
            {isLogin ? "Don't have an account? Join Richfield" : 'Already a member? Sign in'}
          </button>
        </div>
      </motion.div>
    </div>
  );
};

export default LandingPage;