import React, { useState } from 'react';
import { PlusCircle } from 'lucide-react';
import { cn } from '../lib/utils';

const MessagingPage = ({ user }) => {
  const [activeChat, setActiveChat] = useState(0);
  const chats = [
    { name: 'Dr. Alan Turing', lastMsg: 'The logic in your last snippet was spot on!', time: '10m ago', avatar: 'Alan' },
    { name: 'Jane Doe', lastMsg: 'Are we still meeting for the project collab?', time: '1h ago', avatar: 'Jane' },
  ];

  return (
    <div className="max-w-6xl mx-auto pt-14 h-screen flex">
      {/* Sidebar */}
      <div className="w-80 border-r border-gray-200 dark:border-gray-800 bg-white dark:bg-gray-900 overflow-y-auto">
        <div className="p-4 border-b border-gray-100 dark:border-gray-800">
          <h2 className="font-bold text-xl dark:text-white">Messages</h2>
        </div>
        {chats.map((chat, i) => (
          <div 
            key={i}
            onClick={() => setActiveChat(i)}
            className={cn(
              "p-4 flex gap-3 cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors",
              activeChat === i && "bg-blue-50 dark:bg-blue-900/20 border-r-4 border-blue-600"
            )}
          >
            <div className="w-12 h-12 rounded-full overflow-hidden bg-gray-100">
              <img src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${chat.avatar}`} alt="avatar" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex justify-between items-center mb-1">
                <h4 className="font-bold text-sm truncate dark:text-white">{chat.name}</h4>
                <span className="text-[10px] text-gray-400">{chat.time}</span>
              </div>
              <p className="text-xs text-gray-500 dark:text-gray-400 truncate">{chat.lastMsg}</p>
            </div>
          </div>
        ))}
      </div>

      {/* Chat Area */}
      <div className="flex-1 flex flex-col bg-gray-50 dark:bg-gray-950">
        <div className="p-4 bg-white dark:bg-gray-900 border-b border-gray-200 dark:border-gray-800 flex items-center gap-3">
          <div className="w-10 h-10 rounded-full overflow-hidden bg-gray-100">
            <img src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${chats[activeChat].avatar}`} alt="avatar" />
          </div>
          <h3 className="font-bold dark:text-white">{chats[activeChat].name}</h3>
        </div>
        
        <div className="flex-1 p-6 overflow-y-auto space-y-4">
          <div className="flex justify-start">
            <div className="bg-white dark:bg-gray-800 p-3 rounded-2xl rounded-tl-none shadow-sm max-w-md text-sm dark:text-gray-200">
              Hello! How can I help you with your project today?
            </div>
          </div>
          <div className="flex justify-end">
            <div className="bg-blue-600 p-3 rounded-2xl rounded-tr-none shadow-sm max-w-md text-sm text-white">
              I was wondering if you could take a look at my latest code snippet on the feed.
            </div>
          </div>
        </div>

        <div className="p-4 bg-white dark:bg-gray-900 border-t border-gray-200 dark:border-gray-800">
          <div className="flex gap-2">
            <input 
              type="text" 
              placeholder="Write a message..." 
              className="flex-1 bg-gray-100 dark:bg-gray-800 rounded-full px-6 py-2 text-sm outline-none focus:ring-2 focus:ring-blue-500 dark:text-white"
            />
            <button className="bg-blue-600 text-white p-2 rounded-full hover:bg-blue-700 transition-colors">
              <PlusCircle className="w-5 h-5" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
export default MessagingPage;