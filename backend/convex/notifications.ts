import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";

// Required Convex environment variables (set in Convex dashboard):
//   APNS_KEY_ID        — 10-character key ID from Apple Developer
//   APNS_TEAM_ID       — 10-character Team ID from Apple Developer
//   APNS_PRIVATE_KEY   — p8 private key content (PEM, without BEGIN/END lines, single line)
//   APNS_BUNDLE_ID     — e.g. "com.yourcompany.MonkeyHub"
//   APNS_ENVIRONMENT   — "production" | "sandbox" (default: "sandbox")

export const sendMessagePush = internalAction({
  args: {
    roomId: v.id("rooms"),
    messageId: v.id("messages"),
    senderId: v.id("users"),
    senderName: v.string(),
    content: v.string(),
    type: v.string(),
  },
  handler: async (ctx, { roomId, senderId, senderName, content, type }) => {
    const keyId = process.env.APNS_KEY_ID;
    const teamId = process.env.APNS_TEAM_ID;
    const privateKeyBase64 = process.env.APNS_PRIVATE_KEY;
    const bundleId = process.env.APNS_BUNDLE_ID;
    const environment = process.env.APNS_ENVIRONMENT ?? "sandbox";

    if (!keyId || !teamId || !privateKeyBase64 || !bundleId) {
      // Push not configured — skip silently
      return;
    }

    // Fetch all room members except the sender
    const members: Array<{ deviceTokens: string[] }> = await ctx.runQuery(
      internal.rooms.getMembersWithTokens,
      { roomId, excludeUserId: senderId }
    );

    const tokens: string[] = [];
    for (const member of members) {
      for (const token of member.deviceTokens ?? []) {
        tokens.push(token);
      }
    }
    if (tokens.length === 0) return;

    const jwt = await buildApnsJwt(teamId, keyId, privateKeyBase64);
    const host =
      environment === "production"
        ? "https://api.push.apple.com"
        : "https://api.sandbox.push.apple.com";

    const body =
      type === "text"
        ? content
        : type === "image"
        ? "📷 Image"
        : type === "video"
        ? "🎥 Video"
        : type === "audio"
        ? "🎵 Audio"
        : "New message";

    const payload = JSON.stringify({
      aps: {
        alert: { title: senderName, body },
        sound: "default",
        badge: 1,
        "content-available": 1,
        "mutable-content": 1,
        category: "CHAT_MESSAGE",
      },
      roomId,
      senderName,
      type,
    });

    const results = await Promise.allSettled(
      tokens.map((token) =>
        fetch(`${host}/3/device/${token}`, {
          method: "POST",
          headers: {
            authorization: `bearer ${jwt}`,
            "apns-topic": bundleId,
            "apns-push-type": "alert",
            "content-type": "application/json",
          },
          body: payload,
        })
      )
    );

    // Log failures (don't throw — push failures are non-fatal)
    for (const result of results) {
      if (result.status === "rejected") {
        console.error("APNs push failed:", result.reason);
      }
    }
  },
});

// Build a signed JWT for APNs authentication (ES256)
async function buildApnsJwt(
  teamId: string,
  keyId: string,
  privateKeyBase64: string
): Promise<string> {
  const issuedAt = Math.floor(Date.now() / 1000);

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: issuedAt }));
  const signingInput = `${header}.${claims}`;

  // Import the private key (PKCS8 PEM → CryptoKey)
  const pemBody = privateKeyBase64
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");

  const keyBuffer = base64ToArrayBuffer(pemBody);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBuffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  const encoder = new TextEncoder();
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    encoder.encode(signingInput)
  );

  return `${signingInput}.${base64url(signature)}`;
}

function base64url(input: string | ArrayBuffer): string {
  let str: string;
  if (typeof input === "string") {
    str = btoa(input);
  } else {
    const bytes = new Uint8Array(input);
    str = btoa(String.fromCharCode(...bytes));
  }
  return str.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}
