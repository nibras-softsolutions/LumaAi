import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Timeline Entry & Provider

public struct LumaWidgetEntry: TimelineEntry {
    public let date: Date
    public let snapshot: LumaWidgetSnapshot

    public init(date: Date = Date(), snapshot: LumaWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

public struct LumaWidgetTimelineProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> LumaWidgetEntry {
        LumaWidgetEntry(snapshot: .placeholder)
    }

    public func getSnapshot(in context: Context, completion: @escaping (LumaWidgetEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : LumaWidgetStore.shared.loadSnapshot()
        completion(LumaWidgetEntry(snapshot: snapshot))
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<LumaWidgetEntry>) -> Void) {
        let snapshot = LumaWidgetStore.shared.loadSnapshot()
        let entry = LumaWidgetEntry(date: Date(), snapshot: snapshot)
        // Refresh policy: explicitly reloaded when app updates chat/auth via WidgetCenter.shared.reloadAllTimelines()
        let timeline = Timeline(entries: [entry], policy: .never)
        completion(timeline)
    }
}

// MARK: - Root Entry View

public struct LumaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    public let entry: LumaWidgetEntry

    public init(entry: LumaWidgetEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(snapshot: entry.snapshot)
            case .systemMedium:
                MediumWidgetView(snapshot: entry.snapshot)
            case .systemLarge:
                LargeWidgetView(snapshot: entry.snapshot)
            case .accessoryCircular:
                LockScreenCircularView(snapshot: entry.snapshot)
            case .accessoryRectangular:
                LockScreenRectangularView(snapshot: entry.snapshot)
            case .accessoryInline:
                LockScreenInlineView(snapshot: entry.snapshot)
            @unknown default:
                SmallWidgetView(snapshot: entry.snapshot)
            }
        }
        .widgetBackground()
    }
}

// MARK: - Small Widget View (Ask Luma)

struct SmallWidgetView: View {
    let snapshot: LumaWidgetSnapshot

    var body: some View {
        Link(destination: LumaDeepLinkDestination.chat.url) {
            VStack(alignment: .leading, spacing: 10) {
                // Brand Header
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#8765F5"))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                        )

                    Text("Luma AI")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    if let emoji = snapshot.activePersonaEmoji, !emoji.isEmpty {
                        Text(emoji)
                            .font(.system(size: 12))
                    }
                }

                Spacer()

                // "Ask Anything" Capsule
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.6))

                    Text(snapshot.isAuthenticated ? "Ask anything…" : "Sign In to Luma")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Bottom Tagline
                Text(snapshot.isAuthenticated ? "Tap to chat with AI" : "Tap to sign in")
                    .font(.system(size: 11))
                    .foregroundColor(Color.white.opacity(0.55))
            }
            .padding(14)
        }
        .widgetURL(LumaDeepLinkDestination.chat.url)
    }
}

// MARK: - Medium Widget View (Quick Actions)

struct MediumWidgetView: View {
    let snapshot: LumaWidgetSnapshot

    var body: some View {
        VStack(spacing: 10) {
            // Header Bar
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#8765F5"))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        )

                    Text("Luma AI")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(snapshot.isAuthenticated ? Color(hex: "#10B981") : Color(hex: "#F59E0B"))
                        .frame(width: 6, height: 6)

                    Text(snapshot.isAuthenticated ? (snapshot.activePersonaName ?? "Ready") : "Guest")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.65))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }

            Spacer()

            // 4 Quick Action Buttons
            HStack(spacing: 8) {
                // 1. Ask Luma
                actionTile(
                    title: "Ask Luma",
                    subtitle: "Chat",
                    icon: "bubble.left.and.bubble.right.fill",
                    accent: Color(hex: "#FFC43D"),
                    destination: .chat,
                    intent: OpenChatIntent()
                )

                // 2. Voice
                actionTile(
                    title: "Voice",
                    subtitle: "Assistant",
                    icon: "waveform",
                    accent: Color(hex: "#8765F5"),
                    destination: .voice,
                    intent: OpenVoiceIntent()
                )

                // 3. Camera
                actionTile(
                    title: "Camera",
                    subtitle: "Analyze",
                    icon: "camera.fill",
                    accent: Color(hex: "#3B82F6"),
                    destination: .camera,
                    intent: OpenCameraIntent()
                )

                // 4. Scan Text
                actionTile(
                    title: "Scan Text",
                    subtitle: "Live OCR",
                    icon: "text.viewfinder",
                    accent: Color(hex: "#10B981"),
                    destination: .scan,
                    intent: OpenScanIntent()
                )
            }
        }
        .padding(14)
    }

    private func actionTile<I: AppIntent>(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        destination: LumaDeepLinkDestination,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.2))
                        .frame(width: 30, height: 30)

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(accent)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(9)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Large Widget View (Luma Dashboard)

struct LargeWidgetView: View {
    let snapshot: LumaWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header Bar
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "#8765F5"))
                        .frame(width: 26, height: 26)
                        .overlay(
                            Image(systemName: "sparkle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Luma AI")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        Text(snapshot.isAuthenticated ? (snapshot.activePersonaName ?? "Intelligent Companion") : "Sign In Required")
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                }

                Spacer()

                if let emoji = snapshot.activePersonaEmoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 18))
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
            }

            // Recent Conversation / Prompt Section
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.isAuthenticated ? "RECENT CONVERSATION" : "GET STARTED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "#FFC43D"))
                    .tracking(0.5)

                Link(destination: LumaDeepLinkDestination.chat.url) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#FFC43D"))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            if let prompt = snapshot.recentPromptTitle, !prompt.isEmpty {
                                Text(prompt)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)

                                Text("Tap to resume conversation in Luma AI")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.55))
                            } else if snapshot.isAuthenticated {
                                Text("Ask your intelligent companion anything")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)

                                Text("Draft ideas, brainstorm, review code, or explore thoughts")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.55))
                                    .lineLimit(1)
                            } else {
                                Text("Sign in to sync recent conversations")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)

                                Text("Unlock full AI chat, voice assistant, and visual creativity")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.35))
                            .padding(.top, 4)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
            }

            Spacer()

            // Quick Actions Section
            VStack(alignment: .leading, spacing: 6) {
                Text("QUICK ACTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.6))
                    .tracking(0.5)

                HStack(spacing: 8) {
                    largeActionTile(
                        title: "Ask Luma",
                        subtitle: "New Chat",
                        icon: "square.and.pencil",
                        accent: Color(hex: "#FFC43D"),
                        intent: OpenChatIntent()
                    )

                    largeActionTile(
                        title: "Voice",
                        subtitle: "Interactive",
                        icon: "waveform",
                        accent: Color(hex: "#8765F5"),
                        intent: OpenVoiceIntent()
                    )

                    largeActionTile(
                        title: "Camera",
                        subtitle: "Snapshot",
                        icon: "camera.fill",
                        accent: Color(hex: "#3B82F6"),
                        intent: OpenCameraIntent()
                    )

                    largeActionTile(
                        title: "Scan",
                        subtitle: "Live OCR",
                        icon: "text.viewfinder",
                        accent: Color(hex: "#10B981"),
                        intent: OpenScanIntent()
                    )
                }
            }
        }
        .padding(16)
    }

    private func largeActionTile<I: AppIntent>(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.2))
                        .frame(width: 34, height: 34)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(accent)
                }

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.white.opacity(0.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lock Screen Widgets

struct LockScreenCircularView: View {
    let snapshot: LumaWidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .bold))
                Text("Ask")
                    .font(.system(size: 9, weight: .bold))
            }
        }
        .widgetURL(LumaDeepLinkDestination.chat.url)
    }
}

struct LockScreenRectangularView: View {
    let snapshot: LumaWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11, weight: .bold))
                Text("LUMA AI")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("Ask")
                    .font(.system(size: 10, weight: .semibold))
            }

            Text("Ask anything · Voice & OCR")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 6) {
                Label("Voice", systemImage: "waveform")
                    .font(.system(size: 9.5, weight: .medium))
                Text("·")
                Label("Scan", systemImage: "text.viewfinder")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .foregroundColor(.secondary)
        }
        .widgetURL(LumaDeepLinkDestination.chat.url)
    }
}

struct LockScreenInlineView: View {
    let snapshot: LumaWidgetSnapshot

    var body: some View {
        ViewThatFits {
            Text("✨ Luma AI · Ask")
            Text("✨ Luma · Ask")
        }
    }
}

// MARK: - Widget Background Helper

private extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                Color(hex: "#121216")
            }
        } else {
            self.background(Color(hex: "#121216"))
        }
    }
}

// MARK: - Color Hex Helper

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 196, 61)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

