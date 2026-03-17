import { mutation, query } from "./_generated/server";
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
  },
  handler: async (ctx, { roomId, userId, content, type, mediaStorageId, senderName }) => {
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

    const messageId = await ctx.db.insert("messages", {
      roomId,
      userId,
      content,
      createdAt: Date.now(),
      type: msgType,
      mediaStorageId,
      senderName: resolvedSenderName,
    });

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

    const enriched = await Promise.all(
      msgs.map(async (msg) => {
        const user = await ctx.db.get(msg.userId);
        const reactions = await ctx.db
          .query("reactions")
          .withIndex("by_message", (q) => q.eq("messageId", msg._id))
          .collect();
        return {
          ...msg,
          username: user?.username ?? "unknown",
          name: user?.name ?? user?.username ?? "unknown",
          reactions,
        };
      })
    );
    return enriched.reverse();
  },
});

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
        const user = await ctx.db.get(msg.userId);
        const reactions = await ctx.db
          .query("reactions")
          .withIndex("by_message", (q) => q.eq("messageId", msg._id))
          .collect();
        return {
          ...msg,
          username: user?.username ?? "unknown",
          name: user?.name ?? user?.username ?? "unknown",
          reactions,
        };
      })
    );
    return enriched;
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

    const enriched = await Promise.all(
      msgs.map(async (msg) => {
        const user = await ctx.db.get(msg.userId);
        const reactions = await ctx.db
          .query("reactions")
          .withIndex("by_message", (q) => q.eq("messageId", msg._id))
          .collect();
        return {
          ...msg,
          username: user?.username ?? "unknown",
          name: user?.name ?? user?.username ?? "unknown",
          reactions,
        };
      })
    );
    return enriched.reverse(); // chronological order
  },
});
