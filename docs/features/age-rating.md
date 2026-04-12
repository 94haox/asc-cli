# Age Rating Feature

Manage the age rating declaration for an app via the App Store Connect API. The age rating declaration controls the content descriptors, kids age band, and regional overrides that determine the store-displayed age rating (e.g. "4+", "12+", "17+"). Age rating declarations are associated with an `AppInfo` (not directly with the app or version).

## CLI Usage

### Get Age Rating Declaration

Fetch the full age rating declaration for an app info.

```bash
asc age-rating get --app-info-id <APP_INFO_ID>
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--app-info-id` | *(required)* | App Info ID (get from `asc app-infos list`) |
| `--output` | `json` | Output format: `json`, `table`, `markdown` |
| `--pretty` | `false` | Pretty-print JSON |

**Example:**

```bash
asc age-rating get --app-info-id info-abc123 --pretty
```

**JSON output (nil fields omitted):**

```json
{
  "data": [
    {
      "id": "decl-xyz789",
      "appInfoId": "info-abc123",
      "isAdvertising": false,
      "violenceRealistic": "NONE",
      "profanityOrCrudeHumor": "NONE",
      "kidsAgeBand": null,
      "ageRatingOverride": "NONE",
      "affordances": {
        "update": "asc age-rating update --declaration-id decl-xyz789",
        "getAgeRating": "asc age-rating get --app-info-id info-abc123"
      }
    }
  ]
}
```

---

### Update Age Rating Declaration

Update individual fields via PATCH — only provided flags are changed.

```bash
asc age-rating update --declaration-id <DECLARATION_ID> [flags]
```

**Boolean content flags (true/false):**

| Flag | Description |
|------|-------------|
| `--advertising` | Contains advertising |
| `--gambling` | Contains gambling |
| `--health-or-wellness` | Contains health or wellness topics |
| `--loot-box` | Contains loot box mechanics |
| `--messaging-and-chat` | Contains messaging or chat |
| `--parental-controls` | Contains parental controls |
| `--age-assurance` | Contains age assurance |
| `--unrestricted-web-access` | Contains unrestricted web access |
| `--user-generated-content` | Contains user-generated content |

**Intensity flags** (`NONE` / `INFREQUENT_OR_MILD` / `FREQUENT_OR_INTENSE` / `INFREQUENT` / `FREQUENT`):

| Flag | Description |
|------|-------------|
| `--alcohol-tobacco-drugs` | Alcohol, tobacco or drug use |
| `--contests` | Contests |
| `--gambling-simulated` | Simulated gambling |
| `--guns-weapons` | Guns or other weapons |
| `--medical-treatment` | Medical or treatment information |
| `--profanity` | Profanity or crude humor |
| `--sexual-content-graphic` | Sexual content (graphic and nudity) |
| `--sexual-content` | Sexual content or nudity |
| `--horror-fear` | Horror or fear themes |
| `--mature-suggestive` | Mature or suggestive themes |
| `--violence-cartoon` | Cartoon or fantasy violence |
| `--violence-realistic-prolonged` | Prolonged, graphic or sadistic realistic violence |
| `--violence-realistic` | Realistic violence |

**Override flags:**

| Flag | Values | Description |
|------|--------|-------------|
| `--kids-age-band` | `FIVE_AND_UNDER` / `SIX_TO_EIGHT` / `NINE_TO_ELEVEN` | Kids category age band |
| `--age-rating-override` | `NONE` / `NINE_PLUS` / `THIRTEEN_PLUS` / `SIXTEEN_PLUS` / `EIGHTEEN_PLUS` / `UNRATED` | Global age rating override |
| `--korea-age-rating-override` | `NONE` / `FIFTEEN_PLUS` / `NINETEEN_PLUS` | Korea-specific override |

**Examples:**

```bash
# Set violence rating and disable gambling flag
asc age-rating update --declaration-id decl-xyz789 \
  --violence-realistic NONE \
  --gambling false

# Mark app as kids app (ages 9-11)
asc age-rating update --declaration-id decl-xyz789 \
  --kids-age-band NINE_TO_ELEVEN

# Apply 17+ age rating override
asc age-rating update --declaration-id decl-xyz789 \
  --age-rating-override EIGHTEEN_PLUS
```

---

## Typical Workflow

```bash
# 1. Find your app
asc apps list --output table

# 2. Get the AppInfo ID for your app
asc app-infos list --app-id <APP_ID> --output table

# 3. Get the current age rating declaration
asc age-rating get --app-info-id <APP_INFO_ID> --pretty
# → Note the "id" (declaration ID) from the response

# 4. Update specific content ratings
asc age-rating update --declaration-id <DECLARATION_ID> \
  --violence-realistic NONE \
  --gambling false \
  --advertising false

# 5. Verify the update
asc age-rating get --app-info-id <APP_INFO_ID> --pretty
```

Each response includes an `affordances` field with ready-to-run follow-up commands for AI agents.

---

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                     Age Rating Feature                              │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ASC API                    Infrastructure            Domain        │
│  ┌──────────────────────┐  ┌─────────────────────┐  ┌───────────┐  │
│  │ GET /v1/appInfos/    │  │                     │  │ AgeRating │  │
│  │ {id}/ageRating-      │─▶│ SDKAgeRating        │─▶│ Declara-  │  │
│  │ Declaration          │  │ Declaration         │  │ tion      │  │
│  │                      │  │ Repository          │  │ (struct)  │  │
│  │ PATCH /v1/ageRating- │  │                     │  └───────────┘  │
│  │ Declarations/{id}    │─▶│ (implements         │  ┌───────────┐  │
│  │                      │  │  AgeRatingDecl-     │  │ AgeRating │  │
│  │                      │  │  arationRepository) │  │ Declara-  │  │
│  │                      │  │                     │  │ tion      │  │
│  │                      │  │                     │  │ Repository│  │
│  │                      │  │                     │  │(@Mockable)│  │
│  └──────────────────────┘  └─────────────────────┘  └───────────┘  │
│                                                                     │
│  Resource hierarchy:                                                │
│  App → AppInfo → AgeRatingDeclaration                              │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  ASCCommand Layer                                           │   │
│  │  asc age-rating get --app-info-id <id>                      │   │
│  │  asc age-rating update --declaration-id <id> [flags]        │   │
│  └─────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────┘
```

**Dependency direction:** `ASCCommand → Infrastructure → Domain`

---

## Domain Models

### `AgeRatingDeclaration`

The full content rating questionnaire for an app. All content fields are optional — the API returns only fields that have been explicitly set.

```swift
public struct AgeRatingDeclaration: Sendable, Equatable, Identifiable, Codable {
    public let id: String
    public let appInfoId: String   // Parent ID, always injected by Infrastructure

    // Boolean content flags
    public let isAdvertising: Bool?
    public let isGambling: Bool?
    public let isHealthOrWellnessTopics: Bool?
    public let isLootBox: Bool?
    public let isMessagingAndChat: Bool?
    public let isParentalControls: Bool?
    public let isAgeAssurance: Bool?
    public let isUnrestrictedWebAccess: Bool?
    public let isUserGeneratedContent: Bool?

    // Content intensity ratings
    public let alcoholTobaccoOrDrugUseOrReferences: ContentIntensity?
    public let contests: ContentIntensity?
    public let gamblingSimulated: ContentIntensity?
    public let gunsOrOtherWeapons: ContentIntensity?
    public let medicalOrTreatmentInformation: ContentIntensity?
    public let profanityOrCrudeHumor: ContentIntensity?
    public let sexualContentGraphicAndNudity: ContentIntensity?
    public let sexualContentOrNudity: ContentIntensity?
    public let horrorOrFearThemes: ContentIntensity?
    public let matureOrSuggestiveThemes: ContentIntensity?
    public let violenceCartoonOrFantasy: ContentIntensity?
    public let violenceRealisticProlongedGraphicOrSadistic: ContentIntensity?
    public let violenceRealistic: ContentIntensity?

    // Override ratings
    public let kidsAgeBand: KidsAgeBand?
    public let ageRatingOverride: AgeRatingOverride?
    public let koreaAgeRatingOverride: KoreaAgeRatingOverride?

    // Affordances
    "update":       "asc age-rating update --declaration-id <id>"
    "getAgeRating": "asc age-rating get --app-info-id <appInfoId>"
}
```

**Custom `Codable`:** nil fields are omitted from JSON output using `encodeIfPresent`.

### `ContentIntensity`

Shared enum for all 13 content intensity fields.

```swift
public enum ContentIntensity: String, Sendable, Equatable, Codable, CaseIterable {
    case none = "NONE"
    case infrequentOrMild = "INFREQUENT_OR_MILD"
    case frequentOrIntense = "FREQUENT_OR_INTENSE"
    case infrequent = "INFREQUENT"
    case frequent = "FREQUENT"
}
```

### `KidsAgeBand`

```swift
public enum KidsAgeBand: String, Sendable, Equatable, Codable, CaseIterable {
    case fiveAndUnder = "FIVE_AND_UNDER"
    case sixToEight = "SIX_TO_EIGHT"
    case nineToEleven = "NINE_TO_ELEVEN"
}
```

### `AgeRatingOverride`

```swift
public enum AgeRatingOverride: String, Sendable, Equatable, Codable, CaseIterable {
    case none = "NONE"
    case ninePlus = "NINE_PLUS"
    case thirteenPlus = "THIRTEEN_PLUS"
    case sixteenPlus = "SIXTEEN_PLUS"
    case eighteenPlus = "EIGHTEEN_PLUS"
    case unrated = "UNRATED"
}
```

### `KoreaAgeRatingOverride`

```swift
public enum KoreaAgeRatingOverride: String, Sendable, Equatable, Codable, CaseIterable {
    case none = "NONE"
    case fifteenPlus = "FIFTEEN_PLUS"
    case nineteenPlus = "NINETEEN_PLUS"
}
```

### `AgeRatingDeclarationUpdate`

Partial update value type — only set fields are sent in the PATCH request.

```swift
public struct AgeRatingDeclarationUpdate: Sendable {
    public var isAdvertising: Bool?
    public var isGambling: Bool?
    // ... (all same fields as AgeRatingDeclaration)
    public init() {}
}
```

### `AgeRatingDeclarationRepository`

The DI boundary between the command layer and the API. Annotated with `@Mockable` for testing.

```swift
@Mockable
public protocol AgeRatingDeclarationRepository: Sendable {
    func getDeclaration(appInfoId: String) async throws -> AgeRatingDeclaration
    func updateDeclaration(id: String, update: AgeRatingDeclarationUpdate) async throws -> AgeRatingDeclaration
}
```

---

## File Map

```
Sources/
├── Domain/Apps/AppInfos/
│   ├── AgeRatingDeclaration.swift          # Value types + enums + AffordanceProviding
│   └── AgeRatingDeclarationRepository.swift # @Mockable protocol (2 methods)
│
├── Infrastructure/Apps/AppInfos/
│   └── SDKAgeRatingDeclarationRepository.swift  # GET + PATCH; injects appInfoId; maps SDK enums
│
└── ASCCommand/Commands/AgeRating/
    └── AgeRatingCommand.swift              # AgeRatingCommand + AgeRatingGet + AgeRatingUpdate

Tests/
├── DomainTests/Apps/AppInfos/
│   └── AgeRatingDeclarationTests.swift     # Parent ID, affordances, enum raw values, field storage
├── DomainTests/Apps/
│   └── AffordancesTests.swift              # Modified: added AgeRatingDeclaration + AppInfo affordance tests
├── DomainTests/TestHelpers/
│   └── MockRepositoryFactory.swift         # Modified: added makeAgeRatingDeclaration()
├── InfrastructureTests/Apps/AppInfos/
│   └── SDKAgeRatingDeclarationRepositoryTests.swift  # Parent ID injection, field mapping
└── ASCCommandTests/Commands/AgeRating/
    ├── AgeRatingGetTests.swift             # Exact JSON output with affordances
    └── AgeRatingUpdateTests.swift          # Exact JSON output + update flag passing
```

**Wiring files modified:**

| File | Change |
|------|--------|
| `Sources/Infrastructure/Client/ClientFactory.swift` | Added `makeAgeRatingDeclarationRepository(authProvider:)` |
| `Sources/ASCCommand/ClientProvider.swift` | Added `makeAgeRatingDeclarationRepository()` |
| `Sources/ASCCommand/ASC.swift` | Added `AgeRatingCommand.self` |
| `Sources/Domain/Apps/AppInfos/AppInfo.swift` | Added `getAgeRating` affordance |
| `Tests/ASCCommandTests/Commands/AppInfos/AppInfosListTests.swift` | Updated AppInfo affordances snapshot |

---

## App Store Connect API Reference

| Endpoint | SDK call | Used by |
|----------|----------|---------|
| `GET /v1/appInfos/{id}/ageRatingDeclaration` | `.appInfos.id(id).ageRatingDeclaration.get()` | `getDeclaration(appInfoId:)` |
| `PATCH /v1/ageRatingDeclarations/{id}` | `.ageRatingDeclarations.id(id).patch(body)` | `updateDeclaration(id:update:)` |

The SDK is from [appstoreconnect-swift-sdk](https://github.com/AvdLee/appstoreconnect-swift-sdk). Each content category in the SDK has its own enum type (e.g. `ViolenceRealistic`, `ProfanityOrCrudeHumor`) — all with identical cases. The Infrastructure mapper uses a generic `mapIntensity<T: RawRepresentable>(_ value: T?) -> ContentIntensity?` to convert all of them using their shared `String` raw values, avoiding repetitive mapping code.

**Note:** The SDK's `AgeRatingDeclarationUpdateRequest` also encodes `kidsAgeBand` using `encode` (not `encodeIfPresent`), so it is always included in the PATCH body when set. `ageRatingOverrideV2` is the non-deprecated V2 field — the domain model exposes this as `ageRatingOverride`.

---

## Testing

Tests follow the **Chicago school TDD** pattern: assert on state and return values, not on interactions.

```swift
@Test func `getDeclaration injects appInfoId`() async throws {
    let stub = StubAPIClient()
    stub.willReturn(AgeRatingDeclarationResponse(
        data: AgeRatingDeclaration(type: .ageRatingDeclarations, id: "decl-1"),
        links: .init(this: "")
    ))
    let repo = SDKAgeRatingDeclarationRepository(client: stub)
    let result = try await repo.getDeclaration(appInfoId: "info-42")
    #expect(result.id == "decl-1")
    #expect(result.appInfoId == "info-42")
}

@Test func `age-rating update passes only specified flags`() async throws {
    let mockRepo = MockAgeRatingDeclarationRepository()
    var capturedUpdate: AgeRatingDeclarationUpdate?
    given(mockRepo).updateDeclaration(id: .any, update: .any)
        .willProduce { _, update in
            capturedUpdate = update
            return AgeRatingDeclaration(id: "decl-1", appInfoId: "")
        }
    let cmd = try AgeRatingUpdate.parse([
        "--declaration-id", "decl-1",
        "--gambling", "true",
        "--violence-cartoon", "INFREQUENT_OR_MILD",
    ])
    _ = try await cmd.execute(repo: mockRepo)
    let update = try #require(capturedUpdate)
    #expect(update.isGambling == true)
    #expect(update.violenceCartoonOrFantasy == .infrequentOrMild)
    #expect(update.isAdvertising == nil)  // not provided → nil
}
```

Run the full test suite:

```bash
swift test --filter 'AgeRating'
```

---

## Extending the Feature

### Adding territory-specific age ratings

Not implemented in asc-cli yet. The App Store Connect API also exposes per-territory age ratings via `/v1/appInfos/{id}/territoryAgeRatings`. This returns the computed store-displayed ratings (e.g. "12+" in France) rather than the editable declaration fields.

There is no `asc age-rating territories` subcommand in this repository.
