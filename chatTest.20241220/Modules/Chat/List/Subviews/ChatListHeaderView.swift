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

                HStack(spacing: 12) {
                    HeaderActionButton(title: "New Room", icon: "plus.circle.fill", action: onCreateRoom)
                    HeaderActionButton(title: "Search", icon: "magnifyingglass", action: onSearch)
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
                .frame(maxWidth: .infinity, minHeight: 30)
        }
        // Prominent (tinted) Liquid Glass, branded with the theme accent.
        .buttonStyle(.glassProminent)
        .tint(selectedTheme.colors(for: colorScheme).headerControlTint)
        .buttonBorderShape(.roundedRectangle(radius: 16))
    }
}

// MARK: - Section Selector

private struct SectionSelectorView: View {
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedSection: ChatListViewModel.Section
    let pendingRequestCount: Int

    var body: some View {
        // Native draggable segmented control — press a segment and slide the handle. We keep the iOS 26
        // Liquid Glass frosted handle as the selected indicator (NO `selectedTint`, which would force
        // the legacy flat filled style), clear the control's own track, and put a tinted glass capsule
        // BEHIND it so the whole control reads as one branded glass pill with a glass border to match
        // the buttons above. Titles are white so they stay legible on the glass + gradient.
        #if canImport(UIKit)
        let theme = selectedTheme.colors(for: colorScheme)
        NativeSegmentedControl(
            selection: $selectedSection,
            items: ChatListViewModel.Section.allCases.map { (value: $0, title: label(for: $0)) },
            height: 44,
            normalTitleColor: theme.text,
            selectedTitleColor: theme.text,
            clearsBackground: true
        )
        // Glass border on the WHOLE control (tinted to match the prominent buttons). Non-interactive
        // so it doesn't intercept the segmented control's own press-and-drag handle gesture.
        .glassEffect(.regular.tint(theme.headerControlTint), in: .capsule)
        #else
        Picker("Section", selection: $selectedSection) {
            ForEach(ChatListViewModel.Section.allCases, id: \.self) { section in
                Text(label(for: section)).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #endif
    }

    private func label(for section: ChatListViewModel.Section) -> String {
        section == .requests && pendingRequestCount > 0
            ? "\(section.rawValue) (\(pendingRequestCount))"
            : section.rawValue
    }
}
