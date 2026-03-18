import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  users: defineTable({
    username: v.string(),
    name: v.optional(v.string()),
    passwordHash: v.string(),
    recoveryKeyHash: v.optional(v.string()),
    createdAt: v.number(),
    status: v.optional(v.string()), // "online" | "away" | "offline"
    lastSeen: v.optional(v.number()),
    bio: v.optional(v.string()),
    email: v.optional(v.string()),
    avatarStorageId: v.optional(v.id("_storage")),
    deviceTokens: v.optional(v.array(v.string())), // legacy field — OneSignal manages tokens now
  }).index("by_username", ["username"]),

  friendships: defineTable({
    userId: v.id("users"),
    friendId: v.id("users"),
    status: v.string(), // "pending" | "accepted"
    createdAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_friend", ["friendId"])
    .index("by_pair", ["userId", "friendId"]),

  rooms: defineTable({
    name: v.string(),
    description: v.optional(v.string()),
    createdBy: v.id("users"),
    createdAt: v.number(),
    isPrivate: v.boolean(),
    memberCount: v.number(),
    passwordHash: v.optional(v.string()),
    // New fields
    type: v.optional(v.string()),          // "regular" | "secret"
    messageLifetime: v.optional(v.number()), // auto-expiry in seconds
    avatarStorageId: v.optional(v.id("_storage")),
    lastMessage: v.optional(v.string()),
    lastMessageTime: v.optional(v.number()),
  })
    .index("by_name", ["name"])
    .index("by_last_activity", ["lastMessageTime"]),

  roomMembers: defineTable({
    roomId: v.id("rooms"),
    userId: v.id("users"),
    joinedAt: v.number(),
    role: v.string(), // "owner" | "member"
  })
    .index("by_room", ["roomId"])
    .index("by_user", ["userId"])
    .index("by_room_user", ["roomId", "userId"]),

  messages: defineTable({
    roomId: v.id("rooms"),
    userId: v.id("users"),
    content: v.string(),
    createdAt: v.number(),
    edited: v.optional(v.boolean()),
    // New fields
    type: v.optional(v.string()),            // "text" | "image" | "video" | "audio" | "url" | "system"
    mediaStorageId: v.optional(v.id("_storage")),
    senderName: v.optional(v.string()),
    expiresAt: v.optional(v.number()),       // Unix ms timestamp — set for Chamber of Secrets rooms
  })
    .index("by_room", ["roomId"])
    .index("by_room_time", ["roomId", "createdAt"]),

  reactions: defineTable({
    messageId: v.id("messages"),
    userId: v.id("users"),
    emoji: v.string(),
    createdAt: v.number(),
  })
    .index("by_message", ["messageId"])
    .index("by_message_user", ["messageId", "userId"]),

  typingIndicators: defineTable({
    roomId: v.id("rooms"),
    userId: v.id("users"),
    updatedAt: v.number(),
  })
    .index("by_room", ["roomId"])
    .index("by_room_user", ["roomId", "userId"]),
});
