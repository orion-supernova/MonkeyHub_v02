import SwiftUI

struct ChatListHeaderView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .largeTitle) private var largeTitleSize: Double = 34
    @ScaledMetric(relativeTo: .largeTitle) private var compactTitleSize: Double = 28

    @Binding var selectedSection: ChatListViewModel.Section
    let sectionSummary: String
    let pendingRequestCount: Int
    let onCreateRoom: () -> Void
    let onSearch: () -> Void

    var body: some View {
        VStack(spacing: verticalSizeClass == .compact ? 12 : 20) {
            Color.clear
                .frame(height: verticalSizeClass == .compact ? 20 : 50)

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        let title = selectedSection == .chats ? "Chat Rooms" : selectedSection.rawValue

                        Text(title)
                            .font(.system(size: verticalSizeClass == .compact ? compactTitleSize : largeTitleSize, weight: .bold))
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).text)

                        Text(sectionSummary)
                            .font(.subheadline)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).text.opacity(0.8))
                    }

                    Spacer()
                }

                GlassEffectContainer {
                    HStack(spacing: 12) {
                        HeaderActionButton(title: "New Room", icon: "plus.circle.fill", action: onCreateRoom)
                        HeaderActionButton(title: "Search", icon: "magnifyingglass", action: onSearch)
                    }
                }
                

                SectionSelectorView(
                    selectedSection: $selectedSection,
                    pendingRequestCount: pendingRequestCount
                )
            }
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
            .padding(.bottom, verticalSizeClass == .compact ? 36 : 44)
        }
    }
}

// MARK: - Header Action Button

private struct HeaderActionButton: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        // Native Liquid Glass — same treatment as the chat-room top-control buttons, but a wide
        // rounded-rect shape instead of a circle. clipShape after buttonBorderShape is the
        // documented workaround for the glass shape rendering artifact.
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Section Selector

private struct SectionSelectorView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedSection: ChatListViewModel.Section
    let pendingRequestCount: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ChatListViewModel.Section.allCases, id: \.self) { section in
                Button {
                    withAnimation(.spring(duration: 0.25)) {
                        selectedSection = section
                    }
                } label: {
                    VStack(spacing: 6) {
                        Label(section.rawValue, systemImage: section.icon)
                            .font(.subheadline.bold())
                        if section == .requests && pendingRequestCount > 0 {
                            Text("\(pendingRequestCount)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.18), in: .capsule)
                        }
                    }
                    .foregroundStyle(
                        selectedSection == section
                            ? selectedTheme.colors(for: colorScheme).text
                            : selectedTheme.colors(for: colorScheme).text.opacity(0.6)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        selectedSection == section
                            ? selectedTheme.colors(for: colorScheme).headerOverlay
                            : Color.clear
                    )
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(selectedTheme.colors(for: colorScheme).headerOverlay.opacity(0.6))
        .clipShape(.capsule)
    }
}
