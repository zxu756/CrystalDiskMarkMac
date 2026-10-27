import SwiftUI

public struct MeterView: View {
    public let title: String
    public let result: BenchmarkResult?
    public let unit: BenchmarkUnit
    public let blockSizeBytes: UInt64
    public let accent: Color

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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(title)
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 0)
                Text(unit.label)
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.secondaryText)
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Theme.track)

                GeometryReader { geometry in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(accent)
                        .frame(width: max(0, geometry.size.width * ratio))
                }

                Text(valueText)
                    .font(Theme.numberFont)
                    .monospacedDigit()
                    .foregroundStyle(result?.isStale == true ? Theme.secondaryText : Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.leading, 6)

                if result?.isStale == true {
                    Text("STALE")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.trailing, 4)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(height: 30)
        }
        .help(tooltip)
    }

    private var valueText: String {
        guard let result else { return "—" }
        switch unit {
        case .mbps:
            return String(format: "%.2f", result.mbps)
        case .gbps:
            return String(format: "%.3f", result.mbps / 1_000)
        case .iops:
            return result.iops >= 1_000_000
                ? String(format: "%.0f", result.iops)
                : String(format: "%.2f", result.iops)
        case .microseconds:
            return String(format: "%.2f", result.latencyUs)
        }
    }

    private var ratio: Double {
        guard let result else { return 0 }
        let value: Double

        if unit == .microseconds {
            guard result.latencyUs > 0.0000000001 else { return 0 }
            value = 1.0 - (1.0 / 6.0) * log10(result.latencyUs)
        } else {
            guard result.mbps > 0.1 else { return 0 }
            value = (1.0 / 6.0) * log10(result.mbps * 10.0)
        }

        return min(max(value, 0), 1)
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
