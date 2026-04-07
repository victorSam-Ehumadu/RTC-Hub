import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Search, GraduationCap, Building2, UserCircle, ShieldCheck, CheckCircle2, Upload } from 'lucide-react';
import { FACULTIES, YEARS } from '../constants';
import { cn } from '../lib/utils';
import axios from 'axios';

const LandingPage = ({ onLogin }) => {
  // --- UI State ---
  const [isLogin, setIsLogin] = useState(true);
  const [loading, setLoading] = useState(false);
  const [role, setRole] = useState('STUDENT'); // Requirement: 4 distinct user types [cite: 16]
  const [courseSearch, setCourseSearch] = useState('');
  
  // --- Data State ---
  const [verificationFile, setVerificationFile] = useState(null); // For Alumni verification challenge 
  const [formData, setFormData] = useState({
    email: '',
    password: '',
    full_name: '',
    student_number: '',
    role: 'STUDENT',
    faculty: 'IT', // Default to IT for initial list rendering
    course: '',
    academic_year: '',
    company_name: '', // Mandatory for Business Profiles [cite: 44]
    graduation_year: '', // Mandatory for Alumni Profiles [cite: 42]
  });

  // --- Logic: Course Filtering ---
  const filteredCourses = FACULTIES[formData.faculty]?.courses.filter(c => 
    c.toLowerCase().includes(courseSearch.toLowerCase())
  ) || [];

  // --- Logic: Form Submission ---
  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);

    let extractedStudentNumber = '';
    let verificationUrl = null;

    // Requirement: Student registration logic
    if (!isLogin && role === 'STUDENT') {
      const cleanEmail = formData.email.trim(); // Account for white spaces

      // 1. Check domain restriction [cite: 18, 19]
      if (!cleanEmail.endsWith('@my.richfield.ac.za')) {
        alert("Registration restricted to @my.richfield.ac.za domain.");
        setLoading(false);
        return;
      }

      // 2. Extract and validate student number (9 digits before @)
      const emailPrefix = cleanEmail.split('@')[0];
      const isNineDigits = /^\d{9}$/.test(emailPrefix);

      if (!isNineDigits) {
        alert("Invalid Student Email. The prefix must be exactly 9 digits.");
        setLoading(false);
        return;
      }
      extractedStudentNumber = emailPrefix;
    }

    // Requirement: Alumni must provide proof of graduation [cite: 21, 22]
    if (!isLogin && role === 'ALUMNI' && !verificationFile) {
      alert("Please upload your graduation certificate.");
      setLoading(false);
      return;
    }

    // (Note: Supabase upload logic for verificationFile would occur here if role is ALUMNI)

    try {
      // --- FINAL REGISTRATION / LOGIN ---
      const endpoint = isLogin ? '/auth/login' : '/auth/signup';
      
      const payload = {
        ...formData,
        email: formData.email.trim(),
        full_name: formData.full_name.trim(),
        student_number: role === 'STUDENT' ? extractedStudentNumber : formData.student_number,
        role: role, // Enforce role-based access [cite: 17]
        verification_photo_url: verificationUrl // For Admin review [cite: 33]
      };

      const { data } = await axios.post(`http://localhost:5000/api${endpoint}`, payload);
      
      alert(isLogin ? 'Welcome back!' : 'Registration successful! Profiles pending admin review where applicable.');
      onLogin(data.user);

    } catch (error) {
      console.error("Auth Error:", error);
      alert(error.response?.data?.error || error.message || 'Authentication failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center p-4">
      <motion.div 
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="w-full max-w-lg bg-white rounded-2xl shadow-2xl overflow-hidden border border-gray-100 p-8"
      >
        <div className="flex items-center justify-center gap-3 mb-8">
          <div className="bg-blue-600 text-white p-2 rounded-xl font-black text-3xl rotate-3 shadow-lg">R</div>
          <h1 className="text-3xl font-black text-gray-900 tracking-tighter italic">RichConnect</h1>
        </div>

        {!isLogin && (
          <div className="flex bg-gray-100 p-1 rounded-xl mb-8">
            {[
              { id: 'STUDENT', icon: GraduationCap },
              { id: 'ALUMNI', icon: UserCircle },
              { id: 'BUSINESS', icon: Building2 }
            ].map((item) => (
              <button
                key={item.id}
                type="button"
                onClick={() => { 
                  setRole(item.id); 
                  setFormData({...formData, role: item.id, course: '', faculty: 'IT'}); 
                  setCourseSearch('');
                }}
                className={cn(
                  "flex-1 flex items-center justify-center gap-2 py-2 text-[10px] font-black rounded-lg transition-all",
                  role === item.id ? "bg-white shadow-sm text-blue-600" : "text-gray-500 hover:text-gray-700"
                )}
              >
                <item.icon size={14} />
                {item.id}
              </button>
            ))}
          </div>
        )}

        <h2 className="text-xl font-bold text-center mb-6 text-gray-700 uppercase tracking-widest">
          {isLogin ? 'Member Login' : `${role} Registration`}
        </h2>

        <form onSubmit={handleSubmit} className="space-y-4">
          <AnimatePresence mode="wait">
            <motion.div
              key={role + isLogin}
              initial={{ opacity: 0, x: 10 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -10 }}
              className="space-y-4"
            >
              <label className="text-[10px] font-bold text-blue-800 uppercase px-1">Full Name</label>
              {!isLogin && (
                
                <input 
                  type="text" 
                  placeholder={role === 'BUSINESS' ? "John Doe" : "Full Name"} 
                  required
                  className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
                  onChange={(e) => setFormData({...formData, full_name: e.target.value})}
                />
              )}

              <label className="text-[10px] font-bold text-blue-800 uppercase px-1">Student Email</label>
              <input 
                type="email" 
                placeholder={role === 'STUDENT' ? "e.g. 123456789@my.richfield.ac.za" : "john.doe@example.com"} 
                required
                className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
                onChange={(e) => setFormData({...formData, email: e.target.value})}
              />

              {!isLogin && (role === 'STUDENT' || role === 'ALUMNI') && (
                <div className="space-y-3 p-4 bg-blue-50/50 rounded-2xl border border-blue-100">
                  <label className="text-[10px] font-bold text-blue-800 uppercase px-1">Academic Profile</label>
                  
                  <div className="flex gap-2">
                    <select 
                      className="flex-1 px-3 py-2 rounded-lg border border-gray-200 text-xs font-bold bg-white outline-none focus:ring-2 focus:ring-blue-500"
                      value={formData.faculty}
                      onChange={(e) => setFormData({...formData, faculty: e.target.value, course: ''})}
                    >
                      <option value="IT">IT Faculty</option>
                      <option value="BUSINESS">Business Faculty</option>
                    </select>

                    <select 
                      className="flex-1 px-3 py-2 rounded-lg border border-gray-200 text-xs font-bold bg-white outline-none focus:ring-2 focus:ring-blue-500"
                      required
                      value={formData.academic_year}
                      onChange={(e) => setFormData({...formData, academic_year: e.target.value})}
                    >
                      <option value="">{role === 'ALUMNI' ? 'Grad Status' : 'Year of Study'}</option>
                      {YEARS.map(y => <option key={y} value={y}>{y}</option>)}
                    </select>
                  </div>

                  <div className="relative">
                    <Search className="absolute left-3 top-2.5 w-4 h-4 text-gray-400" />
                    <input 
                      type="text" 
                      placeholder="Search for your course..." 
                      className="w-full px-10 py-2 rounded-lg border border-gray-200 text-xs bg-white focus:ring-2 focus:ring-blue-500 outline-none"
                      value={courseSearch}
                      onChange={(e) => setCourseSearch(e.target.value)}
                    />
                    
                    <div className="mt-2 max-h-32 overflow-y-auto space-y-1 custom-scrollbar">
                      {filteredCourses.map(course => (
                        <button
                          key={course}
                          type="button"
                          onClick={() => { setFormData({...formData, course}); setCourseSearch(course); }}
                          className={cn(
                            "w-full text-left px-3 py-2 rounded-lg text-[10px] flex items-center justify-between transition-colors",
                            formData.course === course ? "bg-blue-600 text-white" : "bg-white hover:bg-blue-50 text-gray-700"
                          )}
                        >
                          <span className="truncate pr-2">{course}</span>
                          {formData.course === course && <CheckCircle2 size={12} />}
                        </button>
                      ))}
                    </div>
                  </div>
                  {/* Manual student number input removed as requested */}
                </div>
              )}

              
              {!isLogin && role === 'BUSINESS' && (
                <>
                  <input 
                    type="text" 
                    placeholder="E.g. John Doe Corp" 
                    required
                    className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
                    onChange={(e) => setFormData({...formData, company_name: e.target.value})}
                  />
                  <div className="bg-blue-50 p-3 rounded-xl flex gap-3 border border-blue-100 shadow-inner">
                    <ShieldCheck className="text-blue-600 shrink-0" size={18} />
                    <p className="text-[10px] text-blue-800 leading-tight">
                      <strong>Verification Required:</strong> Business accounts must be verified by administration.
                    </p>
                  </div>
                </>
              )}

              {!isLogin && role === 'ALUMNI' && (
                <div className="space-y-4">
                  <input 
                    type="text" 
                    placeholder="Graduation Year" 
                    required
                    className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
                    onChange={(e) => setFormData({...formData, graduation_year: e.target.value})}
                  />
                  
                  <div className="space-y-2">
                    <label className="text-[10px] font-black text-gray-500 uppercase px-1">
                      Identity Proof (Certificate Photo)
                    </label>
                    <div className="relative group">
                      <input 
                        type="file" 
                        accept="image/*" 
                        required
                        className="absolute inset-0 w-full h-full opacity-0 cursor-pointer z-10"
                        onChange={(e) => setVerificationFile(e.target.files[0])}
                      />
                      <div className={cn(
                        "w-full px-4 py-3 rounded-xl border-2 border-dashed flex items-center justify-center gap-3 transition-all",
                        verificationFile ? "border-green-400 bg-green-50" : "border-blue-200 bg-blue-50/30 group-hover:border-blue-400"
                      )}>
                        <Upload size={18} className={verificationFile ? "text-green-600" : "text-blue-600"} />
                        <span className="text-xs font-bold text-gray-600">
                          {verificationFile ? verificationFile.name : "Upload Verification Photo"}
                        </span>
                      </div>
                    </div>
                  </div>
                </div>
              )}
              
              <label className="text-[10px] font-bold text-blue-800 uppercase px-1">Password</label>
              <input 
                type="password" 
                placeholder="E.g. JohnDoe123!" 
                required
                className="w-full px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 outline-none text-sm"
                onChange={(e) => setFormData({...formData, password: e.target.value})}
              />
            </motion.div>
          </AnimatePresence>

          <button 
            type="submit"
            disabled={loading}
            className="w-full bg-blue-600 text-white py-4 rounded-xl font-black uppercase tracking-widest hover:bg-blue-700 transition-all shadow-xl active:scale-95 disabled:bg-gray-400 mt-4"
          >
            {loading ? 'Processing...' : (isLogin ? 'Sign In' : 'Join RichConnect')}
          </button>
        </form>

        <div className="mt-8 text-center border-t border-gray-100 pt-6">
          <button 
            onClick={() => {
              setIsLogin(!isLogin);
              setFormData({...formData, course: '', student_number: '', company_name: '', graduation_year: ''});
              setCourseSearch('');
              setVerificationFile(null);
            }}
            className="text-blue-600 font-bold text-xs hover:underline"
          >
            {isLogin ? "New account? Join Richfield" : "Already a member? Sign in"}
          </button>
        </div>
      </motion.div>
    </div>
  );
};

export default LandingPage;