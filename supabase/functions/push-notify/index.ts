// =====================================================================
// push-notify — turns one `notifications` row into one FCM message
// =====================================================================
// Called by the `dispatch_push` trigger (0015) over the container
// network, with `{ notification_id, user_id }`. It is deliberately the
// only thing in the system that holds the FCM service-account key: that
// key can send a push to any device in the project, so it must never be
// in the Flutter app and never in a table PostgREST can reach.
//
// Deploy with --no-verify-jwt: the caller is Postgres, not a signed-in
// student, so there is no JWT to verify. The shared secret below is what
// authenticates it instead.
//
// Required secrets:
//   PUSH_SHARED_SECRET   same value as the database's app.push_secret
//   FCM_SERVICE_ACCOUNT  the service-account JSON, as one line
//   SUPABASE_URL         injected by the platform
//   SUPABASE_SERVICE_ROLE_KEY  injected by the platform
// =====================================================================

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SHARED_SECRET = Deno.env.get('PUSH_SHARED_SECRET') ?? '';
const SERVICE_ACCOUNT_RAW = Deno.env.get('FCM_SERVICE_ACCOUNT') ?? '';

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

const account: ServiceAccount | null = SERVICE_ACCOUNT_RAW
  ? JSON.parse(SERVICE_ACCOUNT_RAW)
  : null;

const admin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false } },
);

// ---------------------------------------------------------------------
// FCM OAuth
// ---------------------------------------------------------------------
// HTTP v1 wants a bearer token, which means signing a JWT with the
// service account's key. Tokens last an hour; this caches one rather
// than paying a round trip to Google on every single message.
let cachedToken: { value: string; expiresAt: number } | null = null;

async function accessToken(): Promise<string> {
  if (!account) throw new Error('FCM_SERVICE_ACCOUNT is not set');

  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const claim = {
    iss: account.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };

  const encode = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  const unsigned = `${encode({ alg: 'RS256', typ: 'JWT' })}.${encode(claim)}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(account.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(unsigned)),
  );
  const jwt = `${unsigned}.${
    btoa(String.fromCharCode(...signature))
      .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  }`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  if (!response.ok) throw new Error(`FCM auth failed: ${await response.text()}`);

  const token = await response.json();
  cachedToken = { value: token.access_token, expiresAt: now + token.expires_in };
  return cachedToken.value;
}

function pemToBytes(pem: string): ArrayBuffer {
  // The JSON carries the key with literal \n, which survives the env var as
  // two characters rather than a newline.
  const body = pem
    .replace(/\\n/g, '\n')
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const raw = atob(body);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

// ---------------------------------------------------------------------

Deno.serve(async (request) => {
  if (SHARED_SECRET === '' ||
      request.headers.get('Authorization') !== `Bearer ${SHARED_SECRET}`) {
    return new Response('forbidden', { status: 403 });
  }

  let body: { notification_id?: string; user_id?: string };
  try {
    body = await request.json();
  } catch {
    return new Response('bad request', { status: 400 });
  }

  const { notification_id, user_id } = body;
  if (!notification_id || !user_id) {
    return new Response('bad request', { status: 400 });
  }

  // The partition key is user_id, so both halves of the key are needed to
  // reach the row without scanning all eight partitions.
  const { data: note } = await admin
    .from('notifications')
    .select('id, user_id, kind, title, body, target_id, deep_link, pushed_at')
    .eq('user_id', user_id)
    .eq('id', notification_id)
    .maybeSingle();

  if (!note) return Response.json({ sent: 0, reason: 'gone' });
  // Already delivered — the trigger and the retry sweep can both reach the
  // same row, and a student should not get the same message twice.
  if (note.pushed_at) return Response.json({ sent: 0, reason: 'already pushed' });

  const { data: devices } = await admin
    .from('user_devices')
    .select('push_token, platform')
    .eq('user_id', user_id)
    .eq('push_enabled', true);

  if (!devices || devices.length === 0) {
    // Nothing to send to. Stamped anyway, so the sweep stops retrying a
    // student who has never opened the app on a phone.
    await stampPushed(user_id, notification_id);
    return Response.json({ sent: 0, reason: 'no devices' });
  }

  const token = await accessToken();
  const endpoint =
    `https://fcm.googleapis.com/v1/projects/${account!.project_id}/messages:send`;

  let sent = 0;
  const dead: string[] = [];

  for (const device of devices) {
    // `data` carries what the app routes on; `notification` is what the
    // system tray draws when the app is not running. Both are needed:
    // data-only messages are not shown by Android on their own, and a
    // notification-only message reaches no Dart code to route with.
    const message = {
      message: {
        token: device.push_token,
        notification: { title: note.title, body: note.body ?? '' },
        data: {
          kind: String(note.kind),
          deep_link: note.deep_link ?? '',
          target_id: note.target_id ?? '',
        },
        android: {
          priority: 'HIGH',
          notification: {
            channel_id: 'campus_connect_default',
            // One notification per conversation rather than a stack of
            // twenty from the same person.
            tag: note.deep_link ?? String(note.id),
          },
        },
        apns: {
          headers: {
            // 10 = deliver now. The default (5) lets iOS hold a message back
            // to save battery, which for a chat message means it arrives
            // minutes after the conversation moved on.
            'apns-priority': '10',
            // Same collapse behaviour as the Android `tag`: a second message
            // in a thread replaces the first rather than stacking.
            'apns-collapse-id': (note.deep_link ?? String(note.id)).slice(0, 64),
          },
          payload: {
            aps: {
              sound: 'default',
              'thread-id': note.deep_link ?? '',
              // Required for iOS to hand the `data` block to Dart when the
              // app is in the background — without it the tap opens the app
              // with no idea which conversation it was about.
              'content-available': 1,
            },
          },
        },
      },
    };

    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(message),
    });

    if (response.ok) {
      sent++;
      continue;
    }

    const detail = await response.text();
    // A token for an app that has been uninstalled. Left in place it
    // would fail on every message this student is ever sent.
    if (detail.includes('UNREGISTERED') || detail.includes('INVALID_ARGUMENT')) {
      dead.push(device.push_token);
    } else {
      console.error(`fcm ${response.status}: ${detail}`);
    }
  }

  if (dead.length > 0) {
    await admin.from('user_devices').delete().in('push_token', dead);
  }

  // Stamped whatever happened. A row that keeps failing would otherwise be
  // retried every minute for a day.
  await stampPushed(user_id, notification_id);
  return Response.json({ sent, dead: dead.length });
});

async function stampPushed(userId: string, id: string) {
  await admin
    .from('notifications')
    .update({ pushed_at: new Date().toISOString() })
    .eq('user_id', userId)
    .eq('id', id);
}
