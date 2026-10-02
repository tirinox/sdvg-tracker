import SDVGCore
import SwiftUI

/// GitHub-style activity: 53 Monday-first week columns, opened at the latest week.
struct HeatmapView: View {
    @Environment(AppModel.self) private var model
    var cells: [StatsView.Cell]

    private var weeks: [[StatsView.Cell]] {
        stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { i, week in
                        VStack(alignment: .leading, spacing: 3) {
                            // The label may overflow into the next columns without widening this one.
                            Color.clear.frame(width: 13, height: 11).overlay(alignment: .leading) {
                                Text(monthLabel(i)).font(.system(size: 9)).foregroundStyle(.secondary).fixedSize()
                            }
                            ForEach(week, id: \.date) { cell in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(cell.level < 0 ? Color.clear : Palette.heat[cell.level])
                                    .frame(width: 13, height: 13)
                                    .onTapGesture {
                                        guard cell.level >= 0 else { return }
                                        model.dayDate = cell.date
                                        model.tab = .day
                                    }
                                    .accessibilityLabel("\(Fmt.shortDate(cell.date)): \(cell.count)")
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing)
            HStack(spacing: 3) {
                Text(tr("меньше", "less"))
                ForEach(0..<5) { RoundedRectangle(cornerRadius: 2).fill(Palette.heat[$0]).frame(width: 10, height: 10) }
                Text(tr("больше", "more"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func monthLabel(_ i: Int) -> String {
        let m = weeks[i][0].date.dropFirst(5).prefix(2)
        let prev = i > 0 ? weeks[i - 1][0].date.dropFirst(5).prefix(2) : ""
        return m != prev ? Fmt.month(weeks[i][0].date) : ""
    }
}
