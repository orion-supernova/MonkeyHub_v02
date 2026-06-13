import {
  mutation,
  query,
  action,
  internalAction,
  internalMutation,
} from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";

// ────────────────────────────── helpers ──────────────────────────────

const CALL_RING_TIMEOUT_MS = 30 * 1000; // missed after 30s un-answered

async function isPairBlocked(
  ctx: any,
  a: any,
  b: any,
): Promise<boolean> {
  const ab = await ctx.db
    .query("blocks")
    .withIndex("by_pair", (q: any) => q.eq("userId", a).eq("blockedUserId", b))
    .first();
  if (ab) return true;
  const ba = await ctx.db
    .query("blocks")
    .withIndex("by_pair", (q: any) => q.eq("userId", b).eq("blockedUserId", a))
    .first();
  return !!ba;
}

async function assertCallParticipant(ctx: any, callId: any, userId: any) {
  const call = await ctx.db.get(callId);
  if (!call) throw new Error("CALL_NOT_FOUND");
  const u = userId.toString();
  if (call.callerId.toString() !== u && call.calleeId.toString() !== u) {
    throw new Error("NOT_A_PARTICIPANT");
  }
  return call;
}

// Cascade delete every signal for [callId] except any id in [keep] (the
// terminal bye/reject/cancel/taken signals we just inserted, which a
// subscriber still needs to see). Called after every terminal-state
// transition so late-arriving ICE candidates can't race into a re-entered
// session.
async function purgeCallSignals(
  ctx: any,
  callId: any,
  keep?: any | any[],
) {
  const keepIds = new Set<string>();
  if (Array.isArray(keep)) {
    for (const k of keep) if (k) keepIds.add(k.toString());
  } else if (keep) {
    keepIds.add(keep.toString());
  }
  const rows = await ctx.db
    .query("callSignals")
    .withIndex("by_call", (q: any) => q.eq("callId", callId))
    .collect();
  for (const r of rows) {
    if (keepIds.has(r._id.toString())) continue;
    await ctx.db.delete(r._id);
  }
}

// ────────────────────────── initiate / lifecycle ──────────────────────────

export const initiate = mutation({
  args: {
    callerId: v.id("users"),
    calleeId: v.id("users"),
    roomId: v.id("rooms"),
    type: v.string(), // "audio" | "video"
  },
  handler: async (ctx, { callerId, calleeId, roomId, type }) => {
    if (callerId.toString() === calleeId.toString()) {
      throw new Error("CANNOT_CALL_SELF");
    }
    if (type !== "audio" && type !== "video") throw new Error("BAD_CALL_TYPE");

    // Honor block list — generic error so we don't reveal who blocked whom.
    if (await isPairBlocked(ctx, callerId, calleeId)) {
      throw new Error("CALL_FAILED");
    }

    // Membership sanity check: both users must belong to the room.
    const callerMembership = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) =>
        q.eq("roomId", roomId).eq("userId", callerId),
      )
      .first();
    const calleeMembership = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) =>
        q.eq("roomId", roomId).eq("userId", calleeId),
      )
      .first();
    if (!callerMembership || !calleeMembership) {
      throw new Error("NOT_A_MEMBER");
    }

    // Reject if either user is already in a live call (ringing / active).
    for (const uid of [callerId, calleeId]) {
      const liveAsCallee = await ctx.db
        .query("calls")
        .withIndex("by_callee_status", (q) =>
          q.eq("calleeId", uid).eq("status", "ringing"),
        )
        .first();
      const liveAsCalleeActive = await ctx.db
        .query("calls")
        .withIndex("by_callee_status", (q) =>
          q.eq("calleeId", uid).eq("status", "active"),
        )
        .first();
      const liveAsCaller = await ctx.db
        .query("calls")
        .withIndex("by_caller_status", (q) =>
          q.eq("callerId", uid).eq("status", "ringing"),
        )
        .first();
      const liveAsCallerActive = await ctx.db
        .query("calls")
        .withIndex("by_caller_status", (q) =>
          q.eq("callerId", uid).eq("status", "active"),
        )
        .first();
      if (
        liveAsCallee ||
        liveAsCalleeActive ||
        liveAsCaller ||
        liveAsCallerActive
      ) {
        throw new Error("BUSY");
      }
    }

    const caller = await ctx.db.get(callerId);
    const callerName = caller?.name ?? caller?.username ?? "Someone";

    const callId = await ctx.db.insert("calls", {
      callerId,
      calleeId,
      roomId,
      type,
      status: "ringing",
      startedAt: Date.now(),
    });

    // Surface an "invite" signal IMMEDIATELY. Every callee device with an
    // active `signalsForUser` subscription receives it within ~50–150ms,
    // which lets the in-app IncomingCallScreen open before the caller has
    // finished getUserMedia/createOffer (otherwise the screen waits for
    // the `offer` signal — adds 500ms+ on first call). The eventual offer
    // hydrates the same session (see CallService._onRemoteOffer).
    await ctx.db.insert("callSignals", {
      callId,
      fromUserId: callerId,
      toUserId: calleeId,
      kind: "invite",
      payload: JSON.stringify({
        callerName,
        type,
        roomId: roomId.toString(),
      }),
      createdAt: Date.now(),
      consumed: false,
    });

    // Fire push so the callee's app wakes if backgrounded.
    await ctx.scheduler.runAfter(0, internal.calls.sendCallPush, {
      callId,
      calleeId,
      callerId,
      callerName,
      type,
      roomId,
    });

    // Direct VoIP push (APNs PushKit + FCM data-only). This is what wakes a
    // *killed* app into the native CallKit / ConnectionService UI. Runs in
    // parallel with the OneSignal push; either path can carry the wake-up,
    // and the OneSignal path is a fallback if tokens are missing.
    await ctx.scheduler.runAfter(0, internal.voipPush.sendVoip, {
      callId,
      calleeId,
      callerId,
      callerName,
      type,
      roomId,
    });

    // Auto-mark as "missed" if still ringing after the timeout.
    await ctx.scheduler.runAfter(
      CALL_RING_TIMEOUT_MS,
      internal.calls.expireRingingCall,
      { callId },
    );

    return callId;
  },
});

export const accept = mutation({
  args: {
    callId: v.id("calls"),
    userId: v.id("users"),
    acceptingDeviceId: v.optional(v.string()),
  },
  handler: async (ctx, { callId, userId, acceptingDeviceId }) => {
    const call = await assertCallParticipant(ctx, callId, userId);
    if (call.calleeId.toString() !== userId.toString()) {
      throw new Error("ONLY_CALLEE_CAN_ACCEPT");
    }
    if (call.status !== "ringing") throw new Error("NOT_RINGING");
    await ctx.db.patch(callId, {
      status: "active",
      acceptedAt: Date.now(),
      // Recorded so sibling devices' active-call subscriptions can compare
      // against their own deviceId and render the "Move call here" pill.
      acceptingDeviceId: acceptingDeviceId ?? undefined,
    });
    // Tell every other device of the callee to dismiss its ringer. All
    // callee devices share the `toUserId == calleeId` subscription; the
    // accepting device filters its own echo via `byDeviceId`.
    await ctx.db.insert("callSignals", {
      callId,
      fromUserId: userId,
      toUserId: call.calleeId,
      kind: "taken",
      payload: JSON.stringify({
        reason: "accepted",
        byDeviceId: acceptingDeviceId ?? null,
      }),
      createdAt: Date.now(),
      consumed: false,
    });
    // For killed-iOS siblings (subscription not alive), fan a PushKit
    // payload with kind="taken" so CallKit can dismiss with
    // .answeredElsewhere. The accepting device is excluded.
    await ctx.scheduler.runAfter(0, internal.voipPush.sendVoipTaken, {
      callId,
      calleeId: call.calleeId,
      excludeDeviceId: acceptingDeviceId ?? null,
      reason: "accepted",
    });
  },
});

export const reject = mutation({
  args: {
    callId: v.id("calls"),
    userId: v.id("users"),
    acceptingDeviceId: v.optional(v.string()),
  },
  handler: async (ctx, { callId, userId, acceptingDeviceId }) => {
    const call = await assertCallParticipant(ctx, callId, userId);
    if (call.calleeId.toString() !== userId.toString()) {
      throw new Error("ONLY_CALLEE_CAN_REJECT");
    }
    if (call.status !== "ringing") return; // idempotent
    await ctx.db.patch(callId, {
      status: "rejected",
      endedAt: Date.now(),
    });
    // Drop a terminal signal so the caller sees the rejection promptly.
    const sigToCaller = await ctx.db.insert("callSignals", {
      callId,
      fromUserId: userId,
      toUserId: call.callerId,
      kind: "reject",
      payload: "{}",
      createdAt: Date.now(),
      consumed: false,
    });
    // And tell sibling callee devices to dismiss their ringer.
    const sigToCallee = await ctx.db.insert("callSignals", {
      callId,
      fromUserId: userId,
      toUserId: call.calleeId,
      kind: "taken",
      payload: JSON.stringify({
        reason: "rejected",
        byDeviceId: acceptingDeviceId ?? null,
      }),
      createdAt: Date.now(),
      consumed: false,
    });
    await purgeCallSignals(ctx, callId, [sigToCaller, sigToCallee]);
    await ctx.scheduler.runAfter(0, internal.voipPush.sendVoipTaken, {
      callId,
      calleeId: call.calleeId,
      excludeDeviceId: acceptingDeviceId ?? null,
      reason: "rejected",
    });
  },
});

export const cancel = mutation({
  args: { callId: v.id("calls"), userId: v.id("users") },
  handler: async (ctx, { callId, userId }) => {
    const call = await assertCallParticipant(ctx, callId, userId);
    if (call.callerId.toString() !== userId.toString()) {
      throw new Error("ONLY_CALLER_CAN_CANCEL");
    }
    if (call.status !== "ringing") return;
    await ctx.db.patch(callId, {
      status: "cancelled",
      endedAt: Date.now(),
    });
    const sigId = await ctx.db.insert("callSignals", {
      callId,
      fromUserId: userId,
      toUserId: call.calleeId,
      kind: "cancel",
      payload: "{}",
      createdAt: Date.now(),
      consumed: false,
    });
    await purgeCallSignals(ctx, callId, sigId);
  },
});

export const end = mutation({
  args: { callId: v.id("calls"), userId: v.id("users") },
  handler: async (ctx, { callId, userId }) => {
    const call = await assertCallParticipant(ctx, callId, userId);
    if (call.status === "ended" || call.status === "failed") return;
    await ctx.db.patch(callId, {
      status: "ended",
      endedAt: Date.now(),
    });
    const peer =
      call.callerId.toString() === userId.toString()
        ? call.calleeId
        : call.callerId;
    const sigId = await ctx.db.insert("callSignals", {
      callId,
      fromUserId: userId,
      toUserId: peer,
      kind: "bye",
      payload: "{}",
      createdAt: Date.now(),
      consumed: false,
    });
    await purgeCallSignals(ctx, callId, sigId);
  },
});

export const expireRingingCall = internalMutation({
  args: { callId: v.id("calls") },
  handler: async (ctx, { callId }) => {
    const call = await ctx.db.get(callId);
    if (!call) return;
    if (call.status !== "ringing") return;
    await ctx.db.patch(callId, {
      status: "missed",
      endedAt: Date.now(),
    });
    // Notify both sides so their UI can transition out of ringing. Both
    // signals are kept by [purgeCallSignals] so each peer sees its own.
    const sigToCallee = await ctx.db.insert("callSignals", {
      callId,
      fromUserId: call.callerId,
      toUserId: call.calleeId,
      kind: "cancel",
      payload: '{"reason":"timeout"}',
      createdAt: Date.now(),
      consumed: false,
    });
    const sigToCaller = await ctx.db.insert("callSignals", {
      callId,
      fromUserId: call.calleeId,
      toUserId: call.callerId,
      kind: "reject",
      payload: '{"reason":"timeout"}',
      createdAt: Date.now(),
      consumed: false,
    });
    // Sweep everything except those two terminal notifications.
    const rows = await ctx.db
      .query("callSignals")
      .withIndex("by_call", (q: any) => q.eq("callId", callId))
      .collect();
    for (const r of rows) {
      if (
        r._id.toString() === sigToCallee.toString() ||
        r._id.toString() === sigToCaller.toString()
      ) {
        continue;
      }
      await ctx.db.delete(r._id);
    }
  },
});

// ────────────────────────── signaling ──────────────────────────

export const sendSignal = mutation({
  args: {
    callId: v.id("calls"),
    fromUserId: v.id("users"),
    toUserId: v.id("users"),
    kind: v.string(),
    payload: v.string(),
    // Optional during handoff: deliver only to a specific recipient
    // device. Siblings of the same toUserId ignore the signal. See
    // SignalingSubscriber's targetDeviceId filter on the client.
    targetDeviceId: v.optional(v.string()),
    // Optional: the sending device's id. Lets the recipient learn which
    // device of the peer holds the call so it can target its own
    // outgoing signals back.
    fromDeviceId: v.optional(v.string()),
  },
  handler: async (
    ctx,
    {
      callId,
      fromUserId,
      toUserId,
      kind,
      payload,
      targetDeviceId,
      fromDeviceId,
    },
  ) => {
    const call = await assertCallParticipant(ctx, callId, fromUserId);
    // toUserId must be the other participant OR — during handoff — the
    // SAME user (handoff-takeover is sent to my own callee/caller userId
    // but targets a specific deviceId).
    const isHandoffToSelf =
      toUserId.toString() === fromUserId.toString() &&
      (kind === "handoff-takeover" || kind === "handoff-prepare");
    if (!isHandoffToSelf) {
      const expectedPeer =
        call.callerId.toString() === fromUserId.toString()
          ? call.calleeId.toString()
          : call.callerId.toString();
      if (toUserId.toString() !== expectedPeer) {
        throw new Error("WRONG_PEER");
      }
    }
    // Refuse signals for terminal calls. Late-arriving ICE candidates from a
    // slow network could otherwise repopulate rows after [purgeCallSignals]
    // already ran, and resurrect a dead call in the peer's subscription.
    if (call.status !== "ringing" && call.status !== "active") {
      return; // idempotent silent drop
    }
    await ctx.db.insert("callSignals", {
      callId,
      fromUserId,
      toUserId,
      kind,
      payload,
      createdAt: Date.now(),
      consumed: false,
      targetDeviceId: targetDeviceId ?? undefined,
      fromDeviceId: fromDeviceId ?? undefined,
    });
  },
});

// Transfer an active call from whichever device currently holds it to
// [newDeviceId]. The new device performs a fresh WebRTC negotiation with
// the peer; the old device tears down. See addendum design notes.
export const handoffCall = mutation({
  args: {
    callId: v.id("calls"),
    userId: v.id("users"),
    newDeviceId: v.string(),
  },
  handler: async (ctx, { callId, userId, newDeviceId }) => {
    const call = await assertCallParticipant(ctx, callId, userId);
    if (call.status !== "active") throw new Error("CALL_NOT_ACTIVE");
    const oldDeviceId = call.acceptingDeviceId;
    if (oldDeviceId === newDeviceId) {
      return { oldDeviceId: oldDeviceId ?? null };
    }
    await ctx.db.patch(callId, { acceptingDeviceId: newDeviceId });
    // Tell the old device (if known) to tear down its PC quietly. Only
    // it acts because the signal is targetDeviceId-scoped.
    if (oldDeviceId) {
      await ctx.db.insert("callSignals", {
        callId,
        fromUserId: userId,
        toUserId: userId, // same user, different device
        targetDeviceId: oldDeviceId,
        fromDeviceId: newDeviceId,
        kind: "handoff-takeover",
        payload: JSON.stringify({ newDeviceId }),
        createdAt: Date.now(),
        consumed: false,
      });
    }
    // Tell the peer to close its existing PC and expect a fresh offer
    // from the new device.
    const peerId =
      call.callerId.toString() === userId.toString()
        ? call.calleeId
        : call.callerId;
    await ctx.db.insert("callSignals", {
      callId,
      fromUserId: userId,
      toUserId: peerId,
      fromDeviceId: newDeviceId,
      kind: "handoff-prepare",
      payload: JSON.stringify({ newDeviceId }),
      createdAt: Date.now(),
      consumed: false,
    });
    return { oldDeviceId: oldDeviceId ?? null };
  },
});

export const signalsForUser = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const rows = await ctx.db
      .query("callSignals")
      .withIndex("by_to_unconsumed", (q) =>
        q.eq("toUserId", userId).eq("consumed", false),
      )
      .order("asc")
      .take(50);
    return rows.map((r) => ({
      _id: r._id,
      callId: r.callId,
      fromUserId: r.fromUserId,
      kind: r.kind,
      payload: r.payload,
      createdAt: r.createdAt,
    }));
  },
});

export const consumeSignal = mutation({
  args: { signalId: v.id("callSignals"), userId: v.id("users") },
  handler: async (ctx, { signalId, userId }) => {
    const sig = await ctx.db.get(signalId);
    if (!sig) return;
    if (sig.toUserId.toString() !== userId.toString()) {
      throw new Error("NOT_RECIPIENT");
    }
    await ctx.db.patch(signalId, { consumed: true });
  },
});

export const activeCallForUser = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    // Resolves to my live `ringing` or `active` call so the UI can re-attach
    // after a cold start. Active calls (the more interesting state for the
    // global "Move call here" pill) are checked first.
    let call = null as any;
    outer: for (const status of ["active", "ringing"] as const) {
      const asCallee = await ctx.db
        .query("calls")
        .withIndex("by_callee_status", (q) =>
          q.eq("calleeId", userId).eq("status", status),
        )
        .first();
      if (asCallee) {
        call = asCallee;
        break outer;
      }
      const asCaller = await ctx.db
        .query("calls")
        .withIndex("by_caller_status", (q) =>
          q.eq("callerId", userId).eq("status", status),
        )
        .first();
      if (asCaller) {
        call = asCaller;
        break outer;
      }
    }
    if (!call) return null;
    // Hydrate peer display fields so the pill doesn't need a second
    // round-trip. Peer = the participant who isn't me.
    const peerId =
      call.callerId.toString() === userId.toString()
        ? call.calleeId
        : call.callerId;
    const peer = await ctx.db.get(peerId);
    const peerName = peer?.name ?? peer?.username ?? "Unknown";
    // The deviceName for the device currently holding the call — for the
    // "Move call here · On Bob's MacBook" label. Falls back to platform.
    let acceptingDeviceName: string | null = null;
    let acceptingPlatform: string | null = null;
    if (call.acceptingDeviceId) {
      const dev = await ctx.db
        .query("userDevices")
        .withIndex("by_user_device", (q) =>
          q.eq("userId", call.calleeId).eq("deviceId", call.acceptingDeviceId),
        )
        .first();
      if (dev) {
        acceptingDeviceName = dev.deviceName ?? null;
        acceptingPlatform = dev.platform;
      }
    }
    return {
      _id: call._id,
      callerId: call.callerId,
      calleeId: call.calleeId,
      roomId: call.roomId,
      type: call.type,
      status: call.status,
      startedAt: call.startedAt,
      acceptedAt: call.acceptedAt,
      acceptingDeviceId: call.acceptingDeviceId ?? null,
      peerName,
      acceptingDeviceName,
      acceptingPlatform,
    };
  },
});

// ────────────────────────── ICE config ──────────────────────────
// Returns the iceServers list the client should hand to RTCPeerConnection.
// Always includes Google's public STUN. If TURN_URL + TURN_SECRET are set in
// Convex env, generates short-lived TURN REST API credentials (HMAC-SHA1 of
// "<unix-ts + ttl>:<userId>", 1 hour validity). Coturn must be running with
// `use-auth-secret` + the matching `static-auth-secret`.
export const getIceConfig = action({
  args: { userId: v.id("users") },
  handler: async (_ctx, { userId }) => {
    const stun = [
      { urls: "stun:stun.l.google.com:19302" },
      { urls: "stun:stun1.l.google.com:19302" },
    ];
    const turnUrl = process.env.TURN_URL;
    const turnSecret = process.env.TURN_SECRET;
    if (!turnUrl || !turnSecret) {
      return { iceServers: stun };
    }
    const ttlSeconds = 3600;
    const expiry = Math.floor(Date.now() / 1000) + ttlSeconds;
    const username = `${expiry}:${userId.toString()}`;
    const credential = await hmacSha1Base64(turnSecret, username);
    return {
      iceServers: [
        ...stun,
        {
          urls: turnUrl, // e.g. "turn:1.2.3.4:3478"
          username,
          credential,
        },
      ],
    };
  },
});

async function hmacSha1Base64(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  const bytes = new Uint8Array(sig);
  let bin = "";
  for (let i = 0; i < bytes.byteLength; i++) {
    bin += String.fromCharCode(bytes[i]);
  }
  // btoa is available in Convex's V8 runtime.
  return btoa(bin);
}

// ────────────────────────── push (wakes the callee) ──────────────────────────

const ONESIGNAL_APP_ID = "c191a9f0-15cf-402a-8a04-dcc16108f4b0";
const ONESIGNAL_BASE = "https://api.onesignal.com";

export const sendCallPush = internalAction({
  args: {
    callId: v.id("calls"),
    calleeId: v.id("users"),
    callerId: v.id("users"),
    callerName: v.string(),
    type: v.string(),
    roomId: v.id("rooms"),
  },
  handler: async (
    _ctx,
    { callId, calleeId, callerId, callerName, type, roomId },
  ) => {
    const apiKey = process.env.ONESIGNAL_API_KEY;
    if (!apiKey) {
      console.error("sendCallPush: ONESIGNAL_API_KEY env var is not set");
      return;
    }
    const verb = type === "video" ? "Video call" : "Voice call";
    const payload = {
      app_id: ONESIGNAL_APP_ID,
      target_channel: "push",
      include_aliases: { external_id: [calleeId.toString()] },
      headings: { en: callerName },
      contents: { en: `${verb} from ${callerName}` },
      priority: 10,
      ios_interruption_level: "time_sensitive",
      data: {
        type: "call_invite",
        callId: callId.toString(),
        callerId: callerId.toString(),
        callerName,
        callType: type,
        roomId: roomId.toString(),
      },
      ios_category: "CALL_INVITE",
    };
    const response = await fetch(`${ONESIGNAL_BASE}/notifications`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Key ${apiKey}`,
      },
      body: JSON.stringify(payload),
    });
    const text = await response.text();
    if (!response.ok) {
      console.error(`sendCallPush: OneSignal HTTP ${response.status} ${text}`);
    } else {
      console.log(`sendCallPush: dispatched — ${text}`);
    }
  },
});

// ────────────────────────── GC sweeps ──────────────────────────
// These run on a schedule from crons.ts. Each one bounds its work with
// `.take(200)` so a single tick can't run away — if more is pending, the
// next tick picks it up.

const CONSUMED_SIGNAL_RETENTION_MS = 60 * 1000;      // 1 min
const TERMINAL_CALL_RETENTION_MS = 24 * 60 * 60 * 1000; // 1 day
const STUCK_RINGING_MS = 90 * 1000;                  // 90s safety net

// Delete callSignals where consumed=true and createdAt is older than 1 min.
export const gcConsumedSignals = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = Date.now() - CONSUMED_SIGNAL_RETENTION_MS;
    // Convex doesn't expose a single index on (consumed, createdAt), but
    // `by_to_unconsumed` lets us hit the consumed=true partition quickly
    // by iterating all users' rows — for early-stage volumes that's fine.
    // We collect old consumed rows by scanning callSignals filtered by
    // consumed=true and createdAt < cutoff. Cap each run at 200 deletes.
    const rows = await ctx.db
      .query("callSignals")
      .filter((q) =>
        q.and(
          q.eq(q.field("consumed"), true),
          q.lt(q.field("createdAt"), cutoff),
        ),
      )
      .take(200);
    for (const r of rows) {
      await ctx.db.delete(r._id);
    }
    if (rows.length > 0) {
      console.log(`gcConsumedSignals: deleted ${rows.length} row(s)`);
    }
  },
});

// Delete terminal-status calls older than 1 day, plus any of their lingering
// signals (defense in depth — purgeCallSignals should have already cleaned
// them at terminal time).
export const gcTerminalCalls = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = Date.now() - TERMINAL_CALL_RETENTION_MS;
    const terminal = ["ended", "rejected", "cancelled", "missed", "failed"];
    let totalDeleted = 0;
    for (const status of terminal) {
      const rows = await ctx.db
        .query("calls")
        .withIndex("by_status_started", (q) =>
          q.eq("status", status).lt("startedAt", cutoff),
        )
        .take(50);
      for (const call of rows) {
        // Cascade — sweep any signals that survived purge-on-terminal.
        const sigs = await ctx.db
          .query("callSignals")
          .withIndex("by_call", (q: any) => q.eq("callId", call._id))
          .collect();
        for (const sig of sigs) await ctx.db.delete(sig._id);
        await ctx.db.delete(call._id);
        totalDeleted++;
      }
    }
    if (totalDeleted > 0) {
      console.log(`gcTerminalCalls: deleted ${totalDeleted} call(s)`);
    }
  },
});

// Safety net for `ringing` calls older than 90s. The per-call scheduled
// `expireRingingCall` should have fired at 30s; this catches the edge case
// where a backend restart or scheduler failure left a call ringing forever.
export const gcStuckRinging = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = Date.now() - STUCK_RINGING_MS;
    const rows = await ctx.db
      .query("calls")
      .withIndex("by_status_started", (q) =>
        q.eq("status", "ringing").lt("startedAt", cutoff),
      )
      .take(50);
    for (const call of rows) {
      await ctx.db.patch(call._id, {
        status: "missed",
        endedAt: Date.now(),
      });
      // Drop terminal signals so each side's UI clears.
      await ctx.db.insert("callSignals", {
        callId: call._id,
        fromUserId: call.callerId,
        toUserId: call.calleeId,
        kind: "cancel",
        payload: '{"reason":"stuck"}',
        createdAt: Date.now(),
        consumed: false,
      });
      await ctx.db.insert("callSignals", {
        callId: call._id,
        fromUserId: call.calleeId,
        toUserId: call.callerId,
        kind: "reject",
        payload: '{"reason":"stuck"}',
        createdAt: Date.now(),
        consumed: false,
      });
    }
    if (rows.length > 0) {
      console.log(`gcStuckRinging: rescued ${rows.length} call(s)`);
    }
  },
});
