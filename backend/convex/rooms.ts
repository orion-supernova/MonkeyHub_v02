import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const create = mutation({
  args: {
    name: v.string(),
    description: v.optional(v.string()),
    isPrivate: v.boolean(),
    userId: v.id("users"),
    passwordHash: v.optional(v.string()),
  },
  handler: async (ctx, { name, description, isPrivate, userId, passwordHash }) => {
    const existing = await ctx.db
      .query("rooms")
      .withIndex("by_name", (q) => q.eq("name", name))
      .first();
    if (existing) throw new Error("ROOM_EXISTS");

    const roomId = await ctx.db.insert("rooms", {
      name,
      description,
      createdBy: userId,
      createdAt: Date.now(),
      isPrivate,
      memberCount: 1,
      passwordHash: passwordHash && passwordHash.length > 0 ? passwordHash : undefined,
    });
    await ctx.db.insert("roomMembers", {
      roomId,
      userId,
      joinedAt: Date.now(),
      role: "owner",
    });
    return roomId;
  },
});

export const join = mutation({
  args: { roomId: v.id("rooms"), userId: v.id("users"), passwordHash: v.optional(v.string()) },
  handler: async (ctx, { roomId, userId, passwordHash }) => {
    const room = await ctx.db.get(roomId);
    if (!room) throw new Error("ROOM_NOT_FOUND");
    if (room.passwordHash) {
      if (!passwordHash || passwordHash.length === 0) throw new Error("ROOM_PASSWORD_REQUIRED");
      if (passwordHash !== room.passwordHash) throw new Error("ROOM_PASSWORD_INVALID");
    }
    const existing = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();
    if (existing) return;

    await ctx.db.insert("roomMembers", {
      roomId,
      userId,
      joinedAt: Date.now(),
      role: "member",
    });
    if (room) {
      await ctx.db.patch(roomId, { memberCount: room.memberCount + 1 });
    }
  },
});

export const updatePassword = mutation({
  args: {
    roomId: v.id("rooms"),
    userId: v.id("users"),
    passwordHash: v.optional(v.string()),
  },
  handler: async (ctx, { roomId, userId, passwordHash }) => {
    const room = await ctx.db.get(roomId);
    if (!room) throw new Error("ROOM_NOT_FOUND");
    if (room.createdBy.toString() !== userId.toString()) throw new Error("NOT_OWNER");
    await ctx.db.patch(roomId, {
      passwordHash: passwordHash && passwordHash.length > 0 ? passwordHash : undefined,
    });
  },
});

export const updateRoom = mutation({
  args: {
    roomId: v.id("rooms"),
    userId: v.id("users"),
    name: v.string(),
    description: v.optional(v.string()),
  },
  handler: async (ctx, { roomId, userId, name, description }) => {
    const room = await ctx.db.get(roomId);
    if (!room) throw new Error("ROOM_NOT_FOUND");
    if (room.createdBy.toString() !== userId.toString()) throw new Error("NOT_OWNER");

    const trimmed = name.trim();
    if (!trimmed) throw new Error("ROOM_NAME_REQUIRED");
    if (trimmed !== room.name) {
      const existing = await ctx.db
        .query("rooms")
        .withIndex("by_name", (q) => q.eq("name", trimmed))
        .first();
      if (existing && existing._id.toString() !== roomId.toString()) {
        throw new Error("ROOM_EXISTS");
      }
    }

    await ctx.db.patch(roomId, {
      name: trimmed,
      description: description && description.length > 0 ? description : undefined,
    });
  },
});

export const leave = mutation({
  args: { roomId: v.id("rooms"), userId: v.id("users") },
  handler: async (ctx, { roomId, userId }) => {
    const member = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();
    if (!member) return;

    await ctx.db.delete(member._id);
    const room = await ctx.db.get(roomId);
    if (room && room.memberCount > 0) {
      await ctx.db.patch(roomId, { memberCount: room.memberCount - 1 });
    }

    // Auto-delete room if now empty
    const remaining = await ctx.db
      .query("roomMembers")
      .withIndex("by_room", (q) => q.eq("roomId", roomId))
      .collect();
    if (remaining.length === 0) {
      const msgs = await ctx.db
        .query("messages")
        .withIndex("by_room", (q) => q.eq("roomId", roomId))
        .collect();
      for (const msg of msgs) await ctx.db.delete(msg._id);
      await ctx.db.delete(roomId);
    }
  },
});

export const deleteRoom = mutation({
  args: { roomId: v.id("rooms"), userId: v.id("users") },
  handler: async (ctx, { roomId, userId }) => {
    const room = await ctx.db.get(roomId);
    if (!room) throw new Error("ROOM_NOT_FOUND");
    if (room.createdBy.toString() !== userId.toString()) throw new Error("NOT_OWNER");

    // Delete all messages
    const msgs = await ctx.db
      .query("messages")
      .withIndex("by_room", (q) => q.eq("roomId", roomId))
      .collect();
    for (const msg of msgs) await ctx.db.delete(msg._id);

    // Delete all member records
    const members = await ctx.db
      .query("roomMembers")
      .withIndex("by_room", (q) => q.eq("roomId", roomId))
      .collect();
    for (const m of members) await ctx.db.delete(m._id);

    await ctx.db.delete(roomId);
  },
});

export const listPublic = query({
  handler: async (ctx) => {
    return await ctx.db
      .query("rooms")
      .filter((q) => q.eq(q.field("isPrivate"), false))
      .collect();
  },
});

export const listUserRooms = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const memberships = await ctx.db
      .query("roomMembers")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();
    const rooms = await Promise.all(
      memberships.map((m) => ctx.db.get(m.roomId))
    );
    return rooms.filter(Boolean);
  },
});

export const getMembers = query({
  args: { roomId: v.id("rooms") },
  handler: async (ctx, { roomId }) => {
    const members = await ctx.db
      .query("roomMembers")
      .withIndex("by_room", (q) => q.eq("roomId", roomId))
      .collect();
    const users = await Promise.all(
      members.map(async (m) => {
        const user = await ctx.db.get(m.userId);
        return user ? { ...user, role: m.role } : null;
      })
    );
    return users.filter(Boolean);
  },
});

export const getRoom = query({
  args: { roomId: v.id("rooms") },
  handler: async (ctx, { roomId }) => {
    return await ctx.db.get(roomId);
  },
});

export const getOrCreateDM = mutation({
  args: { userId: v.id("users"), friendId: v.id("users") },
  handler: async (ctx, { userId, friendId }) => {
    if (userId.toString() === friendId.toString()) {
      throw new Error("CANNOT_DM_SELF");
    }

    const memberships = await ctx.db
      .query("roomMembers")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .collect();

    for (const m of memberships) {
      const room = await ctx.db.get(m.roomId);
      if (!room || !room.isPrivate) continue;
      const friendMembership = await ctx.db
        .query("roomMembers")
        .withIndex("by_room_user", (q) => q.eq("roomId", m.roomId).eq("userId", friendId))
        .first();
      if (friendMembership) {
        return m.roomId;
      }
    }

    const ordered = [userId.toString(), friendId.toString()].sort();
    const name = `dm:${ordered[0]}:${ordered[1]}`;

    const existingByName = await ctx.db
      .query("rooms")
      .withIndex("by_name", (q) => q.eq("name", name))
      .first();
    if (existingByName) {
      return existingByName._id;
    }

    const roomId = await ctx.db.insert("rooms", {
      name,
      description: undefined,
      createdBy: userId,
      createdAt: Date.now(),
      isPrivate: true,
      memberCount: 2,
    });

    await ctx.db.insert("roomMembers", {
      roomId,
      userId,
      joinedAt: Date.now(),
      role: "owner",
    });
    await ctx.db.insert("roomMembers", {
      roomId,
      userId: friendId,
      joinedAt: Date.now(),
      role: "member",
    });

    return roomId;
  },
});

export const isMember = query({
  args: { roomId: v.id("rooms"), userId: v.id("users") },
  handler: async (ctx, { roomId, userId }) => {
    const member = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();
    return !!member;
  },
});

export const getMembership = query({
  args: { roomId: v.id("rooms"), userId: v.id("users") },
  handler: async (ctx, { roomId, userId }) => {
    const m = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();
    return m ? { role: m.role } : null;
  },
});
