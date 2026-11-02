// Service Worker de Firebase Cloud Messaging.
// Debe vivir en la raíz del sitio (junto a index.html), con este nombre exacto.

importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: "AIzaSyAFucnRd_ZB81l4rH7bAeNh3STqL4AN4R4",
  authDomain: "sistema-escolar-a5c31.firebaseapp.com",
  databaseURL: "https://sistema-escolar-a5c31-default-rtdb.firebaseio.com",
  projectId: "sistema-escolar-a5c31",
  storageBucket: "sistema-escolar-a5c31.firebasestorage.app",
  messagingSenderId: "234198294318",
  appId: "1:234198294318:web:a65521e9607753d68664bf"
});

const messaging = firebase.messaging();

// Los avisos llegan con título y texto, y el navegador los muestra solo (con el celular
// bloqueado o el navegador cerrado). No hace falta mostrarlos a mano: se duplicarían.
