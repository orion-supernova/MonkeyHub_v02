import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const send = mutation({
  args: {
    roomId: v.id("rooms"),
    userId: v.id("users"),
    content: v.string(),
  },
  handler: async (ctx, { roomId, userId, content }) => {
    return await ctx.db.insert("messages", {
      roomId,
      userId,
      content,
      createdAt: Date.now(),
    });
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

    // Enrich with usernames
    const enriched = await Promise.all(
      msgs.map(async (msg) => {
        const user = await ctx.db.get(msg.userId);
        return {
          ...msg,
          username: user?.username ?? "unknown",
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
        return { ...msg, username: user?.username ?? "unknown" };
      })
    );
    return enriched;
  },
});
