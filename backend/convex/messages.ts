import { mutation, query, internalMutation } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";

export const send = mutation({
  args: {
    roomId: v.id("rooms"),
    userId: v.id("users"),
    content: v.string(),
    type: v.optional(v.string()),          // "text" | "image" | "video" | "audio" | "url" | "system"
    mediaStorageId: v.optional(v.id("_storage")),
    senderName: v.optional(v.string()),
    replyToId: v.optional(v.id("messages")),
  },
  handler: async (ctx, { roomId, userId, content, type, mediaStorageId, senderName, replyToId }) => {
    // Verify membership
    const membership = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();
    if (!membership) throw new Error("NOT_A_MEMBER");

    const msgType = type ?? "text";

    // Resolve senderName if not provided
    let resolvedSenderName = senderName;
    if (!resolvedSenderName) {
      const user = await ctx.db.get(userId);
      resolvedSenderName = user?.name ?? user?.username ?? "Unknown";
    }

    const room = await ctx.db.get(roomId);

    // DM block enforcement.
    //
    // Group rooms allow blocks to be one-way (the blocker hides the blockee
    // client-side). For DMs we hard-stop sends in either direction so the
    // block is absolute. The error is intentionally generic — never reveal
    // to the sender that they're the one being blocked.
    if (room?.name?.startsWith("dm:")) {
      const otherMember = await ctx.db
        .query("roomMembers")
        .withIndex("by_room", (q) => q.eq("roomId", roomId))
        .collect();
      const otherId = otherMember.find(
        (m) => m.userId.toString() !== userId.toString()
      )?.userId;
      if (otherId) {
        const iBlockedThem = await ctx.db
          .query("blocks")
          .withIndex("by_pair", (q) =>
            q.eq("userId", userId).eq("blockedUserId", otherId)
          )
          .first();
        const theyBlockedMe = await ctx.db
          .query("blocks")
          .withIndex("by_pair", (q) =>
            q.eq("userId", otherId).eq("blockedUserId", userId)
          )
          .first();
        if (iBlockedThem) throw new Error("UNBLOCK_FIRST");
        if (theyBlockedMe) throw new Error("MESSAGE_FAILED");
      }
    }

    // Check if the room has a message lifetime (Chamber of Secrets)
    const expiresAt = room?.messageLifetime
      ? Date.now() + room.messageLifetime * 1000
      : undefined;

    // Build a denormalized snapshot of the parent at send time. Survives the
    // parent's later deletion so the inline reply tether keeps rendering. We
    // intentionally drop both replyToId AND replyToPreview together if the
    // parent isn't reachable from the same room — never store a dangling id.
    let replyToPreview: {
      senderId: any;
      senderName: string;
      contentPreview: string;
      type: string;
      mediaStorageId?: any;
    } | undefined;
    let resolvedReplyToId: any | undefined;
    if (replyToId) {
      const parent = await ctx.db.get(replyToId);
      if (parent && parent.roomId.toString() === roomId.toString()) {
        const parentContent = parent.content ?? "";
        replyToPreview = {
          senderId: parent.userId,
          senderName: parent.senderName ?? "unknown",
          contentPreview: parentContent.slice(0, 140),
          type: parent.type ?? "text",
          mediaStorageId: parent.mediaStorageId,
        };
        resolvedReplyToId = replyToId;
      }
    }

    const messageId = await ctx.db.insert("messages", {
      roomId,
      userId,
      content,
      createdAt: Date.now(),
      type: msgType,
      mediaStorageId,
      senderName: resolvedSenderName,
      expiresAt,
      ...(replyToPreview ? { replyToId: resolvedReplyToId, replyToPreview } : {}),
    });

    // Schedule server-side deletion for self-destructing messages
    if (expiresAt !== undefined) {
      await ctx.scheduler.runAt(
        new Date(expiresAt),
        internal.messages.expireMessage,
        { messageId }
      );
    }

    // Update room's last message preview
    const preview = msgType === "text" ? content.slice(0, 100) : `[${msgType}]`;
    await ctx.db.patch(roomId, {
      lastMessage: preview,
      lastMessageTime: Date.now(),
    });

    // Fire push notifications in background (non-blocking)
    await ctx.scheduler.runAfter(0, internal.notifications.sendMessagePush, {
      roomId,
      messageId,
      senderId: userId,
      senderName: resolvedSenderName,
      content: preview,
      type: msgType,
    });

    return messageId;
  },
});

export const deleteMessage = mutation({
  args: {
    messageId: v.id("messages"),
    userId: v.id("users"),
  },
  handler: async (ctx, { messageId, userId }) => {
    const msg = await ctx.db.get(messageId);
    if (!msg) throw new Error("MESSAGE_NOT_FOUND");

    // Only sender or room owner can delete
    if (msg.userId.toString() !== userId.toString()) {
      const membership = await ctx.db
        .query("roomMembers")
        .withIndex("by_room_user", (q) => q.eq("roomId", msg.roomId).eq("userId", userId))
        .first();
      if (!membership || membership.role !== "owner") {
        throw new Error("NOT_AUTHORIZED");
      }
    }

    // Delete all reactions for this message
    const reactions = await ctx.db
      .query("reactions")
      .withIndex("by_message", (q) => q.eq("messageId", messageId))
      .collect();
    for (const r of reactions) await ctx.db.delete(r._id);

    // Delete associated file from storage if present
    if (msg.mediaStorageId) {
      await ctx.storage.delete(msg.mediaStorageId);
    }

    // Mark every child reply's denormalized preview as deleted so their
    // inline tether keeps rendering ("message removed") instead of pointing
    // at a vanished parent.
    const children = await ctx.db
      .query("messages")
      .withIndex("by_replyTo", (q) => q.eq("replyToId", messageId))
      .collect();
    for (const child of children) {
      const existing = child.replyToPreview;
      if (!existing) continue;
      await ctx.db.patch(child._id, {
        replyToPreview: { ...existing, contentPreview: "__DELETED__" },
      });
    }

    await ctx.db.delete(messageId);
  },
});

export const list = query({
  args: { roomId: v.id("rooms"), limit: v.optional(v.number()) },
  handler: async (ctx, { roomId, limit }) => {
    const msgs = await ctx.db
      .query("messages")
      .withIndex("by_room_time", (q) => q.eq("roomId", roomId))
      .order("desc")
      .take(limit ?? 100);

    // Do NOT read `users` here. Convex reactivity tracks every doc read, so
    // including `ctx.db.get(msg.userId)` made this subscription re-fire on
    // every user.status flip (online/away/offline) for any author in the
    // list — which then triggered markRoomRead, which patched roomMembers,
    // which refired four other subscriptions. The denormalized
    // `msg.senderName` is set at write time in `messages:send` so the
    // client already has the display name.
    const enriched = await Promise.all(
      msgs.map(async (msg) => {
        const reactions = await ctx.db
          .query("reactions")
          .withIndex("by_message", (q) => q.eq("messageId", msg._id))
          .collect();
        return { ...msg, reactions };
      })
    );
    return enriched.reverse();
  },
});

export const listBefore = query({
  args: {
    roomId: v.id("rooms"),
    beforeTimestamp: v.number(),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, { roomId, beforeTimestamp, limit }) => {
    const msgs = await ctx.db
      .query("messages")
      .withIndex("by_room_time", (q) =>
        q.eq("roomId", roomId).lt("createdAt", beforeTimestamp)
      )
      .order("desc")
      .take(limit ?? 30);

    // Mirrors the no-user-doc-read pattern from `list` above — see comment
    // there for why we never enrich with users in a reactive query.
    const enriched = await Promise.all(
      msgs.map(async (msg) => {
        const reactions = await ctx.db
          .query("reactions")
          .withIndex("by_message", (q) => q.eq("messageId", msg._id))
          .collect();
        return { ...msg, reactions };
      })
    );
    return enriched.reverse(); // chronological order
  },
});

// Incremental fetch: every message in a room created strictly after `since`,
// in chronological order. Used by the native client for one-shot catch-up
// (not a live subscription), so — like `list`/`listBefore` — we avoid reading
// user docs and rely on the denormalized `senderName` set at write time.
export const listSince = query({
  args: { roomId: v.id("rooms"), since: v.number() },
  handler: async (ctx, { roomId, since }) => {
    const msgs = await ctx.db
      .query("messages")
      .withIndex("by_room_time", (q) =>
        q.eq("roomId", roomId).gt("createdAt", since)
      )
      .order("asc")
      .collect();

    const enriched = await Promise.all(
      msgs.map(async (msg) => {
        const reactions = await ctx.db
          .query("reactions")
          .withIndex("by_message", (q) => q.eq("messageId", msg._id))
          .collect();
        return { ...msg, reactions };
      })
    );
    return enriched;
  },
});

// MARK: - Chamber of Secrets: scheduled self-destruction

export const expireMessage = internalMutation({
  args: { messageId: v.id("messages") },
  handler: async (ctx, { messageId }) => {
    const msg = await ctx.db.get(messageId);
    if (!msg) return; // Already deleted (e.g. manually deleted before expiry)

    // Delete all reactions for this message
    const reactions = await ctx.db
      .query("reactions")
      .withIndex("by_message", (q) => q.eq("messageId", messageId))
      .collect();
    for (const r of reactions) await ctx.db.delete(r._id);

    // Delete associated media from storage if present
    if (msg.mediaStorageId) {
      await ctx.storage.delete(msg.mediaStorageId);
    }

    // Same child-preview tombstone treatment as manual delete — keeps the
    // tether on any reply that referenced this now-expired parent.
    const children = await ctx.db
      .query("messages")
      .withIndex("by_replyTo", (q) => q.eq("replyToId", messageId))
      .collect();
    for (const child of children) {
      const existing = child.replyToPreview;
      if (!existing) continue;
      await ctx.db.patch(child._id, {
        replyToPreview: { ...existing, contentPreview: "__DELETED__" },
      });
    }

    await ctx.db.delete(messageId);
  },
});

// Returns the entire conversational thread containing [messageId]: walks up
// to the root via replyToId, then BFS down through the by_replyTo index to
// collect every descendant. Result is sorted chronologically (oldest first)
// and enriched the same way `list` enriches its rows. Capped at 50 messages
// to keep the round-trip bounded; branching threads still work but only the
// first 50 BFS-collected rows come back.
export const getThread = query({
  args: {
    messageId: v.id("messages"),
    maxTotal: v.optional(v.number()),
  },
  handler: async (ctx, { messageId, maxTotal }) => {
    const cap = Math.min(maxTotal ?? 50, 100);

    // 1. Walk up to the root. Bounded by 20 hops + cycle-guard set.
    let rootId: any = messageId;
    const seenUp = new Set<string>();
    for (let i = 0; i < 20; i++) {
      const key = rootId.toString();
      if (seenUp.has(key)) break;
      seenUp.add(key);
      const m = await ctx.db.get(rootId);
      if (!m || !m.replyToId) break;
      rootId = m.replyToId;
    }

    // 2. BFS down from the root through the by_replyTo index.
    const collected: any[] = [];
    const seenDown = new Set<string>();
    const queue: any[] = [rootId];
    while (queue.length > 0 && collected.length < cap) {
      const id = queue.shift();
      const key = id.toString();
      if (seenDown.has(key)) continue;
      seenDown.add(key);
      const m = await ctx.db.get(id);
      if (!m) continue;
      collected.push(m);
      const kids = await ctx.db
        .query("messages")
        .withIndex("by_replyTo", (q) => q.eq("replyToId", id))
        .collect();
      for (const k of kids) queue.push(k._id);
    }

    // 3. Enrich + sort chronologically.
    const enriched = await Promise.all(
      collected.map(async (m) => {
        const user = await ctx.db.get(m.userId);
        const reactions = await ctx.db
          .query("reactions")
          .withIndex("by_message", (q) => q.eq("messageId", m._id))
          .collect();
        return {
          ...m,
          username: user?.username ?? "unknown",
          name: user?.name ?? user?.username ?? "unknown",
          reactions,
        };
      })
    );
    enriched.sort((a, b) => a.createdAt - b.createdAt);
    return enriched;
  },
});

// ─────────────────────────────── Read receipts ───────────────────────────────

/**
 * Mark a room as "read up to now" for the given user. Persisted on the
 * roomMembers row so the relationship is O(rooms × members) rather than
 * O(messages × members).
 *
 * Idempotent — calling repeatedly only updates the timestamp.
 */
export const markRoomRead = mutation({
  args: { roomId: v.id("rooms"), userId: v.id("users") },
  handler: async (ctx, { roomId, userId }) => {
    const membership = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) =>
        q.eq("roomId", roomId).eq("userId", userId)
      )
      .first();
    if (!membership) return; // not a member, silently no-op
    await ctx.db.patch(membership._id, { lastReadAt: Date.now() });
  },
});

/**
 * Returns each member's lastReadAt timestamp for a room, filtered by each
 * reader's `seen` visibility relative to the requesting viewer:
 *
 *   reader.visibility.seen = "public"  → row visible to anyone
 *   reader.visibility.seen = "friends" → row visible only to the reader's friends
 *   reader.visibility.seen = "nobody"  → row hidden (default for missing/unset)
 *
 * The viewer's own row is always returned. Rows whose reader has hidden their
 * `seen` are simply omitted (rather than returned as 0) so the client can
 * compute "latest other read" without a separate filter.
 *
 * The client uses this stream to render the "SEEN" indicator on its own
 * messages. A reader who hasn't opted in to send-read-receipts contributes
 * nothing here — so message senders see no SEEN unless the reader explicitly
 * shares.
 */
export const getReadState = query({
  args: {
    roomId: v.id("rooms"),
    viewerUserId: v.id("users"),
  },
  handler: async (ctx, { roomId, viewerUserId }) => {
    const members = await ctx.db
      .query("roomMembers")
      .withIndex("by_room", (q) => q.eq("roomId", roomId))
      .collect();

    const viewerKey = viewerUserId.toString();
    const out: Array<{ userId: any; lastReadAt: number }> = [];
    for (const m of members) {
      const isSelf = m.userId.toString() === viewerKey;
      if (isSelf) {
        out.push({ userId: m.userId, lastReadAt: m.lastReadAt ?? 0 });
        continue;
      }
      const reader = await ctx.db.get(m.userId);
      const level = reader?.visibility?.seen;
      // Privacy-first default: missing/unknown ⇒ "nobody".
      const allowed =
        level === "public" ||
        (level === "friends" &&
          (await _areFriends(ctx, m.userId, viewerUserId)));
      if (!allowed) continue;
      out.push({ userId: m.userId, lastReadAt: m.lastReadAt ?? 0 });
    }
    return out;
  },
});

async function _areFriends(
  ctx: any,
  a: any,
  b: any,
): Promise<boolean> {
  const fwd = await ctx.db
    .query("friendships")
    .withIndex("by_pair", (q: any) => q.eq("userId", a).eq("friendId", b))
    .first();
  if (fwd?.status === "accepted") return true;
  const rev = await ctx.db
    .query("friendships")
    .withIndex("by_pair", (q: any) => q.eq("userId", b).eq("friendId", a))
    .first();
  return rev?.status === "accepted";
}
