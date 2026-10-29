import SwiftUI

public struct MeterView: View {
    public let title: String
    public let result: BenchmarkResult?
    public let unit: BenchmarkUnit
    public let blockSizeBytes: UInt64
    public let accent: Color

    @Environment(\.uiScale) private var uiScale

    public init(
        title: String,
        result: BenchmarkResult?,
        unit: BenchmarkUnit,
        blockSizeBytes: UInt64,
        accent: Color
    ) {
        self.title = title
        self.result = result
        self.unit = unit
        self.blockSizeBytes = blockSizeBytes
        self.accent = accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: uiScale.value(2)) {
            HStack(spacing: uiScale.value(4)) {
                Text(title)
                    .font(uiScale.font(11))
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
                Text(unit.label)
                    .font(uiScale.font(11))
                    .foregroundStyle(Theme.secondaryText)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: uiScale.value(3))
                    .fill(Theme.track)

                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: uiScale.value(3))
                        .fill(accent)
                        .frame(width: max(0, geometry.size.width * ratio))
                }

                Text(valueText)
                    .font(uiScale.font(28, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(result?.isStale == true ? Theme.secondaryText : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.leading, uiScale.value(6))

                if result?.isStale == true {
                    Text("STALE")
                        .font(uiScale.font(7, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.trailing, uiScale.value(4))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: uiScale.value(30))
        }
        .help(tooltip)
    }

    private var valueText: String {
        guard let result else { return "—" }
        return ResultFormatter.valueString(result: result, unit: unit, blockSizeBytes: blockSizeBytes)
    }

    private var ratio: Double {
        ResultFormatter.meterRatio(result: result ?? emptyResult, unit: unit)
    }

    private var emptyResult: BenchmarkResult {
        BenchmarkResult(testID: "empty", operation: .read, mbps: 0, iops: 0, latencyUs: 0)
    }

    private var tooltip: String {
        guard let result else { return "\(title): no result yet" }
        return String(
            format: "%.3f MB/s\n%.3f GB/s\n%.1f IOPS\n%.2f µs\nBlock: %llu bytes",
            result.mbps,
            result.mbps / 1_000,
            result.iops,
            result.latencyUs,
            blockSizeBytes
        )
    }
}
