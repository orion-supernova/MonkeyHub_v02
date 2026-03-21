import { mutation, query } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";

async function insertRequestMessage(
  ctx: any,
  requestId: string,
  userId: string,
  content: string,
  timestamp = Date.now()
) {
  await ctx.db.insert("friendRequestMessages", {
    requestId,
    userId,
    content,
    createdAt: timestamp,
  });
}

async function clearRequestMessages(ctx: any, requestId: string) {
  const messages = await ctx.db
    .query("friendRequestMessages")
    .withIndex("by_request", (q: any) => q.eq("requestId", requestId))
    .collect();
  for (const message of messages) {
    await ctx.db.delete(message._id);
  }
}

async function getDirectFriendship(ctx: any, userId: any, otherUserId: any) {
  const outgoing = await ctx.db
    .query("friendships")
    .withIndex("by_pair", (q: any) => q.eq("userId", userId).eq("friendId", otherUserId))
    .first();
  const incoming = await ctx.db
    .query("friendships")
    .withIndex("by_pair", (q: any) => q.eq("userId", otherUserId).eq("friendId", userId))
    .first();

  return { outgoing, incoming };
}

async function createDirectRoom(ctx: any, requesterId: any, receiverId: any, roomType?: string, messageLifetime?: number) {
  const normalizedRoomType = roomType ?? "Regular Room";
  const roomKey = normalizedRoomType === "Chamber of Secrets" ? "secret" : "regular";
  const ordered = [requesterId.toString(), receiverId.toString()].sort();
  const roomName = `dm:${roomKey}:${ordered[0]}:${ordered[1]}`;

  const existingRoom = await ctx.db
    .query("rooms")
    .withIndex("by_name", (q: any) => q.eq("name", roomName))
    .first();
  if (existingRoom) return existingRoom._id;

  if (roomKey === "regular") {
    const legacyName = `dm:${ordered[0]}:${ordered[1]}`;
    const legacyRoom = await ctx.db
      .query("rooms")
      .withIndex("by_name", (q: any) => q.eq("name", legacyName))
      .first();
    if (legacyRoom) return legacyRoom._id;
  }

  const roomId = await ctx.db.insert("rooms", {
    name: roomName,
    createdBy: requesterId,
    createdAt: Date.now(),
    isPrivate: true,
    memberCount: 2,
    type: normalizedRoomType,
    messageLifetime,
  });

  await ctx.db.insert("roomMembers", {
    roomId,
    userId: requesterId,
    joinedAt: Date.now(),
    role: "owner",
  });
  await ctx.db.insert("roomMembers", {
    roomId,
    userId: receiverId,
    joinedAt: Date.now(),
    role: "member",
  });

  return roomId;
}

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

export const createDirectRequest = mutation({
  args: {
    userId: v.id("users"),
    friendId: v.id("users"),
    roomType: v.string(),
    messageLifetime: v.optional(v.number()),
    initialMessage: v.string(),
  },
  handler: async (ctx, { userId, friendId, roomType, messageLifetime, initialMessage }) => {
    if (userId.toString() === friendId.toString()) throw new Error("CANNOT_ADD_SELF");

    const target = await ctx.db.get(friendId);
    if (!target) throw new Error("USER_NOT_FOUND");

    const { outgoing, incoming } = await getDirectFriendship(ctx, userId, friendId);

    if (outgoing?.status === "accepted" || incoming?.status === "accepted") {
      throw new Error("ALREADY_FRIENDS");
    }
    if (outgoing?.status === "pending") {
      throw new Error("REQUEST_ALREADY_PENDING");
    }
    if (incoming?.status === "pending") {
      throw new Error("REQUEST_ALREADY_RECEIVED");
    }

    const requestId = await ctx.db.insert("friendships", {
      userId,
      friendId,
      status: "pending",
      createdAt: Date.now(),
      roomType,
      messageLifetime,
      initialMessage: initialMessage.trim(),
    });
    await insertRequestMessage(ctx, requestId, userId, initialMessage.trim());
    return requestId;
  },
});

export const appendDirectRequestMessage = mutation({
  args: {
    requestId: v.id("friendships"),
    userId: v.id("users"),
    content: v.string(),
  },
  handler: async (ctx, { requestId, userId, content }) => {
    const request = await ctx.db.get(requestId);
    if (!request || request.status !== "pending") throw new Error("REQUEST_NOT_FOUND");

    await insertRequestMessage(ctx, requestId, userId, content.trim());
  },
});

export const listDirectRequestMessages = query({
  args: { requestId: v.id("friendships") },
  handler: async (ctx, { requestId }) => {
    const messages = await ctx.db
      .query("friendRequestMessages")
      .withIndex("by_request", (q: any) => q.eq("requestId", requestId))
      .collect();
    return messages
      .sort((a, b) => a.createdAt - b.createdAt)
      .map((m) => ({
        _id: m._id,
        userId: m.userId,
        content: m.content,
        createdAt: m.createdAt,
      }));
  },
});

export const approveDirectRequest = mutation({
  args: { userId: v.id("users"), requesterId: v.id("users") },
  handler: async (ctx, { userId, requesterId }) => {
    const request = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) =>
        q.eq("userId", requesterId).eq("friendId", userId)
      )
      .first();
    if (!request || request.status !== "pending") throw new Error("REQUEST_NOT_FOUND");

    const roomId =
      request.roomId ??
      (await createDirectRoom(
        ctx,
        requesterId,
        userId,
        request.roomType,
        request.messageLifetime
      ));
    const requestMessages = await ctx.db
      .query("friendRequestMessages")
      .withIndex("by_request", (q: any) => q.eq("requestId", request._id))
      .collect();
    requestMessages.sort((a, b) => a.createdAt - b.createdAt);

    const now = Date.now();
    await ctx.db.patch(request._id, {
      status: "accepted",
      respondedAt: now,
      roomId,
    });

    const reverse = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) =>
        q.eq("userId", userId).eq("friendId", requesterId)
      )
      .first();

    if (reverse) {
      await ctx.db.patch(reverse._id, {
        status: "accepted",
        respondedAt: now,
        roomType: reverse.roomType ?? request.roomType,
        messageLifetime: reverse.messageLifetime ?? request.messageLifetime,
        roomId,
      });
    } else {
      await ctx.db.insert("friendships", {
        userId,
        friendId: requesterId,
        status: "accepted",
        createdAt: now,
        respondedAt: now,
        roomType: request.roomType,
        messageLifetime: request.messageLifetime,
        roomId,
      });
    }

    if (requestMessages.length > 0) {
      // Compute expiry from approval time if this is a secret room.
      const expiresAt = request.messageLifetime
        ? now + request.messageLifetime * 1000
        : undefined;

      for (const msg of requestMessages) {
        const messageId = await ctx.db.insert("messages", {
          roomId,
          userId: msg.userId,
          content: msg.content,
          createdAt: msg.createdAt,
          type: "text",
          expiresAt,
        });
        if (expiresAt !== undefined) {
          await ctx.scheduler.runAt(
            new Date(expiresAt),
            internal.messages.expireMessage,
            { messageId }
          );
        }
      }
      const last = requestMessages[requestMessages.length - 1];
      await ctx.db.patch(roomId, {
        lastMessage: last.content.slice(0, 100),
        lastMessageTime: last.createdAt,
      });
      await clearRequestMessages(ctx, request._id);
    }

    return roomId;
  },
});

export const rejectDirectRequest = mutation({
  args: { userId: v.id("users"), requesterId: v.id("users") },
  handler: async (ctx, { userId, requesterId }) => {
    const request = await ctx.db
      .query("friendships")
      .withIndex("by_pair", (q) =>
        q.eq("userId", requesterId).eq("friendId", userId)
      )
      .first();
    if (request?.status === "pending") {
      await clearRequestMessages(ctx, request._id);
      await ctx.db.delete(request._id);
    }
  },
});

export const listIncomingDirectRequests = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const incoming = await ctx.db
      .query("friendships")
      .withIndex("by_friend", (q) => q.eq("friendId", userId))
      .filter((q) => q.eq(q.field("status"), "pending"))
      .collect();

    const requests = await Promise.all(
      incoming.map(async (request) => {
        const requester = await ctx.db.get(request.userId);
        if (!requester) return null;

        return {
          _id: request._id,
          createdAt: request.createdAt,
          roomType: request.roomType ?? "Regular Room",
          messageLifetime: request.messageLifetime,
          initialMessage: request.initialMessage ?? "",
          user: {
            _id: requester._id,
            username: requester.username,
            name: requester.name,
            email: requester.email,
            bio: requester.bio,
            avatarStorageId: requester.avatarStorageId,
            status: requester.status,
          },
        };
      })
    );

    return requests.filter(Boolean);
  },
});

export const listOutgoingDirectRequests = query({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }) => {
    const outgoing = await ctx.db
      .query("friendships")
      .withIndex("by_user", (q) => q.eq("userId", userId))
      .filter((q) => q.eq(q.field("status"), "pending"))
      .collect();

    const requests = await Promise.all(
      outgoing.map(async (request) => {
        const receiver = await ctx.db.get(request.friendId);
        if (!receiver) return null;

        return {
          _id: request._id,
          createdAt: request.createdAt,
          roomType: request.roomType ?? "Regular Room",
          messageLifetime: request.messageLifetime,
          initialMessage: request.initialMessage ?? "",
          user: {
            _id: receiver._id,
            username: receiver.username,
            name: receiver.name,
            email: receiver.email,
            bio: receiver.bio,
            avatarStorageId: receiver.avatarStorageId,
            status: receiver.status,
          },
        };
      })
    );

    return requests.filter(Boolean);
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
