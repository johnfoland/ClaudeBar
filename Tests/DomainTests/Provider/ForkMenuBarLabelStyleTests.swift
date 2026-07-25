import Testing
import Foundation
import Mockable
@testable import Domain

/// Fork-only: the menu bar label reads `"83% | 25m • 51% | 3d"` instead of
/// upstream's `"5h 83% · 25m | 7d 51% · 3d"`.
@Suite
struct ForkMenuBarLabelStyleTests {

    private func dualWindowLabel(
        primary: (text: String, status: QuotaStatus),
        secondary: (text: String, status: QuotaStatus),
        status: QuotaStatus
    ) -> MenuBarLabel {
        let segments = [
            MenuBarLabel.Segment(text: primary.text, status: primary.status),
            MenuBarLabel.Segment(text: secondary.text, status: secondary.status),
        ]
        return MenuBarLabel(
            text: segments.map(\.text).joined(separator: " | "),
            status: status,
            segments: segments
        )
    }

    // MARK: - Dual Window

    @Test
    func `drops the quota window prefixes and swaps both separators`() {
        let label = dualWindowLabel(
            primary: ("5h 83% · 25m", .healthy),
            secondary: ("7d 51% · 3d", .healthy),
            status: .healthy
        )

        let styled = label.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")

        #expect(styled.text == "83% | 25m • 51% | 3d")
    }

    @Test
    func `restyles each segment so stacked rendering loses the prefixes too`() {
        let label = dualWindowLabel(
            primary: ("5h 83% · 25m", .healthy),
            secondary: ("7d 51% · 3d", .warning),
            status: .warning
        )

        let styled = label.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")

        #expect(styled.segments.map(\.text) == ["83% | 25m", "51% | 3d"])
    }

    @Test
    func `keeps every status untouched`() {
        let label = dualWindowLabel(
            primary: ("5h 83%", .healthy),
            secondary: ("7d 15%", .critical),
            status: .critical
        )

        let styled = label.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")

        #expect(styled.status == .critical)
        #expect(styled.segments.map(\.status) == [.healthy, .critical])
    }

    @Test
    func `drops model and time window prefixes`() {
        let label = dualWindowLabel(
            primary: ("Opus 40%", .warning),
            secondary: ("MCP Usage 90%", .healthy),
            status: .warning
        )

        let styled = label.forkStyled(
            primaryQuotaKey: "model:opus",
            secondaryQuotaKey: "time:MCP Usage"
        )

        #expect(styled.text == "40% • 90%")
    }

    @Test
    func `leaves text alone when it does not carry the expected prefix`() {
        let label = dualWindowLabel(
            primary: ("83%", .healthy),
            secondary: ("51%", .healthy),
            status: .healthy
        )

        let styled = label.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")

        #expect(styled.text == "83% • 51%")
    }

    // MARK: - Single Window

    @Test
    func `swaps the separator on a single window label`() {
        let label = MenuBarLabel(text: "83% · 25m", status: .healthy)

        let styled = label.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "")

        #expect(styled.text == "83% | 25m")
        #expect(styled.segments.map(\.text) == ["83% | 25m"])
    }

    @Test
    func `leaves a bare percentage unchanged`() {
        let label = MenuBarLabel(text: "83%", status: .healthy)

        let styled = label.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")

        #expect(styled.text == "83%")
        #expect(styled.status == .healthy)
    }

    // MARK: - Idempotence

    /// The driver can re-style a label it already showed (the last-known-label
    /// fallback), so a second pass must not change anything.
    @Test
    func `restyling an already restyled label changes nothing`() {
        let label = dualWindowLabel(
            primary: ("5h 83% · 25m", .healthy),
            secondary: ("7d 51% · 3d", .healthy),
            status: .healthy
        )

        let once = label.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")
        let twice = once.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")

        #expect(twice == once)
    }
}

/// Guards the fork's restyling against upstream changing the label format it
/// rewrites: these go through the real `QuotaMonitor.menuBarLabel(...)`, so a
/// new prefix or separator upstream fails here instead of shipping.
@Suite
@MainActor
struct ForkMenuBarLabelStyleIntegrationTests {
    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private func makeRefreshedClaudeMonitor(quotas: [UsageQuota]) async -> QuotaMonitor {
        let settings = MockProviderSettingsRepository()
        given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(settings).isEnabled(forProvider: .any).willReturn(true)
        given(settings).setEnabled(.any, forProvider: .any).willReturn()

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: quotas,
            capturedAt: Date()
        ))

        let provider = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [provider]), clock: TestClock())
        await monitor.refresh(providerId: "claude")
        return monitor
    }

    @Test
    func `session and weekly percentages plus durations read in the fork format`() async {
        // Given — session 83% resetting in 25m, weekly 51% resetting in 3d
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(
                percentRemaining: 83,
                quotaType: .session,
                providerId: "claude",
                resetsAt: Date().addingTimeInterval(25 * 60 + 30)
            ),
            UsageQuota(
                percentRemaining: 51,
                quotaType: .weekly,
                providerId: "claude",
                resetsAt: Date().addingTimeInterval(3 * 86_400 + 3600)
            ),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "weekly",
            showPercentage: true,
            showDuration: true,
            mode: .remaining
        )?.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")

        // Then
        #expect(label?.text == "83% | 25m • 51% | 3d")
    }

    @Test
    func `percentage only dual window keeps the window separator`() async {
        // Given
        let monitor = await makeRefreshedClaudeMonitor(quotas: [
            UsageQuota(percentRemaining: 83, quotaType: .session, providerId: "claude"),
            UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude"),
        ])

        // When
        let label = monitor.menuBarLabel(
            providerId: "claude",
            primaryQuotaKey: "session",
            secondaryQuotaKey: "weekly",
            showPercentage: true,
            showDuration: false,
            mode: .remaining
        )?.forkStyled(primaryQuotaKey: "session", secondaryQuotaKey: "weekly")

        // Then — prefixes gone, windows joined by the fork's bullet
        #expect(label?.text == "83% • 35%")
        #expect(label?.status == .warning)
    }
}
