import { internalAction, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import type { Id } from "./_generated/dataModel";

// Direct VoIP push delivery — wakes a *killed* app for CallKit (iOS) or
// ConnectionService (Android). Runs alongside the OneSignal push in
// `calls.sendCallPush` for now; OneSignal stays as a soft fallback.
//
// iOS: APNs HTTP/2 with PushKit topic `<bundle>.voip`, signed with an ES256
//      JWT from the developer-account `.p8` key.
// Android: FCM HTTP v1, data-only `priority: high` message. Authenticated
//      with an OAuth2 access token minted from the service-account JSON.
//
// Required Convex env vars (set in dashboard):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_KEY_P8, APNS_SANDBOX
//   FCM_SERVICE_ACCOUNT_JSON
//
// Any missing piece on a given platform → that platform's branch logs and
// skips (the other can still deliver). Never throws back to the caller.

// Returns every push-eligible device row for [userId]. If the registry is
// empty (older client that hasn't relogged since the migration), synthesizes
// a single fallback row from the legacy `users.voipToken`/`fcmToken` so
// pushes keep flowing until the next login refreshes the per-device record.
//
// Each row carries its own `_id` so the dead-token cleanup path can target
// the specific device — `deviceRowId: null` marks the legacy fallback (we
// clear the user-level field instead).
export const _loadUserDevices = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const rows = await ctx.db
      .query("userDevices")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();
    if (rows.length > 0) {
      return rows.map((r) => ({
        deviceRowId: r._id,
        legacy: false as const,
        deviceId: r.deviceId,
        platform: r.platform,
        voipToken: r.voipToken,
        fcmToken: r.fcmToken,
      }));
    }
    const u = await ctx.db.get(userId);
    if (!u) return [];
    if (!u.voipToken && !u.fcmToken) return [];
    return [
      {
        deviceRowId: null,
        legacy: true as const,
        deviceId: "_legacy",
        platform: u.voipToken ? "ios" : "android",
        voipToken: u.voipToken,
        fcmToken: u.fcmToken,
      },
    ];
  },
});

export const sendVoip = internalAction({
  args: {
    callId: v.id("calls"),
    calleeId: v.id("users"),
    callerId: v.id("users"),
    callerName: v.string(),
    type: v.string(),
    roomId: v.id("rooms"),
  },
  handler: async (ctx, args) => {
    const devices = await ctx.runQuery(internal.voipPush._loadUserDevices, {
      userId: args.calleeId,
    });
    if (devices.length === 0) {
      console.log("sendVoip: no devices for callee — OneSignal-only path");
      return;
    }
    const payload = {
      kind: "invite",
      callId: args.callId.toString(),
      callerId: args.callerId.toString(),
      callerName: args.callerName,
      callerHandle: args.callerName,
      callType: args.type,
      roomId: args.roomId.toString(),
    };
    // Fan out in parallel — one slow APNs round-trip shouldn't block the
    // sibling devices. allSettled because we never want one failure to
    // suppress logging for the others.
    await Promise.allSettled(
      devices.map((d) => pushToDevice(ctx, args.calleeId, d, payload)),
    );
  },
});

// Sent to every sibling iOS device when one device accepts or rejects a
// ringing call, so CallKit can dismiss with `.answeredElsewhere` even on a
// killed app where the in-app `taken` signal can't be delivered in time.
// The accepting device is excluded via `excludeDeviceId`.
export const sendVoipTaken = internalAction({
  args: {
    callId: v.id("calls"),
    calleeId: v.id("users"),
    excludeDeviceId: v.optional(v.union(v.string(), v.null())),
    reason: v.string(), // "accepted" | "rejected"
  },
  handler: async (ctx, args) => {
    const devices = await ctx.runQuery(internal.voipPush._loadUserDevices, {
      userId: args.calleeId,
    });
    const targets = devices.filter(
      (d) =>
        d.voipToken &&
        d.platform !== "ios-simulator" &&
        d.deviceId !== args.excludeDeviceId,
    );
    if (targets.length === 0) return;
    const payload = {
      kind: "taken",
      callId: args.callId.toString(),
      reason: args.reason,
    };
    await Promise.allSettled(
      targets.map((d) => pushToDevice(ctx, args.calleeId, d, payload)),
    );
  },
});

type DeviceRow =
  | {
      deviceRowId: Id<"userDevices">;
      legacy: false;
      deviceId: string;
      platform: string;
      voipToken?: string;
      fcmToken?: string;
    }
  | {
      deviceRowId: null;
      legacy: true;
      deviceId: string;
      platform: string;
      voipToken?: string;
      fcmToken?: string;
    };

async function pushToDevice(
  ctx: any,
  userId: Id<"users">,
  d: DeviceRow,
  payload: Record<string, unknown>,
): Promise<void> {
  // Skip simulator rows for APNs (PushKit doesn't reach simulators); the
  // realtime subscription path covers them.
  if (d.voipToken && d.platform !== "ios-simulator") {
    try {
      await sendApnsVoip(d.voipToken, payload);
      console.log(`sendVoip: APNs OK device=${d.deviceId}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`sendVoip: APNs failed device=${d.deviceId}: ${msg}`);
      // Apple replies 410 (Unregistered) or 400 (BadDeviceToken) when
      // the token has been revoked — usually after we miss the iOS 13+
      // 5-second `reportNewIncomingCall` deadline once too often.
      // Clear just this device's token; siblings keep theirs.
      if (msg.startsWith("APNS_BAD_TOKEN")) {
        if (!d.legacy) {
          await ctx.runMutation(
            internal.voipTokens.clearVoipTokenForDeviceInternal,
            { deviceRowId: d.deviceRowId },
          );
        } else {
          await ctx.runMutation(
            internal.voipTokens.clearLegacyVoipTokenInternal,
            { userId },
          );
        }
        console.warn(
          `sendVoip: cleared voipToken device=${d.deviceId} after ${msg}`,
        );
      }
    }
  }
  if (d.fcmToken) {
    try {
      await sendFcmData(d.fcmToken, payload);
      console.log(`sendVoip: FCM OK device=${d.deviceId}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`sendVoip: FCM failed device=${d.deviceId}: ${msg}`);
      if (msg.startsWith("FCM_BAD_TOKEN")) {
        if (!d.legacy) {
          await ctx.runMutation(
            internal.voipTokens.clearFcmTokenForDeviceInternal,
            { deviceRowId: d.deviceRowId },
          );
        } else {
          await ctx.runMutation(
            internal.voipTokens.clearLegacyFcmTokenInternal,
            { userId },
          );
        }
        console.warn(
          `sendVoip: cleared fcmToken device=${d.deviceId} after ${msg}`,
        );
      }
    }
  }
}

// ────────────────────────── APNs (iOS PushKit) ──────────────────────────

async function sendApnsVoip(
  voipToken: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const bundleId = process.env.APNS_BUNDLE_ID;
  const keyP8 = process.env.APNS_KEY_P8;
  const sandbox = (process.env.APNS_SANDBOX ?? "true") === "true";
  if (!keyId || !teamId || !bundleId || !keyP8) {
    throw new Error(
      "missing APNS_KEY_ID / APNS_TEAM_ID / APNS_BUNDLE_ID / APNS_KEY_P8",
    );
  }
  const iat = Math.floor(Date.now() / 1000);
  const jwt = await signJwt(
    { alg: "ES256", typ: "JWT", kid: keyId },
    { iss: teamId, iat },
    keyP8,
    "ES256",
  );
  const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const url = `https://${host}/3/device/${voipToken}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": `${bundleId}.voip`,
      "apns-push-type": "voip",
      "apns-priority": "10",
      "apns-expiration": "0",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = await res.text();
    // 410 Unregistered / 400 BadDeviceToken → caller should clear the
    // stored token. Use a sentinel prefix so the catch site can branch
    // on it without parsing the whole status line.
    if (res.status === 410 || res.status === 400) {
      throw new Error(`APNS_BAD_TOKEN:${res.status}:${body}`);
    }
    throw new Error(`APNs HTTP ${res.status}: ${body}`);
  }
}

// ────────────────────────── FCM (Android) ──────────────────────────

async function sendFcmData(
  fcmToken: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const saJson = process.env.FCM_SERVICE_ACCOUNT_JSON;
  if (!saJson) throw new Error("missing FCM_SERVICE_ACCOUNT_JSON");
  const sa = JSON.parse(saJson) as {
    client_email: string;
    private_key: string;
    project_id: string;
  };
  const accessToken = await fcmAccessToken(sa);
  // FCM v1 data values must all be strings.
  const data: Record<string, string> = {};
  for (const k of Object.keys(payload)) data[k] = String(payload[k]);
  const body = {
    message: {
      token: fcmToken,
      data,
      android: { priority: "high", ttl: "60s" },
    },
  };
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    },
  );
  if (!res.ok) {
    const respBody = await res.text();
    // FCM signals dead tokens via UNREGISTERED (404) or INVALID_ARGUMENT
    // (400) — surface them so the caller can clear the stored token.
    if (
      res.status === 404 ||
      res.status === 400 ||
      respBody.includes("UNREGISTERED")
    ) {
      throw new Error(`FCM_BAD_TOKEN:${res.status}:${respBody}`);
    }
    throw new Error(`FCM HTTP ${res.status}: ${respBody}`);
  }
}

async function fcmAccessToken(sa: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const iat = Math.floor(Date.now() / 1000);
  const jwt = await signJwt(
    { alg: "RS256", typ: "JWT" },
    {
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat,
      exp: iat + 3600,
    },
    sa.private_key,
    "RS256",
  );
  const params = new URLSearchParams();
  params.set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
  params.set("assertion", jwt);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });
  if (!res.ok) {
    throw new Error(`FCM OAuth HTTP ${res.status}: ${await res.text()}`);
  }
  const j = (await res.json()) as { access_token: string };
  return j.access_token;
}

// ────────────────────────── JWT signing helpers ──────────────────────────

async function signJwt(
  header: Record<string, unknown>,
  claims: Record<string, unknown>,
  privateKeyPem: string,
  alg: "ES256" | "RS256",
): Promise<string> {
  const enc = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;
  const der = pemToDer(privateKeyPem);
  const importAlg: AlgorithmIdentifier | EcKeyImportParams | RsaHashedImportParams =
    alg === "ES256"
      ? { name: "ECDSA", namedCurve: "P-256" }
      : { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };
  const signAlg: AlgorithmIdentifier | EcdsaParams =
    alg === "ES256"
      ? { name: "ECDSA", hash: "SHA-256" }
      : { name: "RSASSA-PKCS1-v1_5" };
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    importAlg,
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    signAlg,
    key,
    new TextEncoder().encode(enc),
  );
  return `${enc}.${b64url(new Uint8Array(sig))}`;
}

function b64url(input: string | Uint8Array): string {
  let bytes: Uint8Array;
  if (typeof input === "string") {
    bytes = new TextEncoder().encode(input);
  } else {
    bytes = input;
  }
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToDer(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
