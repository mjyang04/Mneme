import MnemeCore
import SwiftUI

struct ResultRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title ?? hit.uri.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                Text(hit.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(hit.uri.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(String(format: "%.2f", hit.score))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch hit.kind {
        case .notes:
            return "note.text"
        case .pdf:
            return "doc.richtext"
        case .code:
            return "chevron.left.forwardslash.chevron.right"
        case .transcript:
            return "waveform"
        case .activity:
            return "calendar"
        }
    }
}
