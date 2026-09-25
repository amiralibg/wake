import SwiftUI

/// A moment in the library: the page as it looked, how far down you were, your
/// highlight or its title, your reason, and one status chip.
struct MomentCard: View {
    let moment: MomentRecord
    let status: MomentStatus?
    var isBestMatch = false
    let onOpen: () -> Void

    private var thumbnails: ThumbnailStore { .moments }
    @State private var isHovering = false

    var body: some View {
        let isFading = status?.kind == .fading
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                    .frame(height: 124)
                    .clipped()
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(moment.host) · \(MomentFormat.saved(moment.createdAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let selection = moment.selectedText {
                        Text(selection)
                            .font(.system(size: 13.5))
                            .lineSpacing(3)
                            .lineLimit(3)
                            .padding(.horizontal, 3)
                            .background(MomentFormat.highlight, in: .rect(cornerRadius: 3))
                    } else {
                        Text(moment.title.isEmpty ? moment.host : moment.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(2)
                    }
                    Text(moment.note?.isEmpty == false ? moment.note! : "No reason given")
                        .font(.system(size: 12))
                        .foregroundStyle(moment.note?.isEmpty == false ? .primary : .tertiary)
                        .lineLimit(2)
                    if let status {
                        StatusChip(status: status)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor), in: shape)
            .clipShape(shape)
            .overlay {
                if isBestMatch {
                    shape.strokeBorder(.tint, lineWidth: 2)
                } else {
                    shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
            .shadow(color: .black.opacity(isHovering ? 0.16 : 0.06), radius: isHovering ? 18 : 10, y: isHovering ? 8 : 4)
            .scaleEffect(isHovering ? 1.01 : 1)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .opacity(isFading ? 0.6 : 1)
        .saturation(isFading ? 0.3 : 1)
        .onHover { hovering in withAnimation(.hover) { isHovering = hovering } }
        .accessibilityLabel("\(moment.title), \(moment.host)")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            if let image = thumbnails.image(for: moment.id) {
                Color.clear.overlay(alignment: .top) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } else {
                MonogramIcon.color(for: moment.host).opacity(0.14)
                    .overlay {
                        Favicon(url: URL(string: "https://\(moment.host)/favicon.ico"), host: moment.host, size: 28)
                            .opacity(0.85)
                    }
            }
            if isBestMatch {
                Text("Best match")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tint, in: Capsule())
                    .padding(12)
            } else if moment.scrollFraction > 0.03 {
                Text("\(Int((moment.scrollFraction * 100).rounded()))% down")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .background(Color(nsColor: .quaternarySystemFill))
    }
}

/// The one thing worth knowing about a moment right now.
struct MomentStatus: Equatable {
    enum Kind { case changed, resurfacing, relevant, fading, archived }
    let kind: Kind
    let text: String

    static func of(_ moment: MomentRecord, host: String?, now: Date) -> MomentStatus? {
        if moment.isArchived { return MomentStatus(kind: .archived, text: "Archived") }
        if moment.changedAt != nil {
            return MomentStatus(kind: .changed, text: "Changed" + (moment.changeSummary.map { " · \($0)" } ?? ""))
        }
        if MomentRules.isResurfacing(moment, now: now) {
            return MomentStatus(kind: .resurfacing, text: "Resurfacing today")
        }
        if MomentRules.isFading(moment, now: now) {
            let days = MomentRules.daysUntilArchive(moment, now: now)
            return MomentStatus(kind: .fading, text: "Fading · archives in \(days) day\(days == 1 ? "" : "s")")
        }
        if MomentRules.isRelevant(moment, host: host), let host {
            return MomentStatus(kind: .relevant, text: "Relevant here · \(host)")
        }
        if let due = moment.resurfaceAt, due > now {
            return MomentStatus(kind: .resurfacing, text: "Resurfaces \(MomentFormat.day(due, now: now))")
        }
        return nil
    }
}

struct StatusChip: View {
    let status: MomentStatus

    var body: some View {
        Text(status.text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: AnyShapeStyle {
        switch status.kind {
        case .changed: AnyShapeStyle(Color(nsColor: .systemOrange))
        case .resurfacing, .relevant: AnyShapeStyle(.tint)
        case .fading, .archived: AnyShapeStyle(.secondary)
        }
    }

    private var background: AnyShapeStyle {
        switch status.kind {
        case .changed: AnyShapeStyle(Color(nsColor: .systemOrange).opacity(0.15))
        case .resurfacing, .relevant: AnyShapeStyle(.tint.opacity(0.13))
        case .fading, .archived: AnyShapeStyle(.primary.opacity(0.06))
        }
    }
}

enum MomentFormat {
    static let highlight = Color(red: 1, green: 0.84, blue: 0.04).opacity(0.4)

    /// "today", "yesterday", "Tuesday", "3 weeks ago", "August".
    static func saved(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days < 7 { return "saved " + date.formatted(.dateTime.weekday(.wide)) }
        if days < 14 { return "last week" }
        if days < 45 { return "\(days / 7) weeks ago" }
        return date.formatted(.dateTime.month(.wide))
    }

    /// "tomorrow", "Saturday", "Oct 3". A weekday only within the coming six days,
    /// so it can't be mistaken for today's.
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        return days < 7 ? date.formatted(.dateTime.weekday(.wide)) : date.formatted(.dateTime.month(.abbreviated).day())
    }
}
