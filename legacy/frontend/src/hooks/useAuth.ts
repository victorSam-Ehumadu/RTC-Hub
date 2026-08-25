import { useState, useEffect, createContext, useContext } from 'react';
import { supabase } from '../lib/supabaseClient';
import api from '../lib/api';

interface Profile {
  id: string;
  role: 'STUDENT' | 'ALUMNI' | 'BUSINESS' | 'ADMIN';
  status: string;
  full_name: string;
  email: string;
  avatar_url?: string;
  course?: string;
  faculty?: string;
  company_name?: string;
  profile_completeness?: number;
  [key: string]: any;
}

interface AuthContextType {
  user: Profile | null;
  session: any;
  loading: boolean;
  signOut: () => Promise<void>;
  refreshUser: () => Promise<void>;
}

export const AuthContext = createContext<AuthContextType>({
  user: null, session: null, loading: true,
  signOut: async () => {}, refreshUser: async () => {},
});

export const useAuth = () => useContext(AuthContext);

export const AuthProvider = ({ children }: { children: React.ReactNode }) => {
  const [user, setUser] = useState<Profile | null>(null);
  const [session, setSession] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  const fetchProfile = async () => {
    try {
      const { data } = await api.get('/auth/me');
      setUser(data.user);
    } catch {
      setUser(null);
    }
  };

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      if (session) fetchProfile().finally(() => setLoading(false));
      else setLoading(false);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, session) => {
      setSession(session);
      if (session) await fetchProfile();
      else setUser(null);
      setLoading(false);
    });

    return () => subscription.unsubscribe();
  }, []);

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setSession(null);
  };

  return (
    <AuthContext.Provider value={{ user, session, loading, signOut, refreshUser: fetchProfile }}>
      {children}
    </AuthContext.Provider>
  );
};