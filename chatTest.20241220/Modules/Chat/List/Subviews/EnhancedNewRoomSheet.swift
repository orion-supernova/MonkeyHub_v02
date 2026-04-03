//
//  EnhancedNewRoomSheet.swift
//  chatTest.20241220
//
//  Created by Murat Can Koc on 3.04.2026.
//

import SwiftUI

struct EnhancedNewRoomSheet: View {
    @Binding var isShowingSheet: Bool
    @Binding var roomName: String
    @State private var selectedType: RoomType = .regular
    @State private var messageLifetime: TimeInterval = 30  // 30 seconds default
    let createRoom: (RoomType, TimeInterval?, String?) async -> Void
    @AppStorage("selectedTheme") private var selectedTheme = AppTheme.basic
    @State private var animateContent = false
    @State private var selectedOptionId: TimeInterval?
    @Namespace private var animation
    @FocusState private var isRoomNameFocused: Bool

    // Password Protection
    @State private var isProtected = false
    @State private var roomPassword = ""

    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollID = UUID()  // For scroll anchor
    @Environment(\.colorScheme) private var colorScheme

    private let lifetimeOptions: [(String, TimeInterval)] = [
        ("10 seconds", 10),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("30 minutes", 1800),
        ("1 hour", 3600),
    ]

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Enhanced Header with animation
                        VStack(spacing: 8) {
                            Text("Create New Room")
                                .font(.title.bold())
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)

                            Text("Select room type and customize settings")
                                .font(.subheadline)
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary
                                )
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)
                        }
                        .padding(.top, 12)

                        // Room Type Selector with improved animations
                        VStack(alignment: .leading, spacing: 20) {
                            Text("ROOM TYPE")
                                .font(.caption.bold())
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary
                                )
                                .padding(.leading, 4)
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)

                            VStack(spacing: 16) {
                                ForEach([RoomType.regular, .secret], id: \.self) { type in
                                    RoomTypeButton(
                                        type: type,
                                        selectedType: $selectedType,
                                        selectedTheme: selectedTheme,
                                        animateContent: animateContent
                                    )
                                }
                            }
                        }

                        // Message Lifetime Selector with improved animations
                        if selectedType == .secret {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("MESSAGE LIFETIME")
                                    .font(.caption.bold())
                                    .foregroundStyle(
                                        selectedTheme.colors(for: colorScheme).textSecondary
                                    )
                                    .padding(.leading, 4)
                                    .transition(.move(edge: .top).combined(with: .opacity))

                                VStack(spacing: 12) {
                                    ForEach(lifetimeOptions, id: \.1) { option in
                                        Button {
                                            withAnimation(.spring(duration: 0.3)) {
                                                messageLifetime = option.1
                                                selectedOptionId = option.1
                                            }
                                        } label: {
                                            HStack {
                                                Text(option.0)
                                                    .font(.subheadline)
                                                    .foregroundStyle(
                                                        selectedTheme.colors(for: colorScheme)
                                                            .textPrimary)

                                                Spacer()

                                                if messageLifetime == option.1 {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(
                                                            selectedTheme.colors(for: colorScheme)
                                                                .accent
                                                        )
                                                        .matchedGeometryEffect(
                                                            id: "check\(option.1)",
                                                            in: animation
                                                        )
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(
                                                        selectedTheme.colors(for: colorScheme)
                                                            .cardBackground
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .strokeBorder(
                                                                messageLifetime == option.1
                                                                    ? selectedTheme.colors(
                                                                        for: colorScheme
                                                                    ).accent
                                                                    : selectedTheme.colors(
                                                                        for: colorScheme
                                                                    ).textSecondary
                                                                        .opacity(0.1),
                                                                lineWidth: messageLifetime
                                                                    == option.1
                                                                    ? 1.5 : 1
                                                            )
                                                    )
                                            )
                                            .scaleEffect(messageLifetime == option.1 ? 1.02 : 1)
                                        }
                                        .buttonStyle(.plain)
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }
                            }
                            .padding(.top, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Room name input with simplified keyboard handling
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ROOM NAME")
                                .font(.caption.bold())
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary
                                )
                                .padding(.leading, 4)
                                .opacity(animateContent ? 1 : 0)
                                .offset(y: animateContent ? 0 : 20)

                            TextField("Enter room name", text: $roomName)
                                .textFieldStyle(.plain)
                                .padding()
                                .background(selectedTheme.colors(for: colorScheme).cardBackground)
                                .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(
                                            roomName.isEmpty
                                                ? selectedTheme.colors(for: colorScheme)
                                                    .textSecondary
                                                    .opacity(0.1)
                                                : selectedTheme.colors(for: colorScheme).accent
                                                    .opacity(
                                                        0.2),
                                            lineWidth: 1
                                        )
                                )
                                .focused($isRoomNameFocused)
                        }
                        .id(scrollID)  // Add scroll anchor
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)

                        // Password Protection toggle and input
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("Protect with Password", systemImage: "lock.shield")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                                Spacer()
                                Toggle("", isOn: $isProtected)
                                    .labelsHidden()
                                    .tint(selectedTheme.colors(for: colorScheme).accent)
                            }
                            .padding()
                            .background(selectedTheme.colors(for: colorScheme).cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            if isProtected {
                                SecureField("Enter room password", text: $roomPassword)
                                    .textFieldStyle(.plain)
                                    .padding()
                                    .background(selectedTheme.colors(for: colorScheme).cardBackground)
                                    .foregroundStyle(selectedTheme.colors(for: colorScheme).textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(
                                                roomPassword.isEmpty
                                                    ? selectedTheme.colors(for: colorScheme)
                                                        .textSecondary
                                                        .opacity(0.1)
                                                    : selectedTheme.colors(for: colorScheme).accent
                                                        .opacity(0.2),
                                                lineWidth: 1
                                            )
                                    )
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)

                        // Create button with enhanced animation
                        Button {
                            // Add haptic feedback
                        #if canImport(UIKit)
                            let impactMed = UIImpactFeedbackGenerator(style: .medium)
                            impactMed.impactOccurred()
                        #endif

                            Task {
                                await createRoom(
                                    selectedType,
                                    selectedType == .secret ? messageLifetime : nil,
                                    isProtected ? roomPassword : nil
                                )
                            }
                        } label: {
                            HStack(spacing: 12) {
                                if selectedType == .secret {
                                    Image(systemName: "flame.fill")
                                        .symbolEffect(.variableColor.cumulative.hideInactiveLayers.nonReversing, options: .repeat(.continuous))
                                        .transition(.scale.combined(with: .opacity))
                                    Text("Create Secret Room")
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                        .transition(.scale.combined(with: .opacity))
                                    Text("Create Room")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(selectedTheme.colors(for: colorScheme).text)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: selectedType == .secret
                                        ? [Color.orange, Color.red]
                                        : selectedTheme.colors(for: colorScheme).primary,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(
                                color: selectedType == .secret
                                    ? Color.orange.opacity(0.4)
                                    : selectedTheme.colors(for: colorScheme).primary[0].opacity(0.3),
                                radius: 5, y: 2
                            )
                            .scaleEffect(roomName.isEmpty ? 0.98 : 1)
                        }
                        .disabled(roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(animateContent ? 1 : 0)
                        .offset(y: animateContent ? 0 : 20)
#if os(macOS)
                        .buttonStyle(.plain)
                        .focusable(false)
#endif
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(20)
                    .padding(.bottom, keyboardHeight > 0 ? keyboardHeight + 20 : 16)
                }
                .onChange(of: isRoomNameFocused) { _, isFocused in
                    if isFocused {
                        withAnimation {
                            proxy.scrollTo(scrollID, anchor: .bottom)
                        }
                    }
                }
                .background(selectedTheme.colors(for: colorScheme).background)
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isRoomNameFocused = false
                            }
                        }
                        .foregroundStyle(
                            colorScheme == .dark
                                ? selectedTheme.colors(for: colorScheme).accent
                                : selectedTheme.colors(for: colorScheme).primary[0]
                        )
                    }

                    // Add close button
                    ToolbarItem(placement: {
                        #if canImport(UIKit)
                        return .navigationBarTrailing
                        #else
                        return .automatic
                        #endif
                    }()) {
                        Button {
                            isShowingSheet = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    selectedTheme.colors(for: colorScheme).textSecondary)
                        }
#if os(macOS)
                        .buttonStyle(.plain)
                        .focusable(false)
#endif
                        .contentShape(Circle())
                    }
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) {
                    animateContent = true
                }
            }
            .onChange(of: selectedType) { _, _ in
                #if canImport(UIKit)
                let impactLight = UIImpactFeedbackGenerator(style: .light)
                impactLight.impactOccurred()
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 560, minHeight: 500, idealHeight: selectedType == .secret ? 760 : 620)
        #else
        .presentationDetents([
            .height(selectedType == .secret ? 900 : 620),
            .large,
        ])
        .presentationDragIndicator(.visible)
        .presentationBackground(selectedTheme.colors(for: colorScheme).background)
        .interactiveDismissDisabled()
        #endif
    }
}
