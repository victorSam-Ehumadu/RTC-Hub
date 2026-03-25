import React, { useState } from 'react';
import { Search } from 'lucide-react';
import { Link } from 'react-router-dom';

const MentorshipPage = () => {
  const mentors = [
    { name: 'Dr. Alan Turing', role: 'Senior Lecturer', faculty: 'IT', skills: ['Algorithms', 'AI'], avatar: 'Alan' },
    { name: 'Jane Doe', role: '3rd Year Student', faculty: 'IT', skills: ['React', 'Node.js'], avatar: 'Jane' },
  ];

  return (
    <div className="max-w-5xl mx-auto pt-24 px-4">
      <h1 className="text-3xl font-bold dark:text-white mb-8">Mentorship Bridge</h1>
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {mentors.map((m, i) => (
          <div key={i} className="bg-white dark:bg-gray-800 p-6 rounded-2xl border border-gray-200 dark:border-gray-700 text-center shadow-sm">
             <img src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${m.avatar}`} className="w-20 h-20 mx-auto rounded-full mb-4" />
             <h3 className="font-bold dark:text-white">{m.name}</h3>
             <p className="text-blue-600 text-sm">{m.role}</p>
             <Link to="/messages" className="mt-4 block w-full py-2 bg-blue-600 text-white rounded-xl font-bold">Message</Link>
          </div>
        ))}
      </div>
    </div>
  );
};
export default MentorshipPage;