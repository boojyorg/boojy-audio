// Boojy Audio Service Worker - PWA Offline Support
// Caches app shell, WASM engine, and static assets for offline use

const CACHE_NAME = 'boojy-audio-v1';
const WASM_CACHE_NAME = 'boojy-audio-wasm-v1';

// Core files to cache for app shell
const APP_SHELL_FILES = [
  '/',
  '/index.html',
  '/manifest.json',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/Icon-maskable-192.png',
  '/icons/Icon-maskable-512.png',
];

// WASM engine files (cached separately for efficient updates)
const WASM_FILES = [
  '/wasm/engine.js',
  '/wasm/engine_bg.wasm',
];

// Install event - cache app shell and WASM
self.addEventListener('install', (event) => {
  console.log('[ServiceWorker] Installing...');

  event.waitUntil(
    Promise.all([
      // Cache app shell
      caches.open(CACHE_NAME).then((cache) => {
        console.log('[ServiceWorker] Caching app shell');
        return cache.addAll(APP_SHELL_FILES);
      }),
      // Cache WASM files separately
      caches.open(WASM_CACHE_NAME).then((cache) => {
        console.log('[ServiceWorker] Caching WASM engine');
        return cache.addAll(WASM_FILES);
      }),
    ]).then(() => {
      console.log('[ServiceWorker] Installation complete');
      // Activate immediately
      return self.skipWaiting();
    })
  );
});

// Activate event - cleanup old caches
self.addEventListener('activate', (event) => {
  console.log('[ServiceWorker] Activating...');

  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cacheName) => {
          // Delete old caches that don't match current version
          if (cacheName !== CACHE_NAME && cacheName !== WASM_CACHE_NAME) {
            console.log('[ServiceWorker] Deleting old cache:', cacheName);
            return caches.delete(cacheName);
          }
        })
      );
    }).then(() => {
      console.log('[ServiceWorker] Activation complete');
      // Take control of all clients immediately
      return self.clients.claim();
    })
  );
});

// Fetch event - serve from cache with network fallback
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests
  if (request.method !== 'GET') {
    return;
  }

  // Skip cross-origin requests
  if (url.origin !== location.origin) {
    return;
  }

  // Handle WASM files - cache first for performance
  if (url.pathname.startsWith('/wasm/')) {
    event.respondWith(
      caches.open(WASM_CACHE_NAME).then((cache) => {
        return cache.match(request).then((cachedResponse) => {
          if (cachedResponse) {
            return cachedResponse;
          }
          // Not in cache, fetch and cache
          return fetch(request).then((networkResponse) => {
            cache.put(request, networkResponse.clone());
            return networkResponse;
          });
        });
      })
    );
    return;
  }

  // Handle Flutter files - network first with cache fallback
  // This ensures users get updates but can still use app offline
  if (url.pathname.includes('main.dart.js') ||
      url.pathname.includes('flutter_bootstrap.js') ||
      url.pathname.includes('flutter.js')) {
    event.respondWith(
      fetch(request)
        .then((networkResponse) => {
          // Cache the fresh response
          return caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, networkResponse.clone());
            return networkResponse;
          });
        })
        .catch(() => {
          // Network failed, try cache
          return caches.match(request);
        })
    );
    return;
  }

  // Handle app shell files - cache first
  event.respondWith(
    caches.match(request).then((cachedResponse) => {
      if (cachedResponse) {
        // Return cached version, but fetch update in background
        fetch(request).then((networkResponse) => {
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, networkResponse);
          });
        }).catch(() => {});
        return cachedResponse;
      }

      // Not in cache, fetch from network
      return fetch(request).then((networkResponse) => {
        // Cache successful responses
        if (networkResponse && networkResponse.status === 200) {
          const responseClone = networkResponse.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(request, responseClone);
          });
        }
        return networkResponse;
      });
    })
  );
});

// Handle messages from the main app
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }

  if (event.data && event.data.type === 'CLEAR_CACHE') {
    event.waitUntil(
      caches.keys().then((cacheNames) => {
        return Promise.all(
          cacheNames.map((cacheName) => caches.delete(cacheName))
        );
      }).then(() => {
        console.log('[ServiceWorker] All caches cleared');
      })
    );
  }
});

// Background sync for project saves (when online)
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-projects') {
    console.log('[ServiceWorker] Background sync: projects');
    // Future: sync projects to cloud when online
  }
});

console.log('[ServiceWorker] Loaded');
