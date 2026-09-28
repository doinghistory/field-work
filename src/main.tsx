import React from 'react';import{createRoot}from'react-dom/client';import App from './App';import './style.css';import'maplibre-gl/dist/maplibre-gl.css';
createRoot(document.getElementById('root')!).render(<React.StrictMode><App/></React.StrictMode>);
if('serviceWorker'in navigator)window.addEventListener('load',()=>navigator.serviceWorker.register(import.meta.env.BASE_URL+'sw.js').catch(()=>{}));
