//
//  RoomTypeButton.swift
//  chatTest.20241220
//
//  Created by Murat Can Koc on 3.04.2026.
//

import SwiftUI

struct RoomTypeButton: View {
    let type: RoomType
    @Binding var selectedType: RoomType
    let selectedTheme: AppTheme
    let animateContent: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.5, bounce: 0.3)) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 16) {
                // Room type icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: selectedType == type
                                    ? selectedTheme.colors(for: colorScheme).primary
                                    : [selectedTheme.colors(for: colorScheme).cardBackground],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(
                            color: selectedType == type
                                ? selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3)
                                : .clear,
                            radius: 5, y: 2
                        )

                    Image(
                        systemName: type == .regular
                            ? "bubble.left.circle.fill"
                            : "lock.shield.fill"
                    )
                    .font(.title3)
                    .foregroundStyle(
                        selectedType == type
                            ? selectedTheme.colors(for: colorScheme).text
                            : selectedTheme.colors(for: colorScheme).textSecondary
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        type == .regular
                            ? "Regular Room" : "Chamber of Secrets"
                    )
                    .font(.headline)
                    .foregroundStyle(
                        selectedTheme.colors(for: colorScheme).textPrimary
                    )

                    Text(
                        type == .regular
                            ? "Standard chat room with permanent messages"
                            : "Secret room with self-destructing messages"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        selectedTheme.colors(for: colorScheme).textSecondary
                    )
                    .lineLimit(2)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(
                        selectedTheme.colors(for: colorScheme).accent
                    )
                    .opacity(selectedType == type ? 1 : 0)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selectedTheme.colors(for: colorScheme).cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        selectedType == type
                            ? selectedTheme.colors(for: colorScheme).accent
                            : selectedTheme.colors(for: colorScheme).textSecondary.opacity(0.1),
                        lineWidth: selectedType == type ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(animateContent ? 1 : 0)
        .offset(y: animateContent ? 0 : 20)
    }
}
