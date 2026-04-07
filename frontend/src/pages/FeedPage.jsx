import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { 
  Users, Code, Terminal, Award, PlusCircle, 
  TrendingUp, MessageSquare, Bell, User, Video, Send, MoreHorizontal
} from 'lucide-react';
import { cn } from '../lib/utils';
import axios from 'axios';

// --- Sub-Component: Create Post Modal ---
const CreatePostModal = ({ isOpen, onClose, type, isIT, user, onPostCreated }) => {
  const [content, setContent] = useState('');
  const [codeSnippet, setCodeSnippet] = useState('');
  const [videoFile, setVideoFile] = useState(null);

  if (!isOpen) return null;

  const handleSubmit = async () => {
    try {
      const formData = new FormData();
      formData.append('author_id', user.id);
      formData.append('content', content);
      formData.append('type', type);
      formData.append('faculty', user.faculty); // Used for personalized feed logic 

      if (type === 'snippet') formData.append('code', codeSnippet);
      
      // Requirement: Mandatory video processing/upload [cite: 85]
      if (type === 'video' && videoFile) {
        formData.append('video', videoFile);
      }

      await axios.post('http://localhost:5000/api/posts', formData);
      alert('Post shared with the Richfield community! 🚀');
      onPostCreated(); 
      onClose();
    } catch (error) {
      console.error("Error creating post:", error.message);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 z-[100] flex items-center justify-center p-4 backdrop-blur-md">
      <motion.div initial={{ scale: 0.9, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} className="bg-white dark:bg-gray-800 w-full max-w-2xl rounded-2xl p-8 shadow-2xl border border-gray-100 dark:border-gray-700">
        <div className="flex justify-between items-center mb-6 border-b pb-4">
          <h2 className="text-xl font-black dark:text-white uppercase tracking-tighter italic">
            {type === 'video' ? 'Upload Career Journey' : type === 'snippet' ? (isIT ? 'Share Code' : 'Share Strategy') : 'Create Professional Update'}
          </h2>
          <button onClick={onClose} className="text-gray-400 hover:text-red-500 transition-all active:scale-90">
            <PlusCircle className="w-6 h-6 rotate-45" />
          </button>
        </div>
        
        <div className="space-y-4">
          <textarea 
            rows="4" 
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder={type === 'video' ? "Describe this career insight..." : "What's happening in your professional journey?"}
            className="w-full bg-gray-50 dark:bg-gray-700 border-none rounded-xl p-4 text-sm dark:text-white focus:ring-2 focus:ring-blue-600 outline-none"
          />

          {type === 'snippet' && (
            <textarea 
              rows="6" 
              value={codeSnippet}
              onChange={(e) => setCodeSnippet(e.target.value)}
              className="w-full bg-black text-green-400 font-mono text-xs p-4 rounded-xl outline-none border border-gray-800"
              placeholder={isIT ? "// Paste your clean code here..." : "// Paste your business strategy here..."}
            />
          )}

          {/* Requirement: Support for short-form video uploads  */}
          {type === 'video' && (
            <div className="border-2 border-dashed border-blue-200 dark:border-gray-600 rounded-xl p-8 text-center bg-blue-50/30">
              <input 
                type="file" 
                accept="video/*" 
                onChange={(e) => setVideoFile(e.target.files[0])}
                className="hidden" 
                id="video-upload" 
              />
              <label htmlFor="video-upload" className="cursor-pointer flex flex-col items-center gap-2">
                <Video className="w-10 h-10 text-blue-600" />
                <span className="text-xs font-bold text-blue-800">{videoFile ? videoFile.name : "Select Video (Career Journeys, Day-in-the-life)"}</span>
              </label>
            </div>
          )}

          <div className="flex justify-end gap-3 pt-4">
            <button onClick={onClose} className="px-6 py-2 rounded-xl font-black text-xs uppercase tracking-widest dark:text-gray-400">Cancel</button>
            <button onClick={handleSubmit} className="px-8 py-3 bg-blue-600 text-white rounded-xl font-black text-xs uppercase tracking-widest hover:bg-blue-700 shadow-lg active:scale-95 transition-all">Post Entry</button>
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
  
  // Requirement: Feed personalization based on role 
  const isIT = user?.faculty === 'IT';
  const isBusinessUser = user?.role === 'BUSINESS';

  const loadPosts = async () => {
    try {
      setLoading(true);
      // Requirement: Fetching posts relevant to the user's role and faculty 
      const { data } = await axios.get(`http://localhost:5000/api/posts?faculty=${user?.faculty}&role=${user?.role}`);
      setPosts(data);
    } catch (err) {
      console.error("Fetch error:", err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadPosts();
  }, [user]);

  return (
    <div className="min-h-screen bg-[#F3F4F6] dark:bg-[#111] pt-24 pb-12 px-4 grid grid-cols-1 lg:grid-cols-12 gap-6 max-w-7xl mx-auto">
      
      {/* LEFT SIDEBAR: Professional Identity [cite: 41] */}
      <div className="lg:col-span-3 space-y-4">
        <div className="bg-white dark:bg-gray-800 rounded-2xl border border-gray-100 dark:border-gray-800 overflow-hidden shadow-xl sticky top-24">
          <div className="h-20 bg-gradient-to-r from-blue-600 to-indigo-700" />
          <div className="px-4 pb-6 -mt-10 text-center">
            <div className="w-20 h-20 rounded-2xl bg-white dark:bg-gray-800 p-1 mx-auto border-4 border-white dark:border-gray-800 shadow-lg">
              <img src={user?.avatar_url || `https://api.dicebear.com/7.x/avataaars/svg?seed=${user?.full_name}`} alt="avatar" className="rounded-xl w-full h-full object-cover" />
            </div>
            <h3 className="mt-3 font-black text-gray-900 dark:text-white tracking-tighter uppercase">{user?.full_name}</h3>
            <p className="text-[10px] font-bold text-blue-600 uppercase tracking-widest">{user?.role} • {user?.faculty} Faculty</p>
            
            <div className="mt-6 pt-6 border-t border-gray-50 dark:border-gray-700 grid grid-cols-2 gap-2 text-left">
              <div>
                <p className="text-[9px] font-black text-gray-400 uppercase">Connections</p>
                <p className="text-sm font-black text-blue-600">42</p>
              </div>
              <div>
                <p className="text-[9px] font-black text-gray-400 uppercase">Logic Points</p>
                <p className="text-sm font-black text-orange-500">{user?.logic_points || 0}</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* CENTER FEED: Personalized Activity Feed  */}
      <div className="lg:col-span-6 space-y-5">
        
        {/* Create Post Entry: Professional Update & Video [cite: 51, 52] */}
        <div className="bg-white dark:bg-gray-800 rounded-2xl border border-gray-100 dark:border-gray-800 p-6 shadow-xl">
          <div className="flex gap-4">
            <div className="w-12 h-12 rounded-xl bg-gray-100 dark:bg-gray-700 overflow-hidden shrink-0">
              <img src={user?.avatar_url || `https://api.dicebear.com/7.x/avataaars/svg?seed=${user?.full_name}`} alt="avatar" />
            </div>
            <button 
              onClick={() => setActiveModal('standard')}
              className="flex-1 text-left px-6 py-3 bg-gray-50 dark:bg-gray-700 hover:bg-gray-100 dark:hover:bg-gray-600 rounded-xl text-gray-400 text-sm font-medium transition-all"
            >
              Share a professional update...
            </button>
          </div>
          <div className="grid grid-cols-3 gap-3 mt-6 border-t border-gray-50 dark:border-gray-700 pt-4">
            <button onClick={() => setActiveModal('video')} className="flex items-center justify-center gap-2 text-[10px] text-gray-600 dark:text-gray-300 font-black uppercase tracking-widest hover:bg-gray-50 dark:hover:bg-gray-700 p-2 rounded-xl transition-all">
              <Video className="w-4 h-4 text-red-500" /> Video
            </button>
            <button onClick={() => setActiveModal('snippet')} className="flex items-center justify-center gap-2 text-[10px] text-gray-600 dark:text-gray-300 font-black uppercase tracking-widest hover:bg-gray-50 dark:hover:bg-gray-700 p-2 rounded-xl transition-all">
              <Terminal className="w-4 h-4 text-blue-500" /> {isIT ? 'Code' : 'Strategy'}
            </button>
            <button onClick={() => setActiveModal('bounty')} className="flex items-center justify-center gap-2 text-[10px] text-gray-600 dark:text-gray-300 font-black uppercase tracking-widest hover:bg-gray-50 dark:hover:bg-gray-700 p-2 rounded-xl transition-all">
              <Award className="w-4 h-4 text-orange-500" /> Bounty
            </button>
          </div>
        </div>

        {/* Posts List: Role and Engagement Ranking  */}
        {loading ? (
          <div className="flex flex-col items-center py-20 gap-4">
            <div className="w-10 h-10 border-4 border-blue-600 border-t-transparent rounded-full animate-spin" />
            <p className="text-xs font-black uppercase tracking-widest text-gray-400">Curating Personalized Feed...</p>
          </div>
        ) : (
          posts.map(post => (
            <motion.div key={post.id} initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} className="bg-white dark:bg-gray-800 rounded-2xl border border-gray-100 dark:border-gray-800 shadow-xl overflow-hidden">
              <div className="p-5 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-12 h-12 rounded-xl bg-blue-50 dark:bg-gray-700 overflow-hidden border border-blue-100 dark:border-gray-600">
                    <img src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${post.author_name}`} alt="user" />
                  </div>
                  <div>
                    <h4 className="font-black text-sm dark:text-white uppercase tracking-tight">{post.author_name}</h4>
                    <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{post.author_role} • {post.author_faculty} Faculty</p>
                  </div>
                </div>
                <button className="text-gray-300 hover:text-gray-600 transition-colors"><MoreHorizontal /></button>
              </div>

              <div className="px-6 pb-6">
                <p className="text-sm dark:text-gray-200 leading-relaxed mb-4">{post.content}</p>
                
                {/* Support for Code Snippets */}
                {post.code && (
                  <div className="relative group">
                    <div className="absolute top-3 right-3 text-[9px] font-black uppercase text-gray-500 group-hover:text-green-400 transition-colors">Source Code</div>
                    <pre className="bg-gray-900 text-green-400 p-6 rounded-2xl font-mono text-[11px] overflow-x-auto shadow-inner border border-gray-800">
                      <code>{post.code}</code>
                    </pre>
                  </div>
                )}

                {/* Requirement: Support for short-form video content  */}
                {post.video_url && (
                  <div className="rounded-2xl overflow-hidden bg-black aspect-video shadow-2xl">
                    <video controls className="w-full h-full object-contain">
                      <source src={post.video_url} type="video/mp4" />
                    </video>
                  </div>
                )}
              </div>

              {/* Requirement: Reactions and Comments  */}
              <div className="px-6 py-4 border-t border-gray-50 dark:border-gray-700 flex items-center justify-between">
                <div className="flex gap-6">
                  <button className="flex items-center gap-2 text-[10px] font-black uppercase tracking-widest text-gray-400 hover:text-blue-600 transition-all">
                    <TrendingUp className="w-4 h-4"/> Insightful ({post.likes || 0})
                  </button>
                  <button className="flex items-center gap-2 text-[10px] font-black uppercase tracking-widest text-gray-400 hover:text-blue-600 transition-all">
                    <MessageSquare className="w-4 h-4"/> Discuss ({post.comments_count || 0})
                  </button>
                </div>
                <button className="flex items-center gap-2 text-[10px] font-black uppercase tracking-widest text-gray-400 hover:text-blue-600 transition-all">
                  <Send className="w-4 h-4"/> Share
                </button>
              </div>
            </motion.div>
          ))
        )}
      </div>

      {/* RIGHT SIDEBAR: Institutional Updates [cite: 35, 60] */}
      <div className="lg:col-span-3 space-y-6">
        <div className="bg-white dark:bg-gray-800 rounded-2xl border border-gray-100 dark:border-gray-800 p-6 shadow-xl sticky top-24">
          <h4 className="font-black text-xs mb-6 dark:text-white uppercase tracking-widest border-b pb-4 border-gray-50 dark:border-gray-700 flex items-center gap-2">
            <Bell size={14} className="text-orange-500" /> Institutional Events
          </h4>
          <div className="space-y-6">
            <div className="group cursor-pointer border-l-4 border-blue-600 pl-4 hover:bg-gray-50 dark:hover:bg-gray-700 py-2 transition-all rounded-r-xl">
              <h5 className="text-[11px] font-black dark:text-gray-200 uppercase tracking-tight leading-tight">Richfield Hackathon 2026</h5>
              <p className="text-[9px] text-gray-400 mt-1 uppercase font-bold tracking-widest">16th - 17th April • 2k Readers</p>
            </div>
            {/* Additional mentoring/events would go here */}
          </div>
        </div>
      </div>

      <CreatePostModal 
        isOpen={!!activeModal} 
        onClose={() => setActiveModal(null)} 
        type={activeModal} 
        isIT={isIT} 
        user={user}
        onPostCreated={loadPosts}
      />
    </div>
  );
};

export default FeedPage;