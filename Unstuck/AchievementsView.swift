import SwiftUI

/// "Look what you did" — a private, on-device celebration of REAL progress: your earned Top
/// Dollar credits, what you've cleared, and the milestone ladder you've climbed. Never compared
/// to anyone (no leaderboard, by design — that's the RSD landmine the app refuses), never
/// punishing (no "behind", no streak). Just: here's what you, specifically, did.
struct AchievementsView: View {
    @Binding var isPresented: Bool
    let clusters: [Cluster]
    @State private var cardImage: Image? = nil   // opt-in share card, rendered on appear

    private let prog = Progression.shared
    private let gold = Color(red: 1.0, green: 0.82, blue: 0.32)
    private let teal = Color(red: 0.30, green: 0.85, blue: 0.75)

    private var doneCount: Int { clusters.flatMap(\.items).filter { $0.state == .done }.count }

    var body: some View {
        ZStack {
            Color.black.opacity(0.84).ignoresSafeArea().onTapGesture { close() }
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text("look what you did")
                            .font(.system(.title3, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        Spacer()
                        if let img = cardImage {
                            ShareLink(item: img, preview: SharePreview("my unstuck", image: img)) {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6)).frame(width: 34, height: 34).panel(Circle())
                            }
                            .accessibilityLabel("Share a win")
                        }
                        Button { close() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5)).frame(width: 34, height: 34).panel(Circle())
                        }
                        .buttonStyle(.plain).accessibilityLabel("Close")
                    }

                    // The credit pile — the headline of what you earned.
                    VStack(spacing: 4) {
                        Text("\(prog.credits)")
                            .font(.system(size: 56, weight: .black, design: .rounded).monospacedDigit())
                            .foregroundStyle(gold)
                            .shadow(color: gold.opacity(0.45), radius: 16)
                        Text("CREDITS EARNED").font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(gold.opacity(0.7)).tracking(2)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .panel(RoundedRectangle(cornerRadius: 22, style: .continuous), tint: gold.opacity(0.08))

                    HStack(spacing: 12) {
                        stat("\(doneCount)", "cleared", teal)
                        stat("\(prog.captured)", "externalized", .white.opacity(0.75))
                    }

                    // The milestone ladder — reached marks glow; the next shows your "almost there".
                    VStack(alignment: .leading, spacing: 10) {
                        Text("milestones")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                        // Most-square grid via the √n divisor shortcut (9 marks → a tidy 3×3).
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                 count: squareGridColumns(prog.milestones.count)), spacing: 8) {
                            ForEach(prog.milestones, id: \.self) { m in
                                milestone(m)
                            }
                        }
                    }

                    // Personal records — you vs. your past self. Only ever celebrates; never
                    // shows you sitting below your best (that'd be the RSD trap).
                    if prog.activeDays > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("your records")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                            HStack(spacing: 12) {
                                record("\(prog.bestDay)", "best day")
                                record("\(prog.bestWeek)", "best week")
                                record("\(prog.activeDays)", "active days")
                            }
                            if prog.bestWeek > 0, prog.thisWeekCount >= prog.bestWeek {
                                Text("🎉 this week matches your best — \(prog.thisWeekCount)")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(gold)
                            }
                        }
                    }

                    // Where the wins landed — the spread, in each cluster's colour.
                    if doneCount > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("where").font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                            ForEach(clusters.filter { $0.items.contains { $0.state == .done } }, id: \.id) { c in
                                HStack(spacing: 8) {
                                    Circle().fill(Color(hex: c.effectiveHighlightHex)).frame(width: 7, height: 7)
                                    Text(c.label).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.72))
                                    Spacer()
                                    Text("\(c.items.filter { $0.state == .done }.count)")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                        }
                        .padding(14)
                        .panel(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Text("your own pace · never compared to anyone")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
                }
                .padding(22).padding(.top, 28)
            }
        }
        .transition(.opacity)
        .onAppear { renderCard() }
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .panel(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func milestone(_ m: Int) -> some View {
        let hit = prog.completed >= m
        let isNext = m == prog.nextMark
        return Text("\(m)")
            .font(.system(size: 13, weight: hit ? .bold : .regular, design: .monospaced))
            .foregroundStyle(hit ? .white : .white.opacity(0.3))
            .frame(width: 44, height: 44)
            .background(Circle().fill(hit ? teal.opacity(0.18) : .white.opacity(0.03)))
            .overlay(Circle().stroke(isNext ? teal : (hit ? teal.opacity(0.5) : .white.opacity(0.1)),
                                     lineWidth: isNext ? 2 : 1))
            .overlay {
                if isNext {
                    Circle().trim(from: 0, to: prog.progressToNext)
                        .stroke(teal, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 44, height: 44).rotationEffect(.degrees(-90))
                }
            }
    }

    private func record(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(size: 22, weight: .black, design: .rounded).monospacedDigit()).foregroundStyle(.white)
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .panel(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @MainActor private func renderCard() {
        let r = ImageRenderer(content: ShareCard(cleared: doneCount, credits: prog.credits))
        r.scale = 3
        if let ui = r.uiImage { cardImage = Image(uiImage: ui) }
    }

    private func close() { withAnimation(.easeOut(duration: 0.25)) { isPresented = false } }
}

/// The opt-in share card — rendered to an image and sent via the system share sheet. No account,
/// no server: you choose what/when/who. No-label, on-brand (sharable in public, so it stays clean).
private struct ShareCard: View {
    let cleared: Int
    let credits: Int
    var body: some View {
        VStack(spacing: 8) {
            Text("● unstuck")
                .font(.system(size: 15, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text("\(cleared)")
                .font(.system(size: 96, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text("things cleared")
                .font(.system(size: 19, design: .monospaced)).foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.75))
            Spacer()
            Text("\(credits) credits · my own pace")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
        }
        .padding(28)
        .frame(width: 340, height: 340)
        .background(
            LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.16), Color(red: 0.01, green: 0.01, blue: 0.05)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}
