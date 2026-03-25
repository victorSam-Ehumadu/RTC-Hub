import React from 'react';
import { motion } from 'motion/react';
import { Users, Award, MessageSquare, TrendingUp } from 'lucide-react';
import { cn } from '../lib/utils';

const AnalyticsPage = () => {
  return (
    <div className="max-w-6xl mx-auto pt-24 px-4 pb-20">
      <h1 className="text-3xl font-bold mb-8 dark:text-white">Your Analytics Dashboard</h1>
      
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        {[
          { label: 'Profile Views', value: '1,240', change: '+12%', icon: Users, color: 'text-blue-500' },
          { label: 'Logic Points', value: '4,850', change: '+500', icon: Award, color: 'text-orange-500' },
          { label: 'Collab Requests', value: '12', change: '+2', icon: MessageSquare, color: 'text-green-500' },
          { label: 'Post Reach', value: '15.4k', change: '+5.2k', icon: TrendingUp, color: 'text-purple-500' },
        ].map((stat, i) => (
          <div key={i} className="bg-white dark:bg-gray-800 p-6 rounded-2xl border border-gray-200 dark:border-gray-700 shadow-sm">
            <div className="flex justify-between items-start mb-4">
              <div className={cn("p-2 rounded-lg bg-gray-50 dark:bg-gray-700", stat.color)}>
                <stat.icon className="w-6 h-6" />
              </div>
              <span className="text-xs font-bold text-green-500">{stat.change}</span>
            </div>
            <h3 className="text-2xl font-black dark:text-white">{stat.value}</h3>
            <p className="text-xs text-gray-500 dark:text-gray-400 font-bold uppercase tracking-wider">{stat.label}</p>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="bg-white dark:bg-gray-800 p-6 rounded-2xl border border-gray-200 dark:border-gray-700 shadow-sm">
          <h3 className="font-bold mb-6 dark:text-white">Weekly Engagement</h3>
          <div className="h-64 flex items-end gap-2">
            {[40, 70, 45, 90, 65, 80, 55].map((h, i) => (
              <div key={i} className="flex-1 flex flex-col items-center gap-2">
                <div className="w-full bg-blue-100 dark:bg-blue-900/20 rounded-t-lg relative group">
                  <motion.div 
                    initial={{ height: 0 }}
                    animate={{ height: `${h}%` }}
                    className="w-full bg-blue-600 rounded-t-lg"
                  />
                </div>
                <span className="text-[10px] text-gray-400 font-bold">Day {i+1}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="bg-white dark:bg-gray-800 p-6 rounded-2xl border border-gray-200 dark:border-gray-700 shadow-sm">
          <h3 className="font-bold mb-6 dark:text-white">Top Skills by Verification</h3>
          <div className="space-y-4">
            {[
              { skill: 'Java', level: 90, color: 'bg-blue-600' },
              { skill: 'SQL', level: 75, color: 'bg-green-600' },
              { skill: 'React', level: 60, color: 'bg-purple-600' },
              { skill: 'Python', level: 45, color: 'bg-orange-600' },
            ].map((s, i) => (
              <div key={i}>
                <div className="flex justify-between text-xs font-bold mb-1 dark:text-gray-300">
                  <span>{s.skill}</span>
                  <span>{s.level}%</span>
                </div>
                <div className="h-2 bg-gray-100 dark:bg-gray-700 rounded-full overflow-hidden">
                  <motion.div initial={{ width: 0 }} animate={{ width: `${s.level}%` }} className={cn("h-full", s.color)} />
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
export default AnalyticsPage;