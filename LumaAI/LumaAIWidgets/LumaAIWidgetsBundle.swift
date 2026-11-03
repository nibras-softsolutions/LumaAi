import SwiftUI
import WidgetKit

@main
struct LumaAIWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LumaAIWidget()
    }
}

public struct LumaAIWidget: Widget {
    public let kind: String = "LumaAIWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LumaWidgetTimelineProvider()) { entry in
            LumaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Luma AI")
        .description("Quickly ask Luma AI, start voice conversations, take snapshots, or scan text.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
        .contentMarginsDisabled()
    }
}

// MARK: - Previews for All Families

#Preview("Small - Authenticated", as: .systemSmall) {
    LumaAIWidget()
} timeline: {
    LumaWidgetEntry(snapshot: .placeholder)
}

#Preview("Small - Logged Out", as: .systemSmall) {
    LumaAIWidget()
} timeline: {
    LumaWidgetEntry(snapshot: .loggedOut)
}

#Preview("Medium", as: .systemMedium) {
    LumaAIWidget()
} timeline: {
    LumaWidgetEntry(snapshot: .placeholder)
}

#Preview("Large", as: .systemLarge) {
    LumaAIWidget()
} timeline: {
    LumaWidgetEntry(snapshot: .placeholder)
}

#Preview("Lock Screen Circular", as: .accessoryCircular) {
    LumaAIWidget()
} timeline: {
    LumaWidgetEntry(snapshot: .placeholder)
}

#Preview("Lock Screen Rectangular", as: .accessoryRectangular) {
    LumaAIWidget()
} timeline: {
    LumaWidgetEntry(snapshot: .placeholder)
}

#Preview("Lock Screen Inline", as: .accessoryInline) {
    LumaAIWidget()
} timeline: {
    LumaWidgetEntry(snapshot: .placeholder)
}

