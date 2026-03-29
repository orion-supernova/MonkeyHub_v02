import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const addReaction = mutation({
  args: {
    messageId: v.id("messages"),
    userId: v.id("users"),
    emoji: v.string(),
  },
  handler: async (ctx, { messageId, userId, emoji }) => {
    // Verify message exists
    const msg = await ctx.db.get(messageId);
    if (!msg) throw new Error("MESSAGE_NOT_FOUND");

    // Verify user is a member of the room
    const membership = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) => q.eq("roomId", msg.roomId).eq("userId", userId))
      .first();
    if (!membership) throw new Error("NOT_A_MEMBER");

    // Idempotent: one reaction per user per emoji per message
    const existing = await ctx.db
      .query("reactions")
      .withIndex("by_message_user", (q) =>
        q.eq("messageId", messageId).eq("userId", userId)
      )
      .filter((q) => q.eq(q.field("emoji"), emoji))
      .first();
    if (existing) return existing._id;

    return await ctx.db.insert("reactions", {
      messageId,
      userId,
      emoji,
      createdAt: Date.now(),
    });
  },
});

export const removeReaction = mutation({
  args: {
    messageId: v.id("messages"),
    userId: v.id("users"),
    emoji: v.string(),
  },
  handler: async (ctx, { messageId, userId, emoji }) => {
    const existing = await ctx.db
      .query("reactions")
      .withIndex("by_message_user", (q) =>
        q.eq("messageId", messageId).eq("userId", userId)
      )
      .filter((q) => q.eq(q.field("emoji"), emoji))
      .first();
    if (existing) await ctx.db.delete(existing._id);
  },
});

export const getReactions = query({
  args: { messageId: v.id("messages") },
  handler: async (ctx, { messageId }) => {
    return await ctx.db
      .query("reactions")
      .withIndex("by_message", (q) => q.eq("messageId", messageId))
      .order("asc")
      .collect();
  },
});

// Bulk-fetch reactions for multiple messages (used when loading a room)
export const getReactionsForMessages = query({
  args: { messageIds: v.array(v.id("messages")) },
  handler: async (ctx, { messageIds }) => {
    const result: Record<string, unknown[]> = {};
    for (const messageId of messageIds) {
      const reactions = await ctx.db
        .query("reactions")
        .withIndex("by_message", (q) => q.eq("messageId", messageId))
        .collect();
      result[messageId] = reactions;
    }
    return result;
  },
});
