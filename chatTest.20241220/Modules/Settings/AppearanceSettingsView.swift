import SwiftUI

/// Consolidated appearance & chat preferences (native grouped layout).
/// Replaces the Flutter app's separate chat-style/reply-style/room-layout/
/// navigation screens with one HIG-friendly screen.
struct AppearanceSettingsView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @AppStorage(AppearanceKeys.roomLayout) private var roomLayout = RoomLayout.list
    @AppStorage(AppearanceKeys.navStyle) private var navStyle = NavStyle.pill
    @AppStorage(AppearanceKeys.chatStyle) private var chatStyle = ChatStyle.compact
    @AppStorage(AppearanceKeys.replyStyle) private var replyStyle = ReplyStyle.phantomEcho
    @AppStorage(AppearanceKeys.viewReadReceipts) private var viewReadReceipts = false
    @AppStorage(AppearanceKeys.showLinkUrls) private var showLinkUrls = false
    @AppStorage(AppearanceKeys.captureProtection) private var captureProtection = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors { selectedTheme.colors(for: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                card("LAYOUT") {
                    segmentRow(title: "Room Layout", icon: "square.grid.2x2", selection: $roomLayout) { $0.label }
                    Divider().overlay(theme.textSecondary.opacity(0.1))
                    segmentRow(title: "Navigation", icon: "circle.circle", selection: $navStyle) { $0.label }
                }

                card("CHAT") {
                    segmentRow(title: "Message Density", icon: "text.alignleft", selection: $chatStyle) { $0.label }
                    Divider().overlay(theme.textSecondary.opacity(0.1))
                    menuRow(title: "Reply Style", icon: "arrowshape.turn.up.left", selection: $replyStyle) { $0.label }
                }

                card("MESSAGES & PRIVACY") {
                    toggleRow(title: "Show Read Receipts", icon: "checkmark.circle",
                              subtitle: "Show “Seen” on your sent messages.", isOn: $viewReadReceipts)
                    Divider().overlay(theme.textSecondary.opacity(0.1))
                    toggleRow(title: "Show Link URLs", icon: "link",
                              subtitle: "Keep raw URL text alongside link previews.", isOn: $showLinkUrls)
                    Divider().overlay(theme.textSecondary.opacity(0.1))
                    toggleRow(title: "Screen-Recording Protection", icon: "eye.slash",
                              subtitle: "Mask the screen during capture or recording.", isOn: $captureProtection)
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Appearance")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Rows

    @ViewBuilder
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(theme.textSecondary)
            VStack(spacing: 12) { content() }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(theme.cardBackground))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.textSecondary.opacity(0.1), lineWidth: 1))
        }
    }

    private func segmentRow<T: CaseIterable & Identifiable & Hashable>(
        title: String, icon: String, selection: Binding<T>, label: @escaping (T) -> String
    ) -> some View where T.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textPrimary)
            Picker(title, selection: selection) {
                ForEach(Array(T.allCases)) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func menuRow<T: CaseIterable & Identifiable & Hashable>(
        title: String, icon: String, selection: Binding<T>, label: @escaping (T) -> String
    ) -> some View where T.AllCases: RandomAccessCollection {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(Array(T.allCases)) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .tint(theme.accent)
        }
    }

    private func toggleRow(title: String, icon: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .foregroundStyle(theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(theme.textPrimary)
                Text(subtitle).font(.caption).foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(theme.accent)
        }
    }
}

#Preview {
    NavigationStack { AppearanceSettingsView() }
}
