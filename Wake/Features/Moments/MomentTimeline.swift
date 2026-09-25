import SwiftUI

/// Moments as a list, grouped by the day they were saved (or ranked, when searching).
struct MomentTimeline: View {
    let moments: [MomentRecord]
    let host: String?
    let now: Date
    let groupsByDay: Bool

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(groups, id: \.title) { group in
                Section {
                    ForEach(group.moments) { moment in
                        TimelineRow(moment: moment, status: MomentStatus.of(moment, host: host, now: now))
                        Divider().padding(.leading, 112)
                    }
                } header: {
                    if groupsByDay {
                        Text(group.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.bar)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var groups: [(title: String, moments: [MomentRecord])] {
        guard groupsByDay else { return [("", moments)] }
        var result: [(title: String, moments: [MomentRecord])] = []
        for moment in moments {
            let title = Self.dayTitle(moment.createdAt, now: now)
            if result.last?.title == title {
                result[result.count - 1].moments.append(moment)
            } else {
                result.append((title, [moment]))
            }
        }
        return result
    }

    private static func dayTitle(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date) { return "This week" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.wide))
        }
        return date.formatted(.dateTime.month(.wide).year())
    }
}

private struct TimelineRow: View {
    @Environment(BrowserModel.self) private var browser
    private var thumbnails: ThumbnailStore { .moments }
    let moment: MomentRecord
    let status: MomentStatus?

    @State private var isHovering = false

    var body: some View {
        Button { browser.openMoment(moment) } label: {
            HStack(alignment: .top, spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(moment.selectedText ?? (moment.title.isEmpty ? moment.host : moment.title))
                        .font(.system(size: 13, weight: moment.selectedText == nil ? .semibold : .regular))
                        .lineLimit(2)
                    Text(moment.note?.isEmpty == false ? moment.note! : moment.host)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let status { StatusChip(status: status) }
                }
                Spacer(minLength: 8)
                Text(moment.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(isHovering ? AnyShapeStyle(.primary.opacity(0.04)) : AnyShapeStyle(.clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(status?.kind == .fading ? 0.6 : 1)
        .onHover { isHovering = $0 }
        .contextMenu { MomentMenu(moment: moment) }
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Group {
            if let image = thumbnails.image(for: moment.id) {
                Color.clear.overlay(alignment: .top) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                }
            } else {
                MonogramIcon.color(for: moment.host).opacity(0.14)
                    .overlay { Favicon(url: URL(string: "https://\(moment.host)/favicon.ico"), host: moment.host, size: 16) }
            }
        }
        .frame(width: 74, height: 46)
        .clipShape(shape)
        .overlay(shape.stroke(.primary.opacity(0.08), lineWidth: 0.5))
    }
}
