// Firebase Messaging — service worker para push em background na web.
// Recebe push FCM quando o app está fechado/minimizado e mostra notificação nativa.
// Alinhado a notificationBranding.ts (cores por módulo) e fcm_service.dart (routing).

importScripts('https://www.gstatic.com/firebasejs/12.17.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.17.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyB74Dm4WiLMHYdSiWPvB2yTzNWsINVBvWo',
  authDomain: 'gestaoyahweh-21e23.firebaseapp.com',
  projectId: 'gestaoyahweh-21e23',
  storageBucket: 'gestaoyahweh-21e23.firebasestorage.app',
  messagingSenderId: '157235497908',
  appId: '1:157235497908:web:4f702c7a670d76204ac0e1',
});

var messaging = firebase.messaging();

/** Cores por módulo — alinhado a notificationBranding.ts moduleAccentHex. */
var MODULE_COLORS = {
  aviso: '#0EA5E9',
  evento: '#F97316',
  escala: '#14B8A6',
  fornecedor_agenda: '#475569',
  pastoral: '#EAB308',
  devocional: '#6366F1',
  aniversario: '#E11D48',
  financeiro: '#37474F',
  membro: '#2563EB',
  chat: '#8B5CF6',
  generico: '#3B82F6',
};

function colorForModule(mod) {
  return MODULE_COLORS[mod] || MODULE_COLORS.generico;
}

/** Routing de notificação para URL do app — alinhado a fcm_service.routeNotificationTap. */
function buildClickUrl(data) {
  data = data || {};
  var base = (self.location.origin || 'https://gestaoyahweh.com.br');
  var type = (data.type || '').toString().trim();
  var threadId = (data.threadId || '').toString().trim();
  var tenantId = (data.tenantId || '').toString().trim();
  // Chat: abrir o painel JÁ na conversa/grupo (query param lido no main.dart web).
  if ((type === 'novo_chat' || type === 'chat_message' || type === 'church_chat') && threadId) {
    var u = base + '/painel?gyChat=' + encodeURIComponent(threadId);
    if (tenantId) u += '&gyTenant=' + encodeURIComponent(tenantId);
    return u;
  }
  // Default: abrir painel
  return base + '/';
}

// Background message handler — push FCM quando o app está em background/fechado.
messaging.onBackgroundMessage(function (payload) {
  var title = (payload.notification && payload.notification.title) || 'Gestão Yahweh';
  var body = (payload.notification && payload.notification.body) || '';
  var imageUrl = payload.notification && payload.notification.imageUrl;
  var data = payload.data || {};
  var module = data.gy_module || 'generico';

  var options = {
    body: body,
    icon: imageUrl || '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.type || 'gyh_notification',
    data: data,
    dir: 'auto',
    requireInteraction: false,
    vibrate: [200, 100, 200],
    actions: [
      { action: 'open', title: 'Abrir' },
      { action: 'dismiss', title: 'Ignorar' },
    ],
  };

  return self.registration.showNotification(title, options);
});

// Click handler — abrir o app na página certa.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var data = event.notification.data || {};
  var url = buildClickUrl(data);

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (clients) {
      // Se já há uma janela do app aberta, focar nela.
      for (var i = 0; i < clients.length; i++) {
        var c = clients[i];
        if (c.url && c.url.indexOf(self.location.origin) === 0 && 'focus' in c) {
          c.navigate(url);
          return c.focus();
        }
      }
      // Senão, abrir nova janela.
      if (self.clients.openWindow) {
        return self.clients.openWindow(url);
      }
    })
  );
});
