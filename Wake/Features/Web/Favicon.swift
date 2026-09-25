import SwiftUI

struct Favicon: View {
    let url: URL?
    let host: String
    var size: CGFloat = 12

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().interpolation(.high).scaledToFit()
            } else {
                MonogramIcon(host: host)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size / 4, style: .continuous))
    }
}

/// Stable coloured square with the site's first letter, used until a favicon loads.
struct MonogramIcon: View {
    let host: String

    var body: some View {
        let letter = host.first.map { String($0).uppercased() } ?? "•"
        Rectangle()
            .fill(color)
            .overlay {
                Text(letter)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }

    private var color: Color { Self.color(for: host) }

    static func color(for host: String) -> Color {
        let hue = Double(host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.72)
    }
}
