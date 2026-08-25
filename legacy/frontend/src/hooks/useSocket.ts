import { useEffect, useRef, useCallback } from 'react';
import { io, Socket } from 'socket.io-client';
import { useAuth } from './useAuth';

let socket: Socket | null = null;

export const useSocket = () => {
  const { user, session } = useAuth();
  const socketRef = useRef<Socket | null>(null);

  useEffect(() => {
    if (!user || !session) return;
    if (socketRef.current?.connected) return;

    socket = io('/', {
      auth: { userId: user.id, token: session.access_token },
      transports: ['websocket'],
    });

    socketRef.current = socket;
    socket.connect();

    return () => {
      socket?.disconnect();
      socketRef.current = null;
    };
  }, [user?.id, session?.access_token]);

  const on = useCallback((event: string, handler: (...args: any[]) => void) => {
    socketRef.current?.on(event, handler);
    return () => socketRef.current?.off(event, handler);
  }, []);

  const emit = useCallback((event: string, data?: any) => {
    socketRef.current?.emit(event, data);
  }, []);

  return { socket: socketRef.current, on, emit };
};