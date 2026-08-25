import axios from 'axios';

const API = axios.create({
  baseURL: 'http://localhost:5000/api', // Your Node.js server port
});

export const fetchPosts = () => API.get('/posts');
export const createPost = (postData) => API.post('/posts', postData);
export const getProfile = (id) => API.get(`/profiles/${id}`);
export const updateProfile = (id, profileData) => API.put(`/profiles/${id}`, profileData);

export default API;