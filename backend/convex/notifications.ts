import { internalAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";

// Required Convex environment variables (set in Convex dashboard):
//   ONESIGNAL_APP_ID   — your OneSignal App ID
//   ONESIGNAL_API_KEY  — your OneSignal REST API key (from OneSignal dashboard → Settings → Keys & IDs)

export const sendMessagePush = internalAction({
  args: {
    roomId: v.id("rooms"),
    messageId: v.id("messages"),
    senderId: v.id("users"),
    senderName: v.string(),
    content: v.string(),
    type: v.string(),
  },
  handler: async (ctx, { roomId, senderId, senderName, content, type }) => {
    const appId = process.env.ONESIGNAL_APP_ID;
    const apiKey = process.env.ONESIGNAL_API_KEY;

    if (!appId || !apiKey) {
      // Push not configured — skip silently
      return;
    }

    // Fetch all room members except the sender (we only need their user IDs now)
    const members: Array<{ userId: string }> = await ctx.runQuery(
      internal.rooms.getMemberIds,
      { roomId, excludeUserId: senderId }
    );

    if (members.length === 0) return;

    const externalUserIds = members.map((m) => m.userId.toString());

    const body =
      type === "text"
        ? content
        : type === "image"
        ? "📷 Image"
        : type === "video"
        ? "🎥 Video"
        : type === "audio"
        ? "🎵 Audio"
        : "New message";

    const payload = {
      app_id: appId,
      include_external_user_ids: externalUserIds,
      headings: { en: senderName },
      contents: { en: body },
      data: {
        roomId: roomId.toString(),
        senderId: senderId.toString(),
        senderName,
        content: body,
        type,
      },
      ios_badgeType: "Increase",
      ios_badgeCount: 1,
      // Attach the notification category so iOS renders the quick-reply action
      ios_category: "CHAT_MESSAGE",
    };

    const response = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Basic ${apiKey}`,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        `OneSignal push failed (${response.status}): ${errorText}`
      );
    }
  },
});
