//
//  JoinRoomSheet.swift
//  chatTest.20241220
//
//  Created by Murat Can Koc on 3.04.2026.
//

import SwiftUI

struct JoinRoomSheet: View {
    @Binding var isShowingSheet: Bool
    let availableRooms: [ChatRoom]
    let joinRoom: (ChatRoom) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Text("Join Room")
                    .font(.title.bold())
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                Text("Join an existing room")
                    .font(.subheadline)
                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
            }

            if availableRooms.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: selectedTheme.colors(for: colorScheme).primary,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("No Rooms Available")
                        .font(.title2.bold())
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)

                    Text("Create a new room or try again later")
                        .font(.subheadline)
                        .foregroundStyle(selectedTheme.colors(for: colorScheme).textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(availableRooms) { room in
                            Button {
                                Task {
                                    await joinRoom(room)
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    // Room icon
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    colors: selectedTheme.colors(for: colorScheme)
                                                        .primary,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )

                                        Image(
                                            systemName: room.hasPassword ? "lock.fill" : (room.type == .regular
                                                ? "bubble.left" : "lock.shield")
                                        )
                                        .font(.title3.bold())
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).text)
                                    }
                                    .frame(width: 44, height: 44)

                                    // Room info
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(room.name)
                                                .font(.headline)
                                                .foregroundStyle(
                                                    selectedTheme.colors(for: colorScheme).textPrimary)
                                            
                                            if room.hasPassword {
                                                Image(systemName: "key.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).accent)
                                            }
                                        }

                                        HStack {
                                            Image(systemName: "person.2.fill")
                                                .imageScale(.small)
                                            Text("\(room.resolvedMemberCount) members")
                                        }
                                        .font(.caption)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.headline)
                                        .foregroundStyle(
                                            selectedTheme.colors(for: colorScheme).textSecondary)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(selectedTheme.colors(for: colorScheme).cardBackground)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(
                                            selectedTheme.colors(for: colorScheme).accent.opacity(
                                                0.1), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding(.top, 24)
        .background(selectedTheme.colors(for: colorScheme).background)
    }
}
