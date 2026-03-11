import Foundation
import SwiftUI
import os

struct FeatureAvailability {
    let isAvailable: Bool
    let reason: String?

    static let available = FeatureAvailability(isAvailable: true, reason: nil)
    static func unavailable(_ reason: String) -> FeatureAvailability {
        FeatureAvailability(isAvailable: false, reason: reason)
    }
}

@MainActor
final class FeatureDegradationManager: ObservableObject {
    @Published private(set) var unavailableFeatures: Set<String> = []
    private let logger = Logger(subsystem: "org.moonfin.appletv", category: "FeatureDegradation")

    func checkFeature(
        _ name: String,
        serverType: ServerType,
        requiredFeature: ServerFeature? = nil,
        additionalCheck: (() async -> Bool)? = nil
    ) async -> FeatureAvailability {
        if let required = requiredFeature, !serverType.supports(required) {
            markUnavailable(name)
            return .unavailable("Not supported by \(serverType == .jellyfin ? "Jellyfin" : "Emby")")
        }

        if let check = additionalCheck {
            let ok = await check()
            if !ok {
                markUnavailable(name)
                return .unavailable("Feature unavailable")
            }
        }

        markAvailable(name)
        return .available
    }

    func markUnavailable(_ feature: String) {
        if unavailableFeatures.insert(feature).inserted {
            logger.info("Feature degraded: \(feature)")
        }
    }

    func markAvailable(_ feature: String) {
        unavailableFeatures.remove(feature)
    }

    func isAvailable(_ feature: String) -> Bool {
        !unavailableFeatures.contains(feature)
    }
    func withFallback<T>(
        feature: String,
        primary: () async throws -> T,
        fallback: () async throws -> T
    ) async throws -> T {
        do {
            let result = try await primary()
            markAvailable(feature)
            return result
        } catch {
            logger.warning("Feature \(feature) failed, using fallback: \(error.localizedDescription)")
            markUnavailable(feature)
            return try await fallback()
        }
    }

    func withFallback<T>(
        feature: String,
        primary: () async throws -> T,
        defaultValue: T
    ) async -> T {
        do {
            let result = try await primary()
            markAvailable(feature)
            return result
        } catch {
            logger.warning("Feature \(feature) failed, using default: \(error.localizedDescription)")
            markUnavailable(feature)
            return defaultValue
        }
    }
}

struct FeatureGatedView<Content: View, Fallback: View>: View {
    let feature: String
    let serverType: ServerType
    let requiredFeature: ServerFeature?
    @ViewBuilder let content: () -> Content
    @ViewBuilder let fallback: () -> Fallback

    @EnvironmentObject var degradation: FeatureDegradationManager

    init(
        feature: String,
        serverType: ServerType,
        requiredFeature: ServerFeature? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder fallback: @escaping () -> Fallback = { EmptyView() }
    ) {
        self.feature = feature
        self.serverType = serverType
        self.requiredFeature = requiredFeature
        self.content = content
        self.fallback = fallback
    }

    var body: some View {
        if shouldShow {
            content()
        } else {
            fallback()
        }
    }

    private var shouldShow: Bool {
        if let required = requiredFeature, !serverType.supports(required) {
            return false
        }
        return degradation.isAvailable(feature)
    }
}

extension View {
    func hideIfDegraded(_ feature: String, degradation: FeatureDegradationManager) -> some View {
        let available = degradation.isAvailable(feature)
        return opacity(available ? 1 : 0)
            .disabled(!available)
            .frame(height: available ? nil : 0)
            .clipped()
    }
}
