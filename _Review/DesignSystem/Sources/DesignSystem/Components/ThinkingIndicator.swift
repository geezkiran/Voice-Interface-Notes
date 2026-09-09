import SwiftUI

/// The "AI is working on this" moment — three dots pulsing in sequence,
/// the same visual grammar as Grok's own "Thinking…" state. Used while a
/// capture is being parsed/classified, or while a Session is being
/// summarized.
public struct DSThinkingIndicator: View {
    @State private var phase = 0

    public init() {}

    public var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(DSColor.textTertiary)
                    .frame(width: 6, height: 6)
                    .opacity(phase == index ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.25), value: phase)
            }
        }
        .task {
            var tick = 0
            while !Task.isCancelled {
                phase = tick % 3
                tick += 1
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }
}
