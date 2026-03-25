import React, { useState, useEffect } from 'react';
import { motion } from 'motion/react';
import { 
  Users, Code, Terminal, Award, PlusCircle, 
  TrendingUp, MessageSquare, Bell, User 
} from 'lucide-react';
import { cn } from '../lib/utils';
import axios from 'axios';

// --- Sub-Component: Create Post Modal ---
const CreatePostModal = ({ isOpen, onClose, type, isIT, onPostCreated }) => {
  const [content, setContent] = useState('');
  const [codeSnippet, setCodeSnippet] = useState('');

  if (!isOpen) return null;

  const handleSubmit = async () => {
    try {
      // Replace with your actual backend URL
      await axios.post('http://localhost:5000/api/posts', {
        author_id: user.id,
        content,
        type,
        code: type === 'snippet' ? codeSnippet : null,
      });
      alert('Post created and Logic Points awarded! 🚀');
      onPostCreated(); // Refresh the feed
      onClose();
    } catch (error) {
      console.error("Error creating post:", error.message);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/50 z-[100] flex items-center justify-center p-4 backdrop-blur-sm">
      <motion.div initial={{ scale: 0.9, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="bg-white dark:bg-gray-800 w-full max-w-2xl rounded-2xl p-8 shadow-2xl">
        <div className="flex justify-between items-center mb-6">
          <h2 className="text-2xl font-bold dark:text-white uppercase tracking-tight">
            {type === 'snippet' ? (isIT ? 'Share Code' : 'Share Strategy') : 'New Post'}
          </h2>
          <button onClick={onClose} className="text-gray-400 hover:text-red-500 transition-colors">
            <PlusCircle className="w-6 h-6 rotate-45" />
          </button>
        </div>
        
        <div className="space-y-4">
          <textarea 
            rows="4" 
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder="What's on your mind?"
            className="w-full bg-gray-50 dark:bg-gray-700 border border-gray-200 dark:border-gray-600 rounded-xl p-4 text-sm dark:text-white outline-none focus:ring-2 focus:ring-blue-500"
          />

          {type === 'snippet' && (
            <textarea 
              rows="6" 
              value={codeSnippet}
              onChange={(e) => setCodeSnippet(e.target.value)}
              className="w-full bg-gray-900 text-green-400 font-mono text-xs p-4 rounded-xl outline-none"
              placeholder={isIT ? "// Paste your code here..." : "// Paste your strategy analysis here..."}
            />
          )}

          <div className="flex justify-end gap-3 pt-4">
            <button onClick={onClose} className="px-6 py-2 border border-gray-200 dark:border-gray-700 rounded-xl font-bold text-sm dark:text-gray-300">Cancel</button>
            <button onClick={handleSubmit} className="px-8 py-2 bg-blue-600 text-white rounded-xl font-bold text-sm hover:bg-blue-700">Post</button>
          </div>
        </div>
      </motion.div>
    </div>
  );
};

// --- Main Page Component ---
const FeedPage = ({ user }) => {
  const [activeModal, setActiveModal] = useState(null);
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(true);
  const isIT = user?.faculty === 'IT';

  const loadPosts = async () => {
    try {
      setLoading(true);
      const { data } = await axios.get('http://localhost:5000/api/posts');
      setPosts(data);
    } catch (err) {
      console.error("Fetch error:", err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadPosts();
  }, []);

  return (
    <div className="max-w-6xl mx-auto pt-20 px-4 grid grid-cols-1 lg:grid-cols-12 gap-6">
      
      {/* LEFT SIDEBAR */}
      <div className="lg:col-span-3 space-y-4">
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 overflow-hidden shadow-sm">
          <div className="h-16 bg-blue-600" />
          <div className="px-4 pb-4 -mt-8 text-center">
            <div className="w-16 h-16 rounded-full bg-white dark:bg-gray-700 p-1 mx-auto border border-gray-200 dark:border-gray-700">
              <img src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${user?.name}`} alt="avatar" className="rounded-full" />
            </div>
            <h3 className="mt-2 font-bold text-gray-900 dark:text-white">{user?.name}</h3>
            <p className="text-xs text-gray-500 dark:text-gray-400">{user?.course}</p>
          </div>
        </div>
      </div>

      {/* CENTER FEED */}
      <div className="lg:col-span-6 space-y-4">
        {/* Create Post Entry */}
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4 shadow-sm">
          <div className="flex gap-3">
            <div className="w-12 h-12 rounded-full bg-gray-100 dark:bg-gray-700 overflow-hidden">
              <img src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${user?.name}`} alt="avatar" />
            </div>
            <button 
              onClick={() => setActiveModal('standard')}
              className="flex-1 text-left px-4 py-3 bg-gray-50 dark:bg-gray-700 hover:bg-gray-100 rounded-full text-gray-400 text-sm"
            >
              Start a post...
            </button>
          </div>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-2 mt-4">
            <button onClick={() => setActiveModal('snippet')} className="flex items-center justify-center gap-2 text-[10px] text-gray-600 dark:text-gray-400 font-bold hover:bg-gray-100 dark:hover:bg-gray-700 p-2 rounded">
              <Terminal className="w-4 h-4 text-blue-500" /> {isIT ? 'Code Snippet' : 'Strategy'}
            </button>
            <button onClick={() => setActiveModal('bounty')} className="flex items-center justify-center gap-2 text-[10px] text-gray-600 dark:text-gray-400 font-bold hover:bg-gray-100 dark:hover:bg-gray-700 p-2 rounded">
              <Award className="w-4 h-4 text-orange-500" /> Bounty
            </button>
          </div>
        </div>

        {/* Posts List */}
        {loading ? (
          <p className="text-center dark:text-white">Loading your hub...</p>
        ) : (
          posts.map(post => (
            <motion.div key={post.id} initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 shadow-sm overflow-hidden mb-4">
              <div className="p-4 flex items-center gap-3">
                <div className="w-10 h-10 rounded-full bg-blue-100 overflow-hidden">
                  <img src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${post.user_id}`} alt="user" />
                </div>
                <div>
                  <h4 className="font-bold text-sm dark:text-white">Collaborator</h4>
                  <p className="text-[10px] text-gray-400">Richfield Student</p>
                </div>
              </div>
              <div className="px-4 pb-4">
                <p className="text-sm dark:text-gray-200 mb-3">{post.content}</p>
                {post.code && (
                  <pre className="bg-gray-900 text-green-400 p-4 rounded-lg font-mono text-xs overflow-x-auto">
                    <code>{post.code}</code>
                  </pre>
                )}
              </div>
              <div className="px-4 py-2 border-t border-gray-100 dark:border-gray-700 flex gap-4">
                <button className="flex items-center gap-1 text-xs text-gray-500"><TrendingUp className="w-4 h-4"/> Like</button>
                <button className="flex items-center gap-1 text-xs text-gray-500"><MessageSquare className="w-4 h-4"/> Comment</button>
              </div>
            </motion.div>
          ))
        )}
      </div>

      {/* RIGHT SIDEBAR */}
      <div className="lg:col-span-3 space-y-4">
        <div className="bg-white dark:bg-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 p-4 shadow-sm">
          <h4 className="font-bold text-sm mb-4 dark:text-white">Richfield News</h4>
          <div className="space-y-4">
            <div className="group cursor-pointer">
              <h5 className="text-xs font-bold dark:text-gray-200 group-hover:text-blue-600 transition-colors">Hackathon 2026 Registration</h5>
              <p className="text-[10px] text-gray-500">2d ago • 1,240 readers</p>
            </div>
          </div>
        </div>
      </div>

      <CreatePostModal 
        isOpen={!!activeModal} 
        onClose={() => setActiveModal(null)} 
        type={activeModal} 
        isIT={isIT} 
        onPostCreated={loadPosts}
      />
    </div>
  );
};

export default FeedPage;