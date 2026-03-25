import React from 'react';
import { motion } from 'motion/react';
import { Award } from 'lucide-react';
import { cn } from '../lib/utils';

const BountyPage = () => {
  const bounties = [
    { title: 'Debug Java Recursion', reward: 500, faculty: 'IT', author: 'Sipho M.', time: '2h ago' },
    { title: 'Market Research Spreadsheet', reward: 350, faculty: 'BUSINESS', author: 'Lerato K.', time: '5h ago' },
    { title: 'React State Management Help', reward: 1000, faculty: 'IT', author: 'Thabo N.', time: '1d ago' },
  ];

  return (
    <div className="max-w-4xl mx-auto pt-24 px-4 pb-20">
      <div className="flex justify-between items-center mb-8">
        <div>
          <h1 className="text-3xl font-bold dark:text-white">Active Bounties</h1>
          <p className="text-gray-500 dark:text-gray-400">Solve problems, earn Logic Points, and climb the leaderboard.</p>
        </div>
        <button className="px-4 py-2 bg-blue-600 text-white rounded-xl font-bold text-sm">Post Bounty</button>
      </div>

      <div className="space-y-4">
        {bounties.map((b, i) => (
          <motion.div key={i} whileHover={{ scale: 1.01 }} className="bg-white dark:bg-gray-800 p-6 rounded-2xl border border-gray-200 dark:border-gray-700 shadow-sm flex items-center justify-between">
            <div className="flex items-center gap-4">
              <div className={cn("w-12 h-12 rounded-xl flex items-center justify-center font-bold text-white", b.faculty === 'IT' ? 'bg-blue-500' : 'bg-green-500')}>
                {b.faculty[0]}
              </div>
              <div>
                <h3 className="font-bold dark:text-white">{b.title}</h3>
                <p className="text-xs text-gray-500 dark:text-gray-400">Posted by {b.author} • {b.time}</p>
              </div>
            </div>
            <div className="text-right">
              <div className="text-lg font-black text-orange-500 flex items-center gap-1 justify-end">
                <Award className="w-5 h-5" /> {b.reward}
              </div>
              <button className="mt-2 px-4 py-1.5 bg-gray-900 dark:bg-blue-600 text-white rounded-lg font-bold text-[10px]">Accept Bounty</button>
            </div>
          </motion.div>
        ))}
      </div>
    </div>
  );
};
export default BountyPage;