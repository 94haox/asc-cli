@preconcurrency import AppStoreConnect_Swift_SDK
import Domain
import Foundation

public struct SDKAppAvailabilityRepository: AppAvailabilityRepository, @unchecked Sendable {
    private let client: any APIClient

    public init(client: any APIClient) {
        self.client = client
    }

    public func getAppAvailability(appId: String) async throws -> Domain.AppAvailability {
        let request = APIEndpoint.v1.apps.id(appId).appAvailabilityV2.get(parameters: .init(
            fieldsAppAvailabilities: [.availableInNewTerritories, .territoryAvailabilities],
            fieldsTerritoryAvailabilities: [.available, .releaseDate, .preOrderEnabled, .preOrderPublishDate, .contentStatuses, .territory],
            include: [.territoryAvailabilities],
            limitTerritoryAvailabilities: 200
        ))
        let response = try await client.request(request)
        return mapAvailability(response.data, included: response.included, appId: appId)
    }

    public func createAvailability(
        appId: String,
        isAvailableInNewTerritories: Bool,
        territoryIds: [String]
    ) async throws -> Domain.AppAvailability {
        let body = AppAvailabilityV2CreateRequest(data: .init(
            type: .appAvailabilities,
            attributes: .init(isAvailableInNewTerritories: isAvailableInNewTerritories),
            relationships: .init(
                app: .init(data: .init(type: .apps, id: appId)),
                territoryAvailabilities: .init(data: territoryIds.map { .init(type: .territoryAvailabilities, id: $0) })
            )
        ), included: territoryIds.map { .init(type: .territoryAvailabilities, id: $0) })
        let response = try await client.request(APIEndpoint.v2.appAvailabilities.post(body))
        return mapAvailability(response.data, included: response.included, appId: appId)
    }

    public func updateAvailability(
        appId: String,
        territoryIds: [String],
        isAvailable: Bool
    ) async throws -> Domain.AppAvailability {
        let current = try await getAppAvailability(appId: appId)
        var territories = current.territories

        for territoryId in territoryIds {
            guard let target = territories.first(where: { $0.territoryId == territoryId }) else {
                throw APIError.notFound("No territory availability found for territory \(territoryId) in app \(appId)")
            }

            let request = APIEndpoint.v1.territoryAvailabilities.id(target.id).patch(
                TerritoryAvailabilityUpdateRequest(data: .init(
                    type: .territoryAvailabilities,
                    id: target.id,
                    attributes: .init(isAvailable: isAvailable)
                ))
            )
            let response = try await client.request(request)
            territories.removeAll { $0.id == target.id }
            territories.append(mapTerritoryAvailability(response.data, fallbackTerritoryId: territoryId))
        }

        territories.sort { $0.territoryId < $1.territoryId }
        return Domain.AppAvailability(
            id: current.id,
            appId: current.appId,
            isAvailableInNewTerritories: current.isAvailableInNewTerritories,
            territories: territories
        )
    }

    private func mapAvailability(
        _ sdk: AppAvailabilityV2,
        included: [TerritoryAvailability]?,
        appId: String
    ) -> Domain.AppAvailability {
        let relationshipIds = sdk.relationships?.territoryAvailabilities?.data?.map(\.id) ?? []
        let includedMap = Dictionary(uniqueKeysWithValues: (included ?? []).map { ($0.id, $0) })
        let territoryIds = relationshipIds.isEmpty ? (included ?? []).map(\.id) : relationshipIds
        let territories = territoryIds.compactMap { id -> Domain.AppTerritoryAvailability? in
            if let territoryAvailability = includedMap[id] {
                return mapTerritoryAvailability(territoryAvailability)
            }
            return nil
        }

        return Domain.AppAvailability(
            id: sdk.id,
            appId: appId,
            isAvailableInNewTerritories: sdk.attributes?.isAvailableInNewTerritories ?? false,
            territories: territories
        )
    }

    private func mapTerritoryAvailability(
        _ sdk: AppStoreConnect_Swift_SDK.TerritoryAvailability
    ) -> Domain.AppTerritoryAvailability {
        mapTerritoryAvailability(sdk, fallbackTerritoryId: sdk.relationships?.territory?.data?.id ?? "")
    }

    private func mapTerritoryAvailability(
        _ sdk: AppStoreConnect_Swift_SDK.TerritoryAvailability,
        fallbackTerritoryId: String
    ) -> Domain.AppTerritoryAvailability {
        let territoryId = sdk.relationships?.territory?.data?.id ?? fallbackTerritoryId
        let contentStatuses = (sdk.attributes?.contentStatuses ?? []).compactMap { sdkStatus in
            Domain.ContentStatus(rawValue: sdkStatus.rawValue)
        }
        return Domain.AppTerritoryAvailability(
            id: sdk.id,
            territoryId: territoryId,
            isAvailable: sdk.attributes?.isAvailable ?? false,
            releaseDate: sdk.attributes?.releaseDate,
            isPreOrderEnabled: sdk.attributes?.isPreOrderEnabled ?? false,
            contentStatuses: contentStatuses
        )
    }
}
