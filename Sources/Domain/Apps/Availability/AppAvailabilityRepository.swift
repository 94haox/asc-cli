import Mockable

@Mockable
public protocol AppAvailabilityRepository: Sendable {
    func getAppAvailability(appId: String) async throws -> AppAvailability
    func createAvailability(
        appId: String,
        isAvailableInNewTerritories: Bool,
        territoryIds: [String]
    ) async throws -> AppAvailability
    func updateAvailability(
        appId: String,
        territoryIds: [String],
        isAvailable: Bool
    ) async throws -> AppAvailability
}
