import Mockable
import Testing
@testable import ASCCommand
@testable import Domain

@Suite
struct AppSetupCommandTests {

    @Test func `info returns app metadata snapshot`() async throws {
        let mockRepo = MockAppRepository()
        given(mockRepo).getApp(id: .value("app-42")).willReturn(
            App(
                id: "app-42",
                name: "My App",
                bundleId: "com.example.myapp",
                sku: "SKU-42",
                primaryLocale: "en-US"
            )
        )

        let cmd = try AppSetupInfo.parse(["--app", "app-42", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        #expect(output == """
        {
          "data" : [
            {
              "affordances" : {
                "availability" : "asc app-setup availability --app app-42",
                "categories" : "asc app-setup categories --app app-42"
              },
              "appId" : "app-42",
              "appName" : "My App",
              "bundleId" : "com.example.myapp",
              "primaryLocale" : "en-US",
              "sku" : "SKU-42"
            }
          ]
        }
        """)
    }

    @Test func `availability delegates to app availability repository`() async throws {
        let mockRepo = MockAppAvailabilityRepository()
        given(mockRepo).getAppAvailability(appId: .value("app-42")).willReturn(
            AppAvailability(
                id: "avail-1",
                appId: "app-42",
                isAvailableInNewTerritories: false,
                territories: []
            )
        )

        let cmd = try AppSetupAvailability.parse(["--app", "app-42", "--pretty"])
        let output = try await cmd.execute(repo: mockRepo)

        #expect(output.contains("\"appId\" : \"app-42\""))
        #expect(output.contains("\"isAvailableInNewTerritories\" : false"))
    }

    @Test func `categories edit updates app info categories`() async throws {
        let appRepo = MockAppRepository()
        let appInfoRepo = MockAppInfoRepository()
        let categoryRepo = MockAppCategoryRepository()

        given(appRepo).getApp(id: .value("app-42")).willReturn(
            App(id: "app-42", name: "My App", bundleId: "com.example.myapp")
        )
        given(appInfoRepo).listAppInfos(appId: .value("app-42")).willReturn([
            AppInfo(id: "info-1", appId: "app-42", primaryCategoryId: "6014")
        ])
        given(appInfoRepo).updateCategories(
            id: .value("info-1"),
            primaryCategoryId: .value("7001"),
            primarySubcategoryOneId: .value(nil),
            primarySubcategoryTwoId: .value(nil),
            secondaryCategoryId: .value("7002"),
            secondarySubcategoryOneId: .value(nil),
            secondarySubcategoryTwoId: .value(nil)
        ).willReturn(
            AppInfo(id: "info-1", appId: "app-42", primaryCategoryId: "7001", secondaryCategoryId: "7002")
        )
        given(categoryRepo).listCategories(platform: .value(nil)).willReturn([])

        let cmd = try AppSetupCategories.parse([
            "--app", "app-42",
            "--edit",
            "--primary-category", "7001",
            "--secondary-category", "7002",
            "--pretty",
        ])

        let output = try await cmd.execute(
            appRepo: appRepo,
            appInfoRepo: appInfoRepo,
            categoryRepo: categoryRepo
        )

        #expect(output.contains("\"primaryCategoryId\" : \"7001\""))
        #expect(output.contains("\"secondaryCategoryId\" : \"7002\""))
    }

    @Test func `categories list combines current and available categories`() async throws {
        let appRepo = MockAppRepository()
        let appInfoRepo = MockAppInfoRepository()
        let categoryRepo = MockAppCategoryRepository()

        given(appRepo).getApp(id: .value("app-42")).willReturn(
            App(id: "app-42", name: "My App", bundleId: "com.example.myapp")
        )
        given(appInfoRepo).listAppInfos(appId: .value("app-42")).willReturn([
            AppInfo(id: "info-1", appId: "app-42", primaryCategoryId: "6014", secondaryCategoryId: "6013")
        ])
        given(categoryRepo).listCategories(platform: .value(nil)).willReturn([
            AppCategory(id: "6014", platforms: ["IOS"], parentId: nil),
            AppCategory(id: "6013", platforms: ["IOS"], parentId: nil),
        ])

        let cmd = try AppSetupCategories.parse(["--app", "app-42", "--pretty"])
        let output = try await cmd.execute(
            appRepo: appRepo,
            appInfoRepo: appInfoRepo,
            categoryRepo: categoryRepo
        )

        #expect(output.contains("\"appInfoId\" : \"info-1\""))
        #expect(output.contains("\"availableCategories\" : 2"))
        #expect(output.contains("\"primaryCategoryId\" : \"6014\""))
    }
}
