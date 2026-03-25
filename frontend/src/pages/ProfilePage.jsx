import React, { useState } from 'react';
import { PlusCircle, Award, ShieldCheck, TrendingUp, Users } from 'lucide-react';
import { cn } from '../lib/utils';

const ProfilePage = ({ user }) => {
  const projects = [
    { title: 'Richfield Campus Map', desc: 'Interactive 3D map', tags: ['React', '3D'], likes: 120 },
    { title: 'Student Budget Tracker', desc: 'Finance app', tags: ['Finance', 'Mobile'], likes: 85 },
  ];

  return (
    <div className="max-w-4xl mx-auto pt-24 px-4 pb-20">
      <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm overflow-hidden mb-6">
        <div className="h-32 bg-gradient-to-r from-blue-600 to-indigo-700" />
        <div className="px-8 pb-8 -mt-12 text-center sm:text-left">
           <img src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${user?.name}`} className="w-32 h-32 rounded-full mx-auto sm:mx-0 border-4 border-white bg-gray-700" alt="avatar" />
           <h1 className="text-2xl font-bold dark:text-white mt-4">{user?.name}</h1>
           <p className="text-gray-600 dark:text-gray-400">{user?.course} • {user?.year}</p>
        </div>
      </div>
      {/* Grid for Projects and Heatmap */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
         <div className="md:col-span-2 bg-white dark:bg-gray-800 p-6 rounded-xl border border-gray-200 dark:border-gray-700">
            <h3 className="font-bold mb-4 flex items-center gap-2 dark:text-white"><PlusCircle className="text-purple-500"/> Projects</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
               {projects.map((p, i) => (
                 <div key={i} className="border border-gray-100 dark:border-gray-700 p-4 rounded-xl">
                   <h4 className="font-bold text-sm dark:text-white">{p.title}</h4>
                   <p className="text-[10px] text-gray-500">{p.desc}</p>
                 </div>
               ))}
            </div>
         </div>
      </div>
    </div>
  );
};
export default ProfilePage;