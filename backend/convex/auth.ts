import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const signup = mutation({
  args: {
    username: v.string(),
    name: v.string(),
    passwordHash: v.string(),
    recoveryKeyHash: v.optional(v.string()),
    email: v.optional(v.string()),
  },
  handler: async (ctx, { username, name, passwordHash, recoveryKeyHash, email }) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .first();
    if (existing) throw new Error("USERNAME_TAKEN");

    const userId = await ctx.db.insert("users", {
      username,
      name,
      passwordHash,
      recoveryKeyHash,
      email,
      createdAt: Date.now(),
      status: "online",
      lastSeen: Date.now(),
    });
    return { userId, username, name };
  },
});

export const login = mutation({
  args: {
    username: v.string(),
    passwordHash: v.string(),
  },
  handler: async (ctx, { username, passwordHash }) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .first();
    if (!user) throw new Error("USER_NOT_FOUND");
    if (user.passwordHash !== passwordHash) throw new Error("WRONG_PASSWORD");

    await ctx.db.patch(user._id, { status: "online", lastSeen: Date.now() });
    return { userId: user._id, username: user.username, name: user.name ?? user.username };
  },
});

export const logout = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    await ctx.db.patch(userId, { status: "offline", lastSeen: Date.now() });
  },
});

export const resetPasswordWithRecoveryKey = mutation({
  args: {
    username: v.string(),
    recoveryKeyHash: v.string(),
    newPasswordHash: v.string(),
  },
  handler: async (ctx, { username, recoveryKeyHash, newPasswordHash }) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", username))
      .first();
    if (!user) throw new Error("USER_NOT_FOUND");
    if (!user.recoveryKeyHash || user.recoveryKeyHash !== recoveryKeyHash) {
      throw new Error("INVALID_RECOVERY_KEY");
    }
    await ctx.db.patch(user._id, {
      passwordHash: newPasswordHash,
      status: "online",
      lastSeen: Date.now(),
    });
    return { userId: user._id, username: user.username };
  },
});

export const deleteAccount = mutation({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    // 1. Handle all room memberships
    const memberships = await ctx.db
      .query("roomMembers")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();

    for (const membership of memberships) {
      const roomId = membership.roomId;
      await ctx.db.delete(membership._id);

      const room = await ctx.db.get(roomId);
      if (room && room.memberCount > 0) {
        await ctx.db.patch(roomId, { memberCount: room.memberCount - 1 });
      }

      const remaining = await ctx.db
        .query("roomMembers")
        .withIndex("by_room", (q) => q.eq("roomId", roomId))
        .collect();

      if (remaining.length === 0) {
        const msgs = await ctx.db
          .query("messages")
          .withIndex("by_room", (q) => q.eq("roomId", roomId))
          .collect();
        for (const msg of msgs) {
          const rxns = await ctx.db
            .query("reactions")
            .withIndex("by_message", (q) => q.eq("messageId", msg._id))
            .collect();
          for (const r of rxns) await ctx.db.delete(r._id);
          await ctx.db.delete(msg._id);
        }
        await ctx.db.delete(roomId);
      }
    }

    // 2. Delete all friendships involving this user
    const asUser = await ctx.db
      .query("friendships")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();
    const asFriend = await ctx.db
      .query("friendships")
      .withIndex("by_friend", (q) => q.eq("friendId", userId))
      .collect();
    for (const f of [...asUser, ...asFriend]) await ctx.db.delete(f._id);

    // 3. Delete user's messages (and their reactions) in surviving rooms
    const userMessages = await ctx.db
      .query("messages")
      .filter((q) => q.eq(q.field("userId"), userId))
      .collect();
    for (const msg of userMessages) {
      const rxns = await ctx.db
        .query("reactions")
        .withIndex("by_message", (q) => q.eq("messageId", msg._id))
        .collect();
      for (const r of rxns) await ctx.db.delete(r._id);
      await ctx.db.delete(msg._id);
    }

    // 4. Clear typing indicators
    const typingEntries = await ctx.db
      .query("typingIndicators")
      .filter((q) => q.eq(q.field("userId"), userId))
      .collect();
    for (const t of typingEntries) await ctx.db.delete(t._id);

    // 5. Delete user record
    await ctx.db.delete(userId);
  },
});

export const getUser = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    return await ctx.db.get(userId);
  },
});

export const updateStatus = mutation({
  args: { userId: v.id("users"), status: v.string() },
  handler: async (ctx, { userId, status }) => {
    await ctx.db.patch(userId, { status, lastSeen: Date.now() });
  },
});

