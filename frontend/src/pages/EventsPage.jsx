import React from 'react';
import { Bell } from 'lucide-react';
import { cn } from '../lib/utils';

const EventsPage = () => {
  const events = [
    { title: 'Richfield Hackathon 2026', date: 'March 28', time: '09:00 AM', type: 'Competition', color: 'bg-blue-500' },
    { title: 'Business Strategy Workshop', date: 'April 02', time: '02:00 PM', type: 'Workshop', color: 'bg-green-500' },
    { title: 'Guest Lecture: AI in SA', date: 'April 05', time: '11:00 AM', type: 'Lecture', color: 'bg-purple-500' },
  ];

  return (
    <div className="max-w-4xl mx-auto pt-24 px-4 pb-20">
      <div className="flex justify-between items-center mb-8">
        <h1 className="text-3xl font-bold dark:text-white">Campus Events</h1>
        <button className="bg-blue-600 text-white px-4 py-2 rounded-xl font-bold text-sm">Add Event</button>
      </div>

      <div className="grid grid-cols-7 gap-4 mb-8">
        {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map(day => (
          <div key={day} className="text-center text-xs font-bold text-gray-400 uppercase">{day}</div>
        ))}
        {Array.from({ length: 31 }).map((_, i) => (
          <div key={i} className={cn(
            "aspect-square border border-gray-100 dark:border-gray-800 rounded-xl p-2 text-xs font-bold transition-colors hover:bg-blue-50 dark:hover:bg-blue-900/20 cursor-pointer",
            i + 1 === 25 ? "bg-blue-600 text-white border-blue-600" : "bg-white dark:bg-gray-800 dark:text-gray-400"
          )}>
            {i + 1}
          </div>
        ))}
      </div>

      <div className="space-y-4">
        <h3 className="font-bold text-gray-900 dark:text-white mb-4">Upcoming This Week</h3>
        {events.map((e, i) => (
          <div key={i} className="bg-white dark:bg-gray-800 p-4 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm flex items-center gap-4">
            <div className={cn("w-2 h-12 rounded-full", e.color)} />
            <div className="flex-1">
              <h4 className="font-bold text-sm dark:text-white">{e.title}</h4>
              <p className="text-xs text-gray-500 dark:text-gray-400">{e.date} • {e.time}</p>
            </div>
            <span className="text-[10px] font-bold px-2 py-1 bg-gray-100 dark:bg-gray-700 rounded-lg dark:text-gray-300 uppercase">{e.type}</span>
          </div>
        ))}
      </div>
    </div>
  );
};
export default EventsPage;