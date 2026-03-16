import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const sendRequest = mutation({
  args: { userId: v.id("users"), friendUsername: v.string() },
  handler: async (ctx, { userId, friendUsername }) => {
    const friend = await ctx.db
      .query("users")
      .withIndex("by_username", (q) => q.eq("username", friendUsername))
      .first();
    if (!friend) throw new Error("USER_NOT_FOUND");
    if (friend._id === userId) throw new Error("CANNOT_ADD_SELF");

    const existing = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) =>
        q.eq("userId", userId).eq("friendId", friend._id)
      )
      .first();
    if (existing) throw new Error("ALREADY_FRIENDS_OR_PENDING");

    await ctx.db.insert("friendships", {
      userId,
      friendId: friend._id,
      status: "pending",
      createdAt: Date.now(),
    });
    return friend._id;
  },
});

export const acceptRequest = mutation({
  args: { userId: v.id("users"), requesterId: v.id("users") },
  handler: async (ctx, { userId, requesterId }) => {
    const request = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) =>
        q.eq("userId", requesterId).eq("friendId", userId)
      )
      .first();
    if (!request) throw new Error("REQUEST_NOT_FOUND");

    await ctx.db.patch(request._id, { status: "accepted" });
    // Create reverse friendship
    await ctx.db.insert("friendships", {
      userId,
      friendId: requesterId,
      status: "accepted",
      createdAt: Date.now(),
    });
  },
});

export const rejectRequest = mutation({
  args: { userId: v.id("users"), requesterId: v.id("users") },
  handler: async (ctx, { userId, requesterId }) => {
    const request = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) =>
        q.eq("userId", requesterId).eq("friendId", userId)
      )
      .first();
    if (request) await ctx.db.delete(request._id);
  },
});

export const listFriends = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const friendships = await ctx.db
      .query("friendships")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .filter((q) => q.eq(q.field("status"), "accepted"))
      .collect();

    const friends = await Promise.all(
      friendships.map((f) => ctx.db.get(f.friendId))
    );
    return friends.filter(Boolean);
  },
});

export const listPendingRequests = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    // Requests sent TO this user
    const incoming = await ctx.db
      .query("friendships")
      .withIndex("by_friend", (q) => q.eq("friendId", userId))
      .filter((q) => q.eq(q.field("status"), "pending"))
      .collect();

    const requesters = await Promise.all(
      incoming.map(async (f) => {
        const user = await ctx.db.get(f.userId);
        return user ? { ...user, friendshipId: f._id } : null;
      })
    );
    return requesters.filter(Boolean);
  },
});

export const removeFriend = mutation({
  args: { userId: v.id("users"), friendId: v.id("users") },
  handler: async (ctx, { userId, friendId }) => {
    const f1 = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) => q.eq("userId", userId).eq("friendId", friendId))
      .first();
    const f2 = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) => q.eq("userId", friendId).eq("friendId", userId))
      .first();
    if (f1) await ctx.db.delete(f1._id);
    if (f2) await ctx.db.delete(f2._id);
  },
});

export const searchUsers = query({
  args: { query: v.string(), currentUserId: v.id("users") },
  handler: async (ctx, { query, currentUserId }) => {
    const users = await ctx.db.query("users").collect();
    return users
      .filter(
        (u) =>
          u._id !== currentUserId &&
          u.username.toLowerCase().includes(query.toLowerCase())
      )
      .slice(0, 10)
      .map((u) => ({ _id: u._id, username: u.username, status: u.status }));
  },
});
