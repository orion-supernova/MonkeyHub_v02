import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

const TYPING_TTL_MS = 8000; // safety net — clearTyping fires after 1.5s inactivity, heartbeat every 2s

export const setTyping = mutation({
  args: {
    roomId: v.id("rooms"),
    userId: v.id("users"),
  },
  handler: async (ctx, { roomId, userId }) => {
    const existing = await ctx.db
      .query("typingIndicators")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();

    if (existing) {
      await ctx.db.patch(existing._id, { updatedAt: Date.now() });
    } else {
      await ctx.db.insert("typingIndicators", {
        roomId,
        userId,
        updatedAt: Date.now(),
      });
    }
  },
});

export const clearTyping = mutation({
  args: {
    roomId: v.id("rooms"),
    userId: v.id("users"),
  },
  handler: async (ctx, { roomId, userId }) => {
    const existing = await ctx.db
      .query("typingIndicators")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();
    if (existing) await ctx.db.delete(existing._id);
  },
});

/// Returns { roomId: [typerName, …] } for all rooms the user belongs to.
/// A single subscription gives live typing state for the whole room list.
export const getTypingForUser = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const now = Date.now();
    const memberships = await ctx.db
      .query("roomMembers")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();

    const result: Record<string, string[]> = {};
    for (const m of memberships) {
      const indicators = await ctx.db
        .query("typingIndicators")
        .withIndex("by_room", (q) => q.eq("roomId", m.roomId))
        .collect();

      const active = indicators.filter(
        (t) =>
          t.userId.toString() !== userId.toString() &&
          now - t.updatedAt < TYPING_TTL_MS
      );

      if (active.length > 0) {
        const names = (
          await Promise.all(
            active.map(async (t) => {
              const user = await ctx.db.get(t.userId);
              return user?.name ?? user?.username ?? null;
            })
          )
        ).filter(Boolean) as string[];
        result[m.roomId.toString()] = names;
      }
    }
    return result;
  },
});

export const getTypingUsers = query({
  args: { roomId: v.id("rooms"), currentUserId: v.id("users") },
  handler: async (ctx, { roomId, currentUserId }) => {
    const now = Date.now();
    const indicators = await ctx.db
      .query("typingIndicators")
      .withIndex("by_room", (q) => q.eq("roomId", roomId))
      .collect();

    // Filter out stale entries and self
    const active = indicators.filter(
      (t) =>
        t.userId.toString() !== currentUserId.toString() &&
        now - t.updatedAt < TYPING_TTL_MS
    );

    // Enrich with user names
    const enriched = await Promise.all(
      active.map(async (t) => {
        const user = await ctx.db.get(t.userId);
        return user
          ? { userId: t.userId, name: user.name ?? user.username, username: user.username }
          : null;
      })
    );
    return enriched.filter(Boolean);
  },
});
