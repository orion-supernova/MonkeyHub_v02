import { mutation, query, internalQuery } from "./_generated/server";
import { v } from "convex/values";

export const create = mutation({
  args: {
    name: v.string(),
    description: v.optional(v.string()),
    isPrivate: v.boolean(),
    userId: v.id("users"),
    passwordHash: v.optional(v.string()),
    type: v.optional(v.string()),           // "regular" | "secret"
    messageLifetime: v.optional(v.number()), // seconds
  },
  handler: async (ctx, { name, description, isPrivate, userId, passwordHash, type, messageLifetime }) => {
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
      type: type ?? "regular",
      messageLifetime,
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
  args: {
    roomId: v.id("rooms"),
    userId: v.id("users"),
    passwordHash: v.optional(v.string()),
  },
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
    await ctx.db.patch(roomId, { memberCount: room.memberCount + 1 });
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
      await _deleteRoomContents(ctx, roomId);
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

    await _deleteRoomContents(ctx, roomId);
    await ctx.db.delete(roomId);
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
    isPrivate: v.optional(v.boolean()),
  },
  handler: async (ctx, { roomId, userId, name, description, isPrivate }) => {
    const room = await ctx.db.get(roomId);
    if (!room) throw new Error("ROOM_NOT_FOUND");
    const membership = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();
    if (!membership) throw new Error("NOT_AUTHORIZED"); // any member can update

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
      ...(isPrivate !== undefined ? { isPrivate } : {}),
    });
  },
});

export const updateRoomAvatar = mutation({
  args: {
    roomId: v.id("rooms"),
    userId: v.id("users"),
    storageId: v.id("_storage"),
  },
  handler: async (ctx, { roomId, userId, storageId }) => {
    const room = await ctx.db.get(roomId);
    if (!room) throw new Error("ROOM_NOT_FOUND");
    const membership = await ctx.db
      .query("roomMembers")
      .withIndex("by_room_user", (q) => q.eq("roomId", roomId).eq("userId", userId))
      .first();
    if (!membership) throw new Error("NOT_AUTHORIZED"); // any member can update avatar
    await ctx.db.patch(roomId, { avatarStorageId: storageId });
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
      memberships.map(async (m) => {
        const room = await ctx.db.get(m.roomId);
        if (!room) return null;
        // Include participant IDs for the iOS app
        const members = await ctx.db
          .query("roomMembers")
          .withIndex("by_room", (q) => q.eq("roomId", m.roomId))
          .collect();
        const participantIds = members.map((mem) => mem.userId.toString());
        return { ...room, participantIds };
      })
    );

    return rooms
      .filter(Boolean)
      .sort((a, b) => (b!.lastMessageTime ?? b!.createdAt) - (a!.lastMessageTime ?? a!.createdAt));
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
        if (!user) return null;
        return {
          _id: user._id,
          username: user.username,
          name: user.name,
          email: user.email,
          bio: user.bio,
          avatarStorageId: user.avatarStorageId,
          status: user.status,
          role: m.role,
        };
      })
    );
    return users.filter(Boolean);
  },
});

// Internal query: fetch member user IDs for push notifications via OneSignal.
// OneSignal targets users by external user ID — no device tokens needed here.
export const getMemberIds = internalQuery({
  args: { roomId: v.id("rooms"), excludeUserId: v.id("users") },
  handler: async (ctx, { roomId, excludeUserId }) => {
    const members = await ctx.db
      .query("roomMembers")
      .withIndex("by_room", (q) => q.eq("roomId", roomId))
      .collect();
    return members
      .filter((m) => m.userId.toString() !== excludeUserId.toString())
      .map((m) => ({ userId: m.userId }));
  },
});

export const getRoom = query({
  args: { roomId: v.id("rooms") },
  handler: async (ctx, { roomId }) => {
    const room = await ctx.db.get(roomId);
    if (!room) return null;
    const members = await ctx.db
      .query("roomMembers")
      .withIndex("by_room", (q) => q.eq("roomId", roomId))
      .collect();
    return { ...room, participantIds: members.map((m) => m.userId.toString()) };
  },
});

export const getOrCreateDM = mutation({
  args: { userId: v.id("users"), friendId: v.id("users") },
  handler: async (ctx, { userId, friendId }) => {
    if (userId.toString() === friendId.toString()) throw new Error("CANNOT_DM_SELF");

    // Check for existing private room with both users
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
      if (friendMembership) return m.roomId;
    }

    const ordered = [userId.toString(), friendId.toString()].sort();
    const name = `dm:${ordered[0]}:${ordered[1]}`;

    const existingByName = await ctx.db
      .query("rooms")
      .withIndex("by_name", (q) => q.eq("name", name))
      .first();
    if (existingByName) return existingByName._id;

    const roomId = await ctx.db.insert("rooms", {
      name,
      createdBy: userId,
      createdAt: Date.now(),
      isPrivate: true,
      memberCount: 2,
      type: "regular",
    });

    await ctx.db.insert("roomMembers", { roomId, userId, joinedAt: Date.now(), role: "owner" });
    await ctx.db.insert("roomMembers", { roomId, userId: friendId, joinedAt: Date.now(), role: "member" });

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

// ─── Internal helpers ───────────────────────────────────────────────────────

async function _deleteRoomContents(
  ctx: { db: any },
  roomId: string
) {
  // Delete all messages and their reactions
  const msgs = await ctx.db
    .query("messages")
    .withIndex("by_room", (q: any) => q.eq("roomId", roomId))
    .collect();
  for (const msg of msgs) {
    const reactions = await ctx.db
      .query("reactions")
      .withIndex("by_message", (q: any) => q.eq("messageId", msg._id))
      .collect();
    for (const r of reactions) await ctx.db.delete(r._id);
    await ctx.db.delete(msg._id);
  }

  // Delete all typing indicators
  const typing = await ctx.db
    .query("typingIndicators")
    .withIndex("by_room", (q: any) => q.eq("roomId", roomId))
    .collect();
  for (const t of typing) await ctx.db.delete(t._id);

  // Delete all member records
  const members = await ctx.db
    .query("roomMembers")
    .withIndex("by_room", (q: any) => q.eq("roomId", roomId))
    .collect();
  for (const m of members) await ctx.db.delete(m._id);
}
