import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const getProfile = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const user = await ctx.db.get(userId);
    if (!user) return null;
    return {
      _id: user._id,
      username: user.username,
      name: user.name,
      email: user.email,
      bio: user.bio,
      avatarStorageId: user.avatarStorageId,
      status: user.status,
      deviceTokens: user.deviceTokens,
    };
  },
});

export const updateProfile = mutation({
  args: {
    userId: v.id("users"),
    name: v.string(),
    email: v.optional(v.string()),
    bio: v.optional(v.string()),
  },
  handler: async (ctx, { userId, name, email, bio }) => {
    const user = await ctx.db.get(userId);
    if (!user) throw new Error("USER_NOT_FOUND");
    await ctx.db.patch(userId, {
      name: name.trim(),
      email: email && email.length > 0 ? email : undefined,
      bio: bio && bio.length > 0 ? bio : undefined,
    });
  },
});

export const updateAvatar = mutation({
  args: {
    userId: v.id("users"),
    storageId: v.id("_storage"),
  },
  handler: async (ctx, { userId, storageId }) => {
    const user = await ctx.db.get(userId);
    if (!user) throw new Error("USER_NOT_FOUND");
    await ctx.db.patch(userId, { avatarStorageId: storageId });
  },
});

export const registerDeviceToken = mutation({
  args: {
    userId: v.id("users"),
    token: v.string(),
  },
  handler: async (ctx, { userId, token }) => {
    const user = await ctx.db.get(userId);
    if (!user) throw new Error("USER_NOT_FOUND");
    const existing = user.deviceTokens ?? [];
    if (!existing.includes(token)) {
      await ctx.db.patch(userId, { deviceTokens: [...existing, token] });
    }
  },
});

export const removeDeviceToken = mutation({
  args: {
    userId: v.id("users"),
    token: v.string(),
  },
  handler: async (ctx, { userId, token }) => {
    const user = await ctx.db.get(userId);
    if (!user) return;
    const updated = (user.deviceTokens ?? []).filter((t) => t !== token);
    await ctx.db.patch(userId, { deviceTokens: updated });
  },
});

export const searchUsers = query({
  args: { query: v.string(), currentUserId: v.id("users") },
  handler: async (ctx, { query: q, currentUserId }) => {
    const users = await ctx.db.query("users").collect();
    return users
      .filter(
        (u) =>
          u._id !== currentUserId &&
          (u.username.toLowerCase().includes(q.toLowerCase()) ||
            (u.name ?? "").toLowerCase().includes(q.toLowerCase()))
      )
      .slice(0, 20)
      .map((u) => ({
        _id: u._id,
        username: u.username,
        name: u.name ?? u.username,
        status: u.status,
        avatarStorageId: u.avatarStorageId,
      }));
  },
});
