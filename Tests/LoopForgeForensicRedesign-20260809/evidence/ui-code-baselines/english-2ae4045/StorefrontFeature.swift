import MapKit
import Observation
import OSLog
import PhotosUI
import Security
import SwiftUI
import UIKit

enum StorefrontTransactionType: String, Codable, CaseIterable, Identifiable {
    case rent
    case businessSale = "business_sale"
    case sale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rent: "For Rent"
        case .businessSale: "Business Sale"
        case .sale: "Property Sale"
        }
    }

    var shortTitle: String {
        switch self {
        case .rent: "For Rent"
        case .businessSale: "Business Sale"
        case .sale: "Property Sale"
        }
    }

    var detail: String {
        switch self {
        case .rent: "Direct lease from landlord or new listing"
        case .businessSale: "Buy the operating assets and, if approved, assume or replace the lease"
        case .sale: "Purchase property title"
        }
    }

    var filterTitle: String {
        switch self {
        case .rent: "Rent"
        case .businessSale: "Business"
        case .sale: "Property"
        }
    }

    var symbol: String {
        switch self {
        case .rent: "key.fill"
        case .businessSale: "arrow.left.arrow.right.circle.fill"
        case .sale: "building.2.crop.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .rent: AppTheme.blue
        case .businessSale: AppTheme.amber
        case .sale: AppTheme.mint
        }
    }
}

struct StorefrontListing: Codable, Identifiable, Equatable {
    let id: String
    let transactionType: StorefrontTransactionType
    let title: String
    let currentBusiness: String?
    let suitableCategoryIDs: [String]
    let placeName: String
    let address: String
    let city: String
    let county: String
    let latitude: Double
    let longitude: Double
    let coordinateReference: String
    let areaSquareFeet: Double
    let floorLabel: String
    let monthlyRentUSD: Int?
    let saleTotalUSD: Int?
    let businessAskingPriceUSD: Int?
    let depositUSD: Int?
    let estimatedCAMNNNUSD: Int?
    let featureIDs: [String]
    let description: String
    let contactName: String
    let contactPhone: String
    let photoURLs: [String]
    let status: String
    let createdAt: Date
    let updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case transactionType
        case title
        case currentBusiness
        case suitableCategoryIDs = "suitableCategoryIds"
        case placeName
        case address
        case city
        case county
        case latitude
        case longitude
        case coordinateReference
        case areaSquareFeet
        case floorLabel
        case monthlyRentUSD = "monthlyRentUsd"
        case saleTotalUSD = "saleTotalUsd"
        case businessAskingPriceUSD = "businessAskingPriceUsd"
        case depositUSD = "depositUsd"
        case estimatedCAMNNNUSD = "estimatedCamNnnUsd"
        case featureIDs = "featureIds"
        case description
        case contactName
        case contactPhone
        case photoURLs = "photoUrls"
        case status
        case createdAt
        case updatedAt
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var primaryPrice: String {
        switch transactionType {
        case .rent:
            monthlyRentUSD.map { "$\($0.formatted())/month" } ?? "Rent negotiable"
        case .businessSale:
            businessAskingPriceUSD.map { "Business asking price $\($0.formatted())" } ?? "Asking price negotiable"
        case .sale:
            saleTotalUSD.map { "$\($0.formatted())" } ?? "Price negotiable"
        }
    }

    var secondaryPrice: String? {
        guard transactionType == .businessSale, let monthlyRentUSD else { return nil }
        return "Monthly rent $\(monthlyRentUSD.formatted())"
    }
}

struct StorefrontListingPage: Codable {
    let items: [StorefrontListing]
    let total: Int
}

struct StorefrontUploadedMedia: Codable {
    let id: String
    let width: Int
    let height: Int
}

struct StorefrontRecommendationSource: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let url: String
    let publisher: String?
}

struct StorefrontRecommendedArea: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let city: String
    let county: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Int
    let headline: String
    let reason: String
    let fitNotes: [String]
    let contextHighlights: [String]
    let caution: String
    let sourceIDs: [String]
    let matchedListingIDs: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var radiusMiles: Double {
        Double(radiusMeters) / 1_609.344
    }
}

struct StorefrontRecommendationResult: Codable, Equatable {
    let summary: String
    let areas: [StorefrontRecommendedArea]
    let sources: [StorefrontRecommendationSource]
    let generatedAt: Date
}

struct StorefrontRecommendationJob: Decodable, Equatable {
    let id: String
    let state: String
    let stage: String
    let progressPercent: Int
    let detail: String
    let result: StorefrontRecommendationResult?
    let error: ServerFailure?
}

struct StorefrontRecommendationRequest: Codable, Equatable {
    let category: BusinessCategory
    let subcategory: String
    let investmentBudgetUSD: Int
    let counties: [String]

    private enum CodingKeys: String, CodingKey {
        case category
        case subcategory
        case investmentBudgetUSD = "investmentBudgetUsd"
        case counties
    }
}

struct StorefrontAdministrativeArea: Codable, Identifiable, Equatable {
    let name: String
    let code: String
    let level: String

    var id: String { code }
}

struct StorefrontListingCreateRequest: Codable {
    let transactionType: StorefrontTransactionType
    let title: String
    let currentBusiness: String?
    let suitableCategoryIDs: [BusinessCategory]
    let placeName: String
    let address: String
    let city: String
    let county: String
    let latitude: Double
    let longitude: Double
    let coordinateReference: String
    let areaSquareFeet: Double
    let floorLabel: String
    let monthlyRentUSD: Int?
    let saleTotalUSD: Int?
    let businessAskingPriceUSD: Int?
    let depositUSD: Int?
    let estimatedCAMNNNUSD: Int?
    let featureIDs: [String]
    let description: String
    let contactName: String
    let contactPhone: String
    let photoIDs: [String]
    let acceptsContactPublication: Bool

    private enum CodingKeys: String, CodingKey {
        case transactionType
        case title
        case currentBusiness
        case suitableCategoryIDs = "suitableCategoryIds"
        case placeName
        case address
        case city
        case county
        case latitude
        case longitude
        case coordinateReference
        case areaSquareFeet
        case floorLabel
        case monthlyRentUSD = "monthlyRentUsd"
        case saleTotalUSD = "saleTotalUsd"
        case businessAskingPriceUSD = "businessAskingPriceUsd"
        case depositUSD = "depositUsd"
        case estimatedCAMNNNUSD = "estimatedCamNnnUsd"
        case featureIDs = "featureIds"
        case description
        case contactName
        case contactPhone
        case photoIDs = "photoIds"
        case acceptsContactPublication
    }
}

struct StorefrontPublishDraft: Codable, Equatable {
    var transactionType: StorefrontTransactionType = .rent
    var title = ""
    var currentBusiness = ""
    var suitableCategoryIDs: [BusinessCategory] = []
    var location: LocationCandidate?
    var city = ""
    var county = ""
    var areaText = ""
    var floorLabel = "Ground floor"
    var monthlyRentText = ""
    var saleTotalText = ""
    var businessAskingPriceText = ""
    var depositText = ""
    var estimatedCAMNNNText = ""
    var featureIDs: Set<String> = []
    var description = ""
    var contactName = ""
    var contactPhone = ""
    var acceptsContactPublication = false

    var area: Double? { Double(areaText.replacingOccurrences(of: ",", with: "")) }
    var monthlyRent: Int? { Int(monthlyRentText.replacingOccurrences(of: ",", with: "")) }
    var saleTotal: Int? { Int(saleTotalText.replacingOccurrences(of: ",", with: "")) }
    var businessAskingPrice: Int? { Int(businessAskingPriceText.replacingOccurrences(of: ",", with: "")) }
    var deposit: Int? { Int(depositText.replacingOccurrences(of: ",", with: "")) }
    var estimatedCAMNNN: Int? { Int(estimatedCAMNNNText.replacingOccurrences(of: ",", with: "")) }

    func validationMessage(photoCount: Int) -> String? {
        if photoCount < 3 { return "Add at least 3 real photos" }
        if photoCount > 9 { return "Upload up to 9 photos" }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 6 {
            return "Add a title with at least 6 characters"
        }
        guard location != nil else { return "Confirm the store location" }
        if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            county.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add the city and local jurisdiction"
        }
        guard let area, (75 ... 250_000).contains(area) else {
            return "Enter an area from 75 to 250,000 sq ft"
        }
        if floorLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add the floor" }
        switch transactionType {
        case .rent:
            if monthlyRent == nil { return "Add the monthly rent" }
        case .businessSale:
            if monthlyRent == nil || businessAskingPrice == nil {
                return "Add monthly rent and the business asking price"
            }
        case .sale:
            if saleTotal == nil { return "Add the sale price" }
        }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
            return "Add at least 20 characters about the site and lease"
        }
        if contactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please enter the contact person’s name"
        }
        let digits = contactPhone.filter(\.isNumber)
        let nationalNumber = digits.count == 11 && digits.first == "1"
            ? String(digits.dropFirst())
            : digits
        if nationalNumber.range(
            of: #"^[2-9]\d{2}[2-9]\d{6}$"#,
            options: .regularExpression
        ) == nil {
            return "Please enter a valid U.S. phone number"
        }
        if !acceptsContactPublication { return "Confirm that contact info may be public" }
        return nil
    }
}

struct StorefrontDraftImage: Identifiable {
    let id = UUID()
    let data: Data
    let preview: UIImage
}

enum StorefrontFeatureOption {
    static let all: [(id: String, title: String, symbol: String)] = [
        ("street_front", "Street-facing", "eye.fill"),
        ("independent_entrance", "Private entrance", "door.left.hand.open"),
        ("water", "Water connected", "drop.fill"),
        ("drainage", "Drainage", "arrow.down.to.line.compact"),
        ("open_flame", "Open flame", "flame.fill"),
        ("three_phase_power", "Three-phase power", "bolt.fill"),
        ("outdoor_space", "Outdoor seating", "table.furniture.fill"),
        ("parking", "Parking", "parkingsign.circle.fill"),
        ("license_path_confirmed", "Permit path", "checkmark.seal.fill"),
    ]

    static func title(for identifier: String) -> String {
        all.first(where: { $0.id == identifier })?.title ?? identifier
    }
}

enum StorefrontServiceState: Equatable {
    case checking
    case ready
    case unavailable(String)
}

enum StorefrontAPIError: LocalizedError {
    case configuration
    case invalidResponse
    case server(String, String?)
    case transport

    var errorDescription: String? {
        switch self {
        case .configuration: "Premium Listing Service is not configured."
        case .invalidResponse: "The listing service returned an invalid response."
        case let .server(message, _):
            UserFacingCopy.externalMessage(message, fallback: "The listing service is temporarily unavailable.")
        case .transport: "Cannot connect to Store Finder service. Check your network and try again."
        }
    }

    var remediation: String? {
        if case let .server(_, remediation) = self { return remediation }
        return nil
    }
}

struct StorefrontAPIClient {
    func readiness() async -> StorefrontServiceState {
        do {
            let _: [String: String] = try await send(path: "api/v1/storefront/readyz", method: "GET")
            return .ready
        } catch {
            return .unavailable(
                UserFacingCopy.externalMessage(
                    (error as? LocalizedError)?.errorDescription,
                    fallback: "The listing service is temporarily unavailable."
                )
            )
        }
    }

    func listings(
        transactionType: StorefrontTransactionType?,
        counties: [String] = [],
        category: BusinessCategory? = nil,
        query: String? = nil,
        minimumPriceUSD: Int? = nil,
        maximumPriceUSD: Int? = nil,
        minimumAreaSquareFeet: Double? = nil,
        maximumAreaSquareFeet: Double? = nil,
        featureIDs: Set<String> = [],
        listingIDs: [String] = [],
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> StorefrontListingPage {
        var items = counties.map { URLQueryItem(name: "counties", value: $0) }
        items.append(contentsOf: featureIDs.sorted().map {
            URLQueryItem(name: "feature_ids", value: $0)
        })
        items.append(contentsOf: listingIDs.map {
            URLQueryItem(name: "listing_ids", value: $0)
        })
        items.append(contentsOf: [
            URLQueryItem(name: "transaction_type", value: transactionType?.rawValue),
            URLQueryItem(name: "category", value: category?.rawValue),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "minimum_price_usd", value: minimumPriceUSD.map { String($0) }),
            URLQueryItem(name: "maximum_price_usd", value: maximumPriceUSD.map { String($0) }),
            URLQueryItem(
                name: "minimum_area_square_feet",
                value: minimumAreaSquareFeet.map { String($0) }
            ),
            URLQueryItem(
                name: "maximum_area_square_feet",
                value: maximumAreaSquareFeet.map { String($0) }
            ),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try await send(path: "api/v1/storefront/listings", method: "GET", query: items)
    }

    func administrativeAreas() async throws -> [StorefrontAdministrativeArea] {
        try await send(
            path: "api/v1/storefront/administrative-areas",
            method: "GET"
        )
    }

    func listing(id: String) async throws -> StorefrontListing {
        try await send(path: "api/v1/storefront/listings/\(id)", method: "GET")
    }

    func uploadImage(_ data: Data, ownerToken: String) async throws -> StorefrontUploadedMedia {
        struct Payload: Codable { let dataURL: String }
        return try await send(
            path: "api/v1/storefront/media",
            method: "POST",
            headers: ["X-Storefront-Owner": ownerToken],
            body: Payload(dataURL: "data:image/jpeg;base64,\(data.base64EncodedString())"),
            timeout: 60
        )
    }

    func createListing(
        _ request: StorefrontListingCreateRequest,
        ownerToken: String
    ) async throws -> StorefrontListing {
        try await send(
            path: "api/v1/storefront/listings",
            method: "POST",
            headers: ["X-Storefront-Owner": ownerToken],
            body: request,
            timeout: 60
        )
    }

    func mine(ownerToken: String) async throws -> StorefrontListingPage {
        try await send(
            path: "api/v1/storefront/listings/mine",
            method: "GET",
            headers: ["X-Storefront-Owner": ownerToken]
        )
    }

    func archive(id: String, ownerToken: String) async throws {
        let _: Data = try await sendData(
            path: "api/v1/storefront/listings/\(id)",
            method: "DELETE",
            headers: ["X-Storefront-Owner": ownerToken]
        )
    }

    func startRecommendation(_ request: StorefrontRecommendationRequest) async throws -> StorefrontRecommendationJob {
        try await send(
            path: "api/v1/storefront/recommendation/jobs",
            method: "POST",
            body: request,
            timeout: 30
        )
    }

    func recommendation(id: String) async throws -> StorefrontRecommendationJob {
        try await send(path: "api/v1/storefront/recommendation/jobs/\(id)", method: "GET")
    }

    func imageURL(path: String) -> URL? {
        guard let baseURL = APIConfiguration.baseURL else { return nil }
        return baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        timeout: TimeInterval = 24
    ) async throws -> Response {
        let data = try await sendData(path: path, method: method, query: query, headers: headers, timeout: timeout)
        do {
            return try ReportCoding.decoder.decode(Response.self, from: data)
        } catch {
            #if DEBUG
            Logger(
                subsystem: "com.godicewang.EasyBusiness",
                category: "StorefrontAPI"
            ).error(
                "decode_failed response=\(String(describing: Response.self), privacy: .public) path=\(path, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            #endif
            throw StorefrontAPIError.invalidResponse
        }
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Body,
        timeout: TimeInterval = 24
    ) async throws -> Response {
        let data = try await sendData(
            path: path,
            method: method,
            query: query,
            headers: headers,
            bodyData: try ReportCoding.encoder.encode(body),
            timeout: timeout
        )
        do {
            return try ReportCoding.decoder.decode(Response.self, from: data)
        } catch {
            throw StorefrontAPIError.invalidResponse
        }
    }

    private func sendData(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        bodyData: Data? = nil,
        timeout: TimeInterval = 24
    ) async throws -> Data {
        guard let baseURL = APIConfiguration.baseURL else { throw StorefrontAPIError.configuration }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        let effectiveQuery = query.filter { $0.value?.isEmpty == false }
        if !effectiveQuery.isEmpty { components?.queryItems = effectiveQuery }
        guard let url = components?.url else { throw StorefrontAPIError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-ID")
        if bodyData != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw StorefrontAPIError.invalidResponse }
            guard (200 ..< 300).contains(response.statusCode) else {
                let failure = try? ReportCoding.decoder.decode(ServerFailureEnvelope.self, from: data)
                throw StorefrontAPIError.server(
                    failure?.detail?.message ?? "Premium Listing request failed (\(response.statusCode)).",
                    failure?.detail?.remediation
                )
            }
            return data
        } catch let error as StorefrontAPIError {
            throw error
        } catch {
            throw StorefrontAPIError.transport
        }
    }
}

struct StorefrontCredentialStore {
    private let service = "com.godicewang.EasyBusiness.storefront"
    private let account = "storefront-owner-token"

    func token() -> String {
        if let existing = load() { return existing }
        let value = "storefront-\(UUID().uuidString)-\(UUID().uuidString)"
        save(value)
        return value
    }

    private func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else { return nil }
        return value
    }

    private func save(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = match
            attributes.forEach { insert[$0.key] = $0.value }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }
}

@MainActor
@Observable
final class StorefrontStore {
    var serviceState: StorefrontServiceState = .checking
    var listings: [StorefrontListing] = []
    var totalListings = 0
    var selectedTransactionType: StorefrontTransactionType?
    var selectedCountys: [String] = []
    var selectedCategory: BusinessCategory?
    var minimumPriceUSD: Int?
    var maximumPriceUSD: Int?
    var minimumAreaSquareFeet: Double?
    var maximumAreaSquareFeet: Double?
    var selectedFeatureIDs: Set<String> = []
    var query = ""
    var isLoading = false
    var isLoadingMore = false
    var notice: String?
    var favoriteIDs: Set<String>
    var recommendationJob: StorefrontRecommendationJob?
    var publishProgress = 0.0
    var isPublishing = false

    private let api = StorefrontAPIClient()
    private let ownerToken: String
    private let defaults: UserDefaults
    private var browseRequestID = UUID()
    private static let browsePageSize = 30
    private static let favoritesKey = "easybusiness.us.storefront.favorites.v1"
    private static let draftKey = "easybusiness.us.storefront.publishDraft.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ownerToken = StorefrontCredentialStore().token()
        favoriteIDs = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
    }

    func bootstrap() async {
        serviceState = await api.readiness()
        guard serviceState == .ready else { return }
        await refresh()
    }

    func refresh() async {
        let requestID = UUID()
        browseRequestID = requestID
        isLoading = true
        defer {
            if browseRequestID == requestID {
                isLoading = false
            }
        }
        do {
            let page = try await api.listings(
                transactionType: selectedTransactionType,
                counties: selectedCountys,
                category: selectedCategory,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query,
                minimumPriceUSD: minimumPriceUSD,
                maximumPriceUSD: maximumPriceUSD,
                minimumAreaSquareFeet: minimumAreaSquareFeet,
                maximumAreaSquareFeet: maximumAreaSquareFeet,
                featureIDs: selectedFeatureIDs,
                limit: Self.browsePageSize,
                offset: 0
            )
            guard browseRequestID == requestID else { return }
            listings = page.items
            totalListings = page.total
            serviceState = .ready
        } catch {
            guard browseRequestID == requestID else { return }
            recordBrowseFailure(error)
        }
    }

    func recordBrowseFailure(_ error: Error) {
        listings = []
        totalListings = 0
        notice = nil
        serviceState = .unavailable(
            UserFacingCopy.externalMessage(
                (error as? LocalizedError)?.errorDescription,
                fallback: "The listing service is temporarily unavailable."
            )
        )
    }

    func loadMoreIfNeeded(currentListing: StorefrontListing? = nil) async {
        guard !isLoading,
              !isLoadingMore,
              listings.count < totalListings
        else { return }
        if let currentListing,
           let index = listings.firstIndex(where: { $0.id == currentListing.id }),
           index < max(0, listings.count - 5) {
            return
        }
        let requestID = browseRequestID
        let offset = listings.count
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.listings(
                transactionType: selectedTransactionType,
                counties: selectedCountys,
                category: selectedCategory,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query,
                minimumPriceUSD: minimumPriceUSD,
                maximumPriceUSD: maximumPriceUSD,
                minimumAreaSquareFeet: minimumAreaSquareFeet,
                maximumAreaSquareFeet: maximumAreaSquareFeet,
                featureIDs: selectedFeatureIDs,
                limit: Self.browsePageSize,
                offset: offset
            )
            guard browseRequestID == requestID else { return }
            let existing = Set(listings.map(\.id))
            listings.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            totalListings = page.total
        } catch {
            guard browseRequestID == requestID else { return }
            notice = (error as? LocalizedError)?.errorDescription ?? "Failed to load more listings."
        }
    }

    func select(_ type: StorefrontTransactionType?) async {
        selectedTransactionType = type
        await refresh()
    }

    func clearBrowseFilters() async {
        selectedCountys = []
        selectedCategory = nil
        minimumPriceUSD = nil
        maximumPriceUSD = nil
        minimumAreaSquareFeet = nil
        maximumAreaSquareFeet = nil
        selectedFeatureIDs = []
        await refresh()
    }

    func toggleFavorite(_ listing: StorefrontListing) {
        if favoriteIDs.contains(listing.id) { favoriteIDs.remove(listing.id) }
        else { favoriteIDs.insert(listing.id) }
        defaults.set(Array(favoriteIDs), forKey: Self.favoritesKey)
    }

    func startRecommendation(_ request: StorefrontRecommendationRequest) async {
        recommendationJob = nil
        do {
            var snapshot = try await api.startRecommendation(request)
            recommendationJob = snapshot
            while !["ready", "failed"].contains(snapshot.state) {
                try await Task.sleep(for: .seconds(1.2))
                try Task.checkCancellation()
                snapshot = try await api.recommendation(id: snapshot.id)
                recommendationJob = snapshot
            }
        } catch is CancellationError {
            return
        } catch {
            notice = (error as? LocalizedError)?.errorDescription ?? "Area recommendation incomplete."
        }
    }

    func publish(draft: StorefrontPublishDraft, images: [StorefrontDraftImage]) async -> Bool {
        guard draft.validationMessage(photoCount: images.count) == nil, let location = draft.location, let area = draft.area else {
            notice = draft.validationMessage(photoCount: images.count) ?? "Publication information is incomplete."
            return false
        }
        isPublishing = true
        publishProgress = 0.02
        defer { isPublishing = false }
        do {
            var photoIDs: [String] = []
            for (index, image) in images.enumerated() {
                let media = try await api.uploadImage(image.data, ownerToken: ownerToken)
                photoIDs.append(media.id)
                publishProgress = Double(index + 1) / Double(images.count + 1)
            }
            let request = StorefrontListingCreateRequest(
                transactionType: draft.transactionType,
                title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                currentBusiness: draft.currentBusiness.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                suitableCategoryIDs: draft.suitableCategoryIDs,
                placeName: location.name,
                address: location.address ?? "\(location.name), \(draft.city), \(draft.county)",
                city: draft.city.trimmingCharacters(in: .whitespacesAndNewlines),
                county: draft.county.trimmingCharacters(in: .whitespacesAndNewlines),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                coordinateReference: "wgs84",
                areaSquareFeet: area,
                floorLabel: draft.floorLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                monthlyRentUSD: draft.transactionType == .sale ? nil : draft.monthlyRent,
                saleTotalUSD: draft.transactionType == .sale ? draft.saleTotal : nil,
                businessAskingPriceUSD: draft.transactionType == .businessSale ? draft.businessAskingPrice : nil,
                depositUSD: draft.deposit,
                estimatedCAMNNNUSD: draft.estimatedCAMNNN,
                featureIDs: Array(draft.featureIDs),
                description: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                contactName: draft.contactName.trimmingCharacters(in: .whitespacesAndNewlines),
                contactPhone: draft.contactPhone,
                photoIDs: photoIDs,
                acceptsContactPublication: draft.acceptsContactPublication
            )
            _ = try await api.createListing(request, ownerToken: ownerToken)
            publishProgress = 1
            clearDraft()
            await refresh()
            return true
        } catch {
            let localized = error as? StorefrontAPIError
            notice = [localized?.errorDescription, localized?.remediation]
                .compactMap { $0 }
                .joined(separator: "\n")
            return false
        }
    }

    func loadDraft() -> StorefrontPublishDraft {
        guard
            let data = defaults.data(forKey: Self.draftKey),
            let draft = try? ReportCoding.decoder.decode(StorefrontPublishDraft.self, from: data)
        else { return StorefrontPublishDraft() }
        return draft
    }

    func saveDraft(_ draft: StorefrontPublishDraft) {
        if let data = try? ReportCoding.encoder.encode(draft) {
            defaults.set(data, forKey: Self.draftKey)
        }
    }

    func clearDraft() {
        defaults.removeObject(forKey: Self.draftKey)
    }

    func resolvedImageURL(_ path: String) -> URL? {
        api.imageURL(path: path)
    }

    func loadListings(ids: [String]) async -> [StorefrontListing] {
        (try? await fetchListings(ids: ids)) ?? []
    }

    func fetchListings(ids: [String]) async throws -> [StorefrontListing] {
        let orderedIDs = Array(NSOrderedSet(array: ids).array.compactMap { $0 as? String })
        guard !orderedIDs.isEmpty else { return [] }
        var loaded: [StorefrontListing] = []
        for start in stride(from: 0, to: orderedIDs.count, by: 60) {
            let end = min(start + 60, orderedIDs.count)
            let batch = Array(orderedIDs[start..<end])
            let page = try await api.listings(
                transactionType: nil,
                listingIDs: batch,
                limit: 60
            )
            loaded.append(contentsOf: page.items)
        }
        let byID = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        return orderedIDs.compactMap { byID[$0] }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct StorefrontDiscoveryView: View {
    @Environment(StorefrontStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsMap = false
    @State private var showsFilters = false

    var body: some View {
        @Bindable var store = store
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                quickActions
                recommendationEntry
                searchAndViewMode
                listingContent
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 112)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Storefronts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StorefrontMyListingsView()
                } label: {
                    Image(systemName: "tray.full.fill")
                }
                .accessibilityLabel("My Listings")
            }
        }
        .sheet(isPresented: $showsFilters) {
            StorefrontBrowseFilterSheet()
                .presentationDetents([.fraction(0.78), .large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if store.serviceState == .checking { await store.bootstrap() }
        }
        .refreshable { await store.refresh() }
        .alert(
            "Notice",
            isPresented: Binding(
                get: { store.notice != nil },
                set: { if !$0 { store.notice = nil } }
            )
        ) {
            Button("Got it") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        transactionQuickActions
                    }
                } else {
                    HStack(spacing: 10) {
                        transactionQuickActions
                    }
                }
            }
            NavigationLink {
                StorefrontPublishView()
            } label: {
                HStack(spacing: 12) {
                    FeatureIcon(symbol: "plus.circle.fill", tint: AppTheme.periwinkle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("List a Space")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text("Rent or sell")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.deepClay)
                }
                .appCard(contentPadding: 14)
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityIdentifier("storefront.publish")
        }
    }

    @ViewBuilder
    private var transactionQuickActions: some View {
        ForEach([StorefrontTransactionType.rent, .businessSale]) { type in
            Button {
                Task { await store.select(store.selectedTransactionType == type ? nil : type) }
            } label: {
                StorefrontQuickAction(
                    title: type.shortTitle,
                    symbol: type.symbol,
                    tint: type.tint,
                    isSelected: store.selectedTransactionType == type
                )
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityIdentifier("storefront.intent.\(type.rawValue)")
        }
    }

    private var activeFilterCount: Int {
        store.selectedCountys.count +
            (store.selectedCategory == nil ? 0 : 1) +
            (store.minimumPriceUSD == nil ? 0 : 1) +
            (store.maximumPriceUSD == nil ? 0 : 1) +
            (store.minimumAreaSquareFeet == nil ? 0 : 1) +
            (store.maximumAreaSquareFeet == nil ? 0 : 1) +
            store.selectedFeatureIDs.count
    }

    private var recommendationEntry: some View {
        NavigationLink {
            StorefrontRecommendationView()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.amber.opacity(0.13))
                    Image(systemName: "sparkles")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.deepClay)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find Areas")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text("Choose a category, budget, and market.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.deepClay)
            }
            .appCard(contentPadding: 15)
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityIdentifier("storefront.recommendation")
    }

    private var searchAndViewMode: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.deepClay)
                TextField("Search areas, streets, or features", text: Binding(
                    get: { store.query },
                    set: { store.query = $0 }
                ))
                .submitLabel(.search)
                .onSubmit { Task { await store.refresh() } }
                if !store.query.isEmpty {
                    Button {
                        store.query = ""
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.muted)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedTransactionType?.title ?? "All Listings")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(listingStatusText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button {
                    showsFilters = true
                } label: {
                    Label(
                        activeFilterCount == 0 ? "Filter" : "Filter \(activeFilterCount)",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.deepClay)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36)
                    .background(AppTheme.amber.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("storefront.filters")
                Picker("View Mode", selection: $showsMap) {
                    Label("List", systemImage: "list.bullet").tag(false)
                    Label("Map", systemImage: "map.fill").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 142)
            }
        }
    }

    private var listingStatusText: String {
        switch store.serviceState {
        case .checking:
            "Checking listing service"
        case .unavailable:
            "Listings unavailable"
        case .ready:
            store.totalListings == 0
                ? "No verified listings yet"
                : "\(store.totalListings) verified listings total"
        }
    }

    @ViewBuilder
    private var listingContent: some View {
        switch store.serviceState {
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("Connecting to listings")
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        case let .unavailable(message):
            ContentUnavailableView {
                Label("Listings Unavailable", systemImage: "storefront")
            } description: {
                Text(UserFacingCopy.externalMessage(message, fallback: "Check your connection and try again."))
            } actions: {
                Button("Reconnect") { Task { await store.bootstrap() } }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.deepClay)
            }
            .appCard(contentPadding: 8)
        case .ready:
            if store.isLoading && store.listings.isEmpty {
                ProgressView("Loading verified listings")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if store.listings.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "storefront")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.amber)
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No Matching Listings")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text("Adjust filters or post a verified listing.")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink {
                            StorefrontPublishView()
                        } label: {
                            Label("Post a Listing", systemImage: "arrow.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.deepClay)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 116)
                .appCard(contentPadding: 18)
            } else if showsMap {
                VStack(spacing: 12) {
                    StorefrontListingsMap(listings: store.listings)
                        .frame(height: 430)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        }
                    storefrontLoadMoreControl
                }
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(store.listings) { listing in
                        NavigationLink {
                            StorefrontDetailView(listing: listing)
                        } label: {
                            StorefrontListingCard(listing: listing)
                        }
                        .buttonStyle(PressFeedbackStyle())
                        .accessibilityIdentifier("storefront.listing.\(listing.id)")
                        .task {
                            await store.loadMoreIfNeeded(currentListing: listing)
                        }
                    }
                    storefrontLoadMoreControl
                }
            }
        }
    }

    @ViewBuilder
    private var storefrontLoadMoreControl: some View {
        if store.isLoadingMore {
            ProgressView("Loading more verified listings")
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 48)
        } else if store.listings.count < store.totalListings {
            Button {
                Task { await store.loadMoreIfNeeded() }
            } label: {
                Label(
                    "Continue viewing (\(store.listings.count) / \(store.totalListings))",
                    systemImage: "chevron.down.circle"
                )
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.deepClay)
            .accessibilityIdentifier("storefront.loadMore")
        }
    }
}

private struct StorefrontQuickAction: View {
    let title: String
    let symbol: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(isSelected ? .white : tint)
                .frame(width: 42, height: 42)
                .background(isSelected ? tint : tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            isSelected ? tint.opacity(0.08) : AppTheme.card,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? tint.opacity(0.38) : AppTheme.border, lineWidth: 1)
        }
    }
}

private struct StorefrontRemoteImage: View {
    @Environment(StorefrontStore.self) private var store
    let path: String?

    var body: some View {
        if let path, let url = store.resolvedImageURL(path) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut)) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder(symbol: "photo.badge.exclamationmark")
                default:
                    ZStack {
                        AppTheme.canvas
                        ProgressView()
                    }
                }
            }
        } else {
            placeholder(symbol: "photo")
        }
    }

    private func placeholder(symbol: String) -> some View {
        ZStack {
            LinearGradient(colors: [AppTheme.amber.opacity(0.12), AppTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(AppTheme.muted)
        }
    }
}

struct StorefrontListingCard: View {
    @Environment(StorefrontStore.self) private var store
    let listing: StorefrontListing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StorefrontRemoteImage(path: listing.photoURLs.first)
                .frame(height: 178)
                .clipped()
                .overlay(alignment: .topLeading) {
                    Text(listing.transactionType.shortTitle)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(listing.transactionType.tint, in: Capsule())
                        .padding(12)
                }
                .overlay(alignment: .topTrailing) {
                    Button {
                        store.toggleFavorite(listing)
                    } label: {
                        Image(systemName: store.favoriteIDs.contains(listing.id) ? "heart.fill" : "heart")
                            .foregroundStyle(store.favoriteIDs.contains(listing.id) ? Color.red : AppTheme.ink)
                            .frame(width: 42, height: 42)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(store.favoriteIDs.contains(listing.id) ? "Unsave" : "Save")
                    .padding(10)
                }
            VStack(alignment: .leading, spacing: 10) {
                Text(listing.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline) {
                    Text(listing.primaryPrice)
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.deepClay)
                    Spacer()
                    Text("\(listing.areaSquareFeet.formatted(.number.precision(.fractionLength(0...1)))) sq ft · \(listing.floorLabel)")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                }
                if let secondaryPrice = listing.secondaryPrice {
                    Text(secondaryPrice)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.amber)
                }
                Label("\(listing.city), \(listing.county) · \(listing.placeName)", systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(listing.featureIDs.prefix(4), id: \.self) { feature in
                            Text(StorefrontFeatureOption.title(for: feature))
                                .font(.caption2.bold())
                                .foregroundStyle(AppTheme.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(AppTheme.blue.opacity(0.08), in: Capsule())
                        }
                    }
                }
            }
            .padding(15)
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.border, lineWidth: 1)
        }
        .shadow(color: AppTheme.ink.opacity(0.05), radius: 12, y: 6)
    }
}

private struct StorefrontListingsMap: View {
    let listings: [StorefrontListing]
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $position, interactionModes: .all) {
            ForEach(listings) { listing in
                Annotation(listing.primaryPrice, coordinate: listing.coordinate) {
                    NavigationLink {
                        StorefrontDetailView(listing: listing)
                    } label: {
                        VStack(spacing: 3) {
                            Text(listing.primaryPrice)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(listing.transactionType.tint, in: Capsule())
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(listing.transactionType.tint)
                        }
                    }
                }
            }
        }
        .mapControls {
            MapCompass()
            MapScaleView()
        }
    }
}

struct StorefrontDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(StorefrontStore.self) private var store
    @Environment(CommunityStore.self) private var communityStore
    let listing: StorefrontListing
    @State private var selectedPhoto = 0
    @State private var nearby = StorefrontNearbyContext()
    @State private var showsContact = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                photoGallery
                overview
                facts
                features
                description
                mapAndNearby
                verificationNotice
            }
            .padding(.bottom, 110)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Listing Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFavorite(listing) } label: {
                    Image(systemName: store.favoriteIDs.contains(listing.id) ? "heart.fill" : "heart")
                        .foregroundStyle(store.favoriteIDs.contains(listing.id) ? Color.red : AppTheme.deepClay)
                }
                .accessibilityLabel(store.favoriteIDs.contains(listing.id) ? "Unsave" : "Save")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showsContact = true
            } label: {
                PrimaryActionLabel(title: "Contact Poster", systemImage: "phone.fill")
            }
            .buttonStyle(PressFeedbackStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial)
        }
        .task {
            await nearby.load(around: listing.coordinate)
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await communityStore.recordCreditEvent(
                kind: "storefront_detail_viewed",
                eventID: listing.id
            )
        }
        .sheet(isPresented: $showsContact) {
            StorefrontContactSheet(listing: listing)
                .presentationDetents([.height(320)])
        }
    }

    private var photoGallery: some View {
        TabView(selection: $selectedPhoto) {
            ForEach(Array(listing.photoURLs.enumerated()), id: \.offset) { index, path in
                StorefrontRemoteImage(path: path)
                    .tag(index)
                    .accessibilityIdentifier("storefront.detail.photo.\(index)")
                    .accessibilityLabel("Store photo \(index + 1) of \(listing.photoURLs.count)")
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 310)
        .overlay(alignment: .topLeading) {
            Text(listing.transactionType.shortTitle)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(listing.transactionType.tint, in: Capsule())
                .padding(16)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(listing.primaryPrice)
                    .font(.title.bold())
                    .foregroundStyle(AppTheme.deepClay)
                Spacer()
                if let secondaryPrice = listing.secondaryPrice {
                    Text(secondaryPrice)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.amber)
                }
            }
            Text(listing.title)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.ink)
            Label("\(listing.city), \(listing.county) · \(listing.placeName)", systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 20)
    }

    private var facts: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    fact(
                        "\(listing.areaSquareFeet.formatted(.number.precision(.fractionLength(0...1)))) sq ft",
                        "Floor area"
                    )
                    Divider()
                    fact(listing.floorLabel, "Floor")
                    Divider()
                    fact(listing.currentBusiness ?? "Pending verification", "Current use")
                }
            } else {
                HStack(spacing: 0) {
                    fact(
                        "\(listing.areaSquareFeet.formatted(.number.precision(.fractionLength(0...1)))) sq ft",
                        "Floor area"
                    )
                    Divider().frame(height: 42)
                    fact(listing.floorLabel, "Floor")
                    Divider().frame(height: 42)
                    fact(listing.currentBusiness ?? "Pending verification", "Current use")
                }
            }
        }
        .appCard(contentPadding: 16)
        .padding(.horizontal, 20)
    }

    private func fact(_ value: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var features: some View {
        if !listing.featureIDs.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Operating Conditions", caption: "Provided by the poster. Verify each item before signing.")
                LazyVGrid(
                    columns: dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(listing.featureIDs, id: \.self) { value in
                        Label(StorefrontFeatureOption.title(for: value), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.mint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(11)
                            .background(AppTheme.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .appCard(contentPadding: 16)
            .padding(.horizontal, 20)
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Unit Description", caption: "Poster’s Original Text")
            Text(listing.description)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(5)
        }
        .appCard(contentPadding: 16)
        .padding(.horizontal, 20)
    }

    private var mapAndNearby: some View {
        VStack(alignment: .leading, spacing: 13) {
            SectionTitle("Location & Surroundings", caption: "Drag to move · Pinch to zoom")
            Map(
                initialPosition: .region(
                    MKCoordinateRegion(
                        center: listing.coordinate,
                        latitudinalMeters: 1_600,
                        longitudinalMeters: 1_600
                    )
                ),
                interactionModes: .all
            ) {
                Marker(listing.placeName, coordinate: listing.coordinate)
                    .tint(AppTheme.deepClay)
            }
            .frame(height: 250)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text(listing.address)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            if nearby.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching nearby transit, trade areas, schools, and offices")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            } else if nearby.groups.isEmpty {
                Text(nearby.message ?? "Apple Maps didn’t return verifiable nearby facilities.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            } else {
                VStack(spacing: 10) {
                    ForEach(nearby.groups) { group in
                        HStack(alignment: .top, spacing: 10) {
                            FeatureIcon(symbol: group.symbol, tint: group.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(AppTheme.ink)
                                Text(group.names.joined(separator: ","))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(3)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .appCard(contentPadding: 16)
        .padding(.horizontal, 20)
    }

    private var verificationNotice: some View {
        InlineStatusCard(
            title: "On-site verification required before signing",
            detail: "Listings combine publisher details with Apple Maps. Independently verify ownership or leasing authority, permitted use, fire and ventilation requirements, lease charges, and any business-transfer terms.",
            tint: AppTheme.amber,
            symbol: "checkmark.shield.fill"
        )
        .padding(.horizontal, 20)
    }
}

@MainActor
@Observable
private final class StorefrontNearbyContext {
    var groups: [StorefrontNearbyGroup] = []
    var isLoading = false
    var message: String?

    func load(around coordinate: CLLocationCoordinate2D) async {
        guard !isLoading, groups.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        let definitions: [(String, String, Color)] = [
            ("Transit Station", "tram.fill", AppTheme.blue),
            ("Shopping Mall", "bag.fill", AppTheme.amber),
            ("Schools", "graduationcap.fill", AppTheme.periwinkle),
            ("Office Building", "building.2.fill", AppTheme.mint),
        ]
        var loaded: [StorefrontNearbyGroup] = []
        for definition in definitions {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = definition.0
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 2_000,
                longitudinalMeters: 2_000
            )
            do {
                let response = try await MKLocalSearch(request: request).start()
                let names = response.mapItems
                    .filter {
                        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                            .distance(from: CLLocation(
                                latitude: $0.placemark.coordinate.latitude,
                                longitude: $0.placemark.coordinate.longitude
                            )) <= 1_500
                    }
                    .map(\.name)
                    .compactMap { $0 }
                    .reduce(into: [String]()) { result, value in
                        if !result.contains(value) { result.append(value) }
                    }
                if !names.isEmpty {
                    loaded.append(
                        StorefrontNearbyGroup(
                            title: definition.0,
                            symbol: definition.1,
                            tint: definition.2,
                            names: Array(names.prefix(4))
                        )
                    )
                }
            } catch {
                continue
            }
        }
        groups = loaded
        if loaded.isEmpty { message = "Apple Maps didn’t return verifiable nearby facilities. View the map directly or verify on site." }
    }
}

private struct StorefrontNearbyGroup: Identifiable {
    let title: String
    let symbol: String
    let tint: Color
    let names: [String]
    var id: String { title }
}

private struct StorefrontContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    let listing: StorefrontListing

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule()
                .fill(AppTheme.border)
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
            Text("Contact Poster")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.ink)
            VStack(alignment: .leading, spacing: 7) {
                Text(listing.contactName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(listing.contactPhone)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.deepClay)
                Text("The poster shared this number. EasyBusiness has not verified identity, ownership, or lease authority.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = listing.contactPhone
                } label: {
                    Label("Copy Number", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.deepClay)
                if let url = URL(string: "tel://\(listing.contactPhone)") {
                    Link(destination: url) {
                        Label("Call", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.deepClay)
                }
            }
            Spacer()
        }
        .padding(20)
        .background(AppBackdrop(accent: AppTheme.amber))
    }
}

struct StorefrontPublishView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(StorefrontStore.self) private var store
    @State private var draft = StorefrontPublishDraft()
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var images: [StorefrontDraftImage] = []
    @State private var showsCategoryPicker = false
    @State private var showsExitPrompt = false
    @State private var showsPublished = false
    @State private var hasLoadedDraft = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                publishHero
                transactionCard
                photoCard
                locationCard
                basicsCard
                priceCard
                featuresCard
                contactCard
                publishBoundary
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 122)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Post a Listing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { requestExit() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Back")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 7) {
                if let message = draft.validationMessage(photoCount: images.count) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Button {
                    Task {
                        if await store.publish(draft: draft, images: images) {
                            showsPublished = true
                        }
                    }
                } label: {
                    if store.isPublishing {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Posting \(Int(store.publishProgress * 100))%")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(AppTheme.deepClay, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        PrimaryActionLabel(title: "Post Listing", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(PressFeedbackStyle())
                .disabled(store.isPublishing || draft.validationMessage(photoCount: images.count) != nil)
                .opacity(draft.validationMessage(photoCount: images.count) == nil ? 1 : 0.48)
                .accessibilityIdentifier("storefront.publish.submit")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showsCategoryPicker) {
            NavigationStack {
                StorefrontCategoryPicker(
                    title: "Suitable Business Categories",
                    allowsMultiple: true,
                    selections: $draft.suitableCategoryIDs
                )
            }
        }
        .onAppear {
            guard !hasLoadedDraft else { return }
            draft = store.loadDraft()
            hasLoadedDraft = true
        }
        .onChange(of: photoItems) { _, values in
            Task { await loadPhotos(values) }
        }
        .confirmationDialog(
            "Leave Posting Page?",
            isPresented: $showsExitPrompt,
            titleVisibility: .visible
        ) {
            Button("Save Text Draft & Exit") {
                store.saveDraft(draft)
                dismiss()
            }
            Button("Discard This Entry", role: .destructive) {
                store.clearDraft()
                dismiss()
            }
            Button("Continue Editing", role: .cancel) {}
        } message: {
            Text("Location and text will be saved. Reselect photos after returning.")
        }
        .alert("Listing Posted", isPresented: $showsPublished) {
            Button("Done") { dismiss() }
        } message: {
            Text("Your listing is live with the contact details you approved. Remove it if conditions change.")
        }
    }

    private var publishHero: some View {
        HStack(spacing: 14) {
            FeatureIcon(symbol: "checkmark.shield.fill", tint: AppTheme.mint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Verify Every Detail")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("Confirm the site, price, photos, contact, permitted use, and licenses.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .appCard(contentPadding: 15)
    }

    private var transactionCard: some View {
        StorefrontFormCard(title: "Listing Type", caption: "Choose one") {
            HStack(spacing: 9) {
                ForEach(StorefrontTransactionType.allCases) { type in
                    Button {
                        draft.transactionType = type
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: type.symbol)
                            Text(type.shortTitle)
                                .font(.caption.bold())
                        }
                        .foregroundStyle(draft.transactionType == type ? Color.white : type.tint)
                        .frame(maxWidth: .infinity, minHeight: 62)
                        .background(
                            draft.transactionType == type ? type.tint : type.tint.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                    }
                    .buttonStyle(PressFeedbackStyle())
                }
            }
        }
    }

    private var photoCard: some View {
        StorefrontFormCard(title: "Real Photos", caption: "\(images.count) / 9 (at least 3)") {
            Text("Add storefront, interior, and entrance photos. Avoid faces, plates, and IDs.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(images.enumerated()), id: \.element.id) { index, value in
                            Image(uiImage: value.preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 108, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        images.remove(at: index)
                                        if index < photoItems.count { photoItems.remove(at: index) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.65))
                                    }
                                    .padding(5)
                                    .accessibilityLabel("Delete Photo \(index + 1)")
                                }
                        }
                    }
                }
            }
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 9,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Label(images.isEmpty ? "Add Photos" : "Edit Photos", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.deepClay)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AppTheme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityIdentifier("storefront.publish.photos")
        }
    }

    private var locationCard: some View {
        StorefrontFormCard(title: "Store Location", caption: "Confirm with Apple Maps") {
            NavigationLink {
                LocationPickerView { location in
                    acceptLocation(location)
                }
            } label: {
                HStack(spacing: 12) {
                    FeatureIcon(symbol: "map.fill", tint: AppTheme.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.location == nil ? "Choose Location" : "Location Verified")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(draft.location.map {
                            [$0.name, $0.conciseAddress].compactMap { $0 }.joined(separator: " · ")
                        } ?? "Search or tap a site on the map")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(12)
                .background(AppTheme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)
            StorefrontTextField(label: "City", placeholder: "Auto-filled; verify", text: $draft.city)
            StorefrontTextField(label: "County or Equivalent", placeholder: "County, parish, borough, or city", text: $draft.county)
        }
    }

    private var basicsCard: some View {
        StorefrontFormCard(title: "Site Details", caption: "Help prospects decide whether to visit") {
            StorefrontTextField(label: "Title", placeholder: "Street-facing unit with private entrance", text: $draft.title)
            StorefrontTextField(label: "Current business", placeholder: "Enter “Vacant” if unoccupied", text: $draft.currentBusiness)
            StorefrontTextField(label: "Area (sq ft)", placeholder: "sq ft", text: $draft.areaText, keyboard: .decimalPad)
            StorefrontTextField(label: "Floor", placeholder: "e.g., 1st floor, floors 1–2", text: $draft.floorLabel)
            Button { showsCategoryPicker = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suitable Categories")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.muted)
                        Text(draft.suitableCategoryIDs.isEmpty
                             ? "Choose all that fit"
                             : draft.suitableCategoryIDs.map(\.title).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(draft.suitableCategoryIDs.isEmpty ? AppTheme.muted : AppTheme.ink)
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(12)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var priceCard: some View {
        StorefrontFormCard(title: "Price & lease terms", caption: "All amounts in USD") {
            if draft.transactionType != .sale {
                StorefrontTextField(label: "Monthly Rent", placeholder: "USD / month", text: $draft.monthlyRentText, keyboard: .numberPad)
                StorefrontTextField(label: "Security deposit (optional)", placeholder: "USD", text: $draft.depositText, keyboard: .numberPad)
                StorefrontTextField(label: "Monthly CAM / NNN (Optional)", placeholder: "USD", text: $draft.estimatedCAMNNNText, keyboard: .numberPad)
            }
            if draft.transactionType == .businessSale {
                StorefrontTextField(label: "Business Asking Price", placeholder: "USD", text: $draft.businessAskingPriceText, keyboard: .numberPad)
            }
            if draft.transactionType == .sale {
                StorefrontTextField(label: "Total sale price", placeholder: "USD", text: $draft.saleTotalText, keyboard: .numberPad)
            }
            Text("List rent, deposit, CAM/NNN, key money, and equipment separately.")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var featuresCard: some View {
        StorefrontFormCard(title: "Operating Conditions", caption: "Choose only verified features") {
            LazyVGrid(
                columns: dynamicTypeSize.isAccessibilitySize
                    ? [GridItem(.flexible())]
                    : [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 9
            ) {
                ForEach(StorefrontFeatureOption.all, id: \.id) { option in
                    Button {
                        if draft.featureIDs.contains(option.id) { draft.featureIDs.remove(option.id) }
                        else { draft.featureIDs.insert(option.id) }
                    } label: {
                        Label(
                            option.title,
                            systemImage: draft.featureIDs.contains(option.id) ? "checkmark.circle.fill" : option.symbol
                        )
                        .font(.caption.bold())
                        .foregroundStyle(draft.featureIDs.contains(option.id) ? AppTheme.mint : AppTheme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                        .padding(.horizontal, 10)
                        .background(
                            draft.featureIDs.contains(option.id) ? AppTheme.mint.opacity(0.08) : AppTheme.canvas,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Site & lease description")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.muted)
                TextField(
                    "Describe assets, lease term, approvals, rent changes, CAM/NNN, restrictions, and handover.",
                    text: $draft.description,
                    axis: .vertical
                )
                .lineLimit(5 ... 9)
                .padding(12)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }

    private var contactCard: some View {
        StorefrontFormCard(title: "Contact", caption: "Name and phone only") {
            StorefrontTextField(label: "Name", placeholder: "Enter the real contact person’s name", text: $draft.contactName)
            StorefrontTextField(label: "Phone number", placeholder: "(555) 123-4567", text: $draft.contactPhone, keyboard: .phonePad)
            Toggle(isOn: $draft.acceptsContactPublication) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Publish Contact Info")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text("Prospects can view and call from the detail page; info is hidden after delisting.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .tint(AppTheme.deepClay)
        }
    }

    private var publishBoundary: some View {
        InlineStatusCard(
            title: "Keep the Listing Accurate",
            detail: "Disclose ownership, use limits, and current pricing. Remove the listing when details change.",
            tint: AppTheme.periwinkle,
            symbol: "person.badge.shield.checkmark.fill"
        )
    }

    private func acceptLocation(_ location: LocationCandidate) {
        draft.location = location
        let hint = location.administrativeAreaHint
        if let city = hint.city { draft.city = city }
        Task {
            let coordinate = location.coordinate.clLocationCoordinate
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ).first,
            draft.location?.id == location.id else { return }
            draft.city = placemark.locality ?? draft.city
            draft.county = placemark.subAdministrativeArea ?? draft.county
        }
    }

    private func requestExit() {
        let hasContent = !draft.title.isEmpty || draft.location != nil || !draft.description.isEmpty || !images.isEmpty
        if hasContent { showsExitPrompt = true }
        else { dismiss() }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [StorefrontDraftImage] = []
        for item in items.prefix(9) {
            guard
                let raw = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: raw),
                let prepared = image.storefrontUploadData(),
                let preview = UIImage(data: prepared)
            else { continue }
            loaded.append(StorefrontDraftImage(data: prepared, preview: preview))
        }
        images = loaded
    }
}

private struct StorefrontFormCard<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }
            content()
        }
        .appCard(contentPadding: 16)
    }
}

private struct StorefrontTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.muted)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .padding(.horizontal, 12)
                .frame(minHeight: 46)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
    }
}

private extension UIImage {
    func storefrontUploadData() -> Data? {
        let maximumDimension: CGFloat = 2_000
        let scale = min(1, maximumDimension / max(size.width, size.height))
        let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let prepared = renderer.image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: target))
            draw(in: CGRect(origin: .zero, size: target))
        }
        return prepared.jpegData(compressionQuality: 0.82)
    }
}

private struct StorefrontCategoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let allowsMultiple: Bool
    @Binding var selections: [BusinessCategory]
    @State private var selectedSector: BusinessSector?
    @State private var search = ""

    private var matchingCategories: [BusinessCategory] {
        let base = selectedSector?.categories ?? BusinessCategory.selectableCases
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(term) ||
                $0.suggestedSubcategories.contains(where: { $0.localizedCaseInsensitiveContains(term) })
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.deepClay)
                    TextField("Search business categories", text: $search)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 48)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            selectedSector = nil
                        } label: {
                            Text("All")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedSector == nil ? AppTheme.deepClay : AppTheme.card, in: Capsule())
                                .foregroundStyle(selectedSector == nil ? .white : AppTheme.ink)
                        }
                        ForEach(BusinessSector.allCases) { sector in
                            Button {
                                selectedSector = sector
                            } label: {
                                Label(sector.title, systemImage: sector.symbol)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedSector == sector ? AppTheme.deepClay : AppTheme.card, in: Capsule())
                                    .foregroundStyle(selectedSector == sector ? .white : AppTheme.ink)
                            }
                        }
                    }
                }

                LazyVGrid(
                    columns: dynamicTypeSize.isAccessibilitySize
                        ? [GridItem(.flexible())]
                        : [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    ForEach(matchingCategories) { category in
                        Button {
                            if allowsMultiple {
                                if selections.contains(category) { selections.removeAll { $0 == category } }
                                else if selections.count < 8 { selections.append(category) }
                            } else {
                                selections = [category]
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: category.symbol)
                                    .foregroundStyle(selections.contains(category) ? .white : AppTheme.deepClay)
                                Text(category.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if selections.contains(category) {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .foregroundStyle(selections.contains(category) ? .white : AppTheme.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                selections.contains(category) ? AppTheme.deepClay : AppTheme.card,
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                            )
                        }
                        .buttonStyle(PressFeedbackStyle())
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 80)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsMultiple {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct StorefrontAdministrativeCascade: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onSelect: (String) -> Void

    @State private var states: [StorefrontAdministrativeArea] = []
    @State private var selectedState: StorefrontAdministrativeArea?
    @State private var cityOrMetro = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) {
                        stateMenu
                        marketTextField
                    }
                } else {
                    HStack(spacing: 8) {
                        stateMenu
                            .frame(width: 132)
                        marketTextField
                    }
                }
            }
            if isLoading {
                Label("Loading U.S. jurisdictions...", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            } else if let errorMessage {
                Button {
                    Task { await loadStates() }
                } label: {
                    Label(errorMessage, systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(AppTheme.deepClay)
                }
                .buttonStyle(.plain)
            }
            Button {
                guard let value = selectedMarketName else { return }
                onSelect(value)
            } label: {
                Label("Add this market", systemImage: "plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.deepClay)
            .disabled(selectedMarketName == nil)
            .accessibilityIdentifier("storefront.administrative.add")
            Text("Enter a city or metro area. Apple Maps verifies it.")
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .task {
            if states.isEmpty { await loadStates() }
        }
    }

    private var stateMenu: some View {
        Menu {
            ForEach(states) { value in
                Button("\(value.name) (\(value.code))") {
                    selectedState = value
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("State or territory")
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.muted)
                HStack(spacing: 4) {
                    Text(selectedState?.code ?? "Select")
                        .font(.caption.bold())
                        .foregroundStyle(selectedState == nil ? AppTheme.muted : AppTheme.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("State or territory: \(selectedState?.name ?? "not selected")")
    }

    private var marketTextField: some View {
        TextField("City or metro area", text: $cityOrMetro)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                AppTheme.canvas,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .accessibilityLabel("City or metro area")
    }

    private var selectedMarketName: String? {
        guard let selectedState else { return nil }
        let city = cityOrMetro.trimmingCharacters(in: .whitespacesAndNewlines)
        guard city.count >= 2 else { return nil }
        return "\(city), \(selectedState.code)"
    }

    private func loadStates() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            states = try await StorefrontAPIClient().administrativeAreas()
        } catch {
            errorMessage = "U.S. markets unavailable. Tap to retry."
        }
    }
}

private struct StorefrontBrowseFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StorefrontStore.self) private var store

    @State private var transactionType: StorefrontTransactionType?
    @State private var selectedCategory: BusinessCategory?
    @State private var counties: [String] = []
    @State private var minimumPrice = ""
    @State private var maximumPrice = ""
    @State private var minimumArea = ""
    @State private var maximumArea = ""
    @State private var featureIDs: Set<String> = []
    @State private var showsCategoryPicker = false
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text("Filter Listings")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button("Reset") { reset() }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.deepClay)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    filterSection("Transaction Type") {
                        HStack(spacing: 8) {
                            filterChoice("All", selected: transactionType == nil) {
                                transactionType = nil
                            }
                            ForEach(StorefrontTransactionType.allCases) { type in
                                filterChoice(type.filterTitle, selected: transactionType == type) {
                                    transactionType = type
                                }
                            }
                        }
                    }

                    filterSection("Market Area") {
                        if !counties.isEmpty {
                            StorefrontChipFlow(values: counties) { value in
                                counties.removeAll { $0 == value }
                            }
                        }
                        StorefrontAdministrativeCascade { value in
                            guard counties.count < 5, !counties.contains(value) else { return }
                            counties.append(value)
                        }
                    }

                    filterSection("Price & Area") {
                        Text(priceCaption)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        HStack(spacing: 9) {
                            rangeField("Min Price", text: $minimumPrice, keyboard: .numberPad)
                            Text("—").foregroundStyle(AppTheme.muted)
                            rangeField("Max Price", text: $maximumPrice, keyboard: .numberPad)
                        }
                        Text("Store Area (sq ft)")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        HStack(spacing: 9) {
                            rangeField("Min Area", text: $minimumArea, keyboard: .decimalPad)
                            Text("—").foregroundStyle(AppTheme.muted)
                            rangeField("Max Area", text: $maximumArea, keyboard: .decimalPad)
                        }
                    }

                    filterSection("Operating Conditions") {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                            spacing: 8
                        ) {
                            ForEach(StorefrontFeatureOption.all, id: \.id) { option in
                                Button {
                                    if featureIDs.contains(option.id) { featureIDs.remove(option.id) }
                                    else { featureIDs.insert(option.id) }
                                } label: {
                                    Label(option.title, systemImage: option.symbol)
                                        .font(.caption.bold())
                                        .foregroundStyle(
                                            featureIDs.contains(option.id) ? .white : AppTheme.ink
                                        )
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(
                                            featureIDs.contains(option.id)
                                                ? AppTheme.deepClay
                                                : AppTheme.canvas,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    filterSection("Business Category") {
                        Button { showsCategoryPicker = true } label: {
                            HStack {
                                Label(
                                    selectedCategory?.title ?? "All Categories",
                                    systemImage: selectedCategory?.symbol ?? "square.grid.2x2.fill"
                                )
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .padding(12)
                            .background(
                                AppTheme.canvas,
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }

            Button {
                apply()
            } label: {
                PrimaryActionLabel(title: "View Listings", systemImage: "line.3.horizontal.decrease")
            }
            .buttonStyle(PressFeedbackStyle())
            .disabled(!rangesAreValid)
            .opacity(rangesAreValid ? 1 : 0.48)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("storefront.filters.apply")
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .onAppear { loadCurrentFiltersOnce() }
        .sheet(isPresented: $showsCategoryPicker) {
            NavigationStack {
                StorefrontCategoryPicker(
                    title: "Filter by Business Category",
                    allowsMultiple: false,
                    selections: Binding(
                        get: { selectedCategory.map { [$0] } ?? [] },
                        set: { selectedCategory = $0.first }
                    )
                )
            }
        }
    }

    private var priceCaption: String {
        switch transactionType {
        case .rent: "Monthly Rent (USD)"
        case .businessSale: "Business Price (USD)"
        case .sale: "Property Price (USD)"
        case nil: "Price Range (USD)"
        }
    }

    private var rangesAreValid: Bool {
        let lowPrice = Int(minimumPrice.replacingOccurrences(of: ",", with: ""))
        let highPrice = Int(maximumPrice.replacingOccurrences(of: ",", with: ""))
        let lowArea = Double(minimumArea.replacingOccurrences(of: ",", with: ""))
        let highArea = Double(maximumArea.replacingOccurrences(of: ",", with: ""))
        let priceInputValid = minimumPrice.isEmpty || lowPrice != nil
        let maxPriceInputValid = maximumPrice.isEmpty || highPrice != nil
        let areaInputValid = minimumArea.isEmpty || lowArea != nil
        let maxAreaInputValid = maximumArea.isEmpty || highArea != nil
        return priceInputValid && maxPriceInputValid && areaInputValid && maxAreaInputValid &&
            (lowPrice == nil || highPrice == nil || lowPrice! <= highPrice!) &&
            (lowArea == nil || highArea == nil || lowArea! <= highArea!)
    }

    private func filterSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            content()
        }
    }

    private func filterChoice(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(selected ? .white : AppTheme.ink)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(
                    selected ? AppTheme.deepClay : AppTheme.canvas,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func rangeField(
        _ placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .font(.subheadline)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func loadCurrentFiltersOnce() {
        guard !didLoad else { return }
        didLoad = true
        transactionType = store.selectedTransactionType
        selectedCategory = store.selectedCategory
        counties = store.selectedCountys
        minimumPrice = store.minimumPriceUSD.map(String.init) ?? ""
        maximumPrice = store.maximumPriceUSD.map(String.init) ?? ""
        minimumArea = store.minimumAreaSquareFeet.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        maximumArea = store.maximumAreaSquareFeet.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        featureIDs = store.selectedFeatureIDs
    }

    private func reset() {
        transactionType = nil
        selectedCategory = nil
        counties = []
        minimumPrice = ""
        maximumPrice = ""
        minimumArea = ""
        maximumArea = ""
        featureIDs = []
    }

    private func apply() {
        guard rangesAreValid else { return }
        store.selectedTransactionType = transactionType
        store.selectedCategory = selectedCategory
        store.selectedCountys = counties
        store.minimumPriceUSD = Int(minimumPrice.replacingOccurrences(of: ",", with: ""))
        store.maximumPriceUSD = Int(maximumPrice.replacingOccurrences(of: ",", with: ""))
        store.minimumAreaSquareFeet = Double(minimumArea.replacingOccurrences(of: ",", with: ""))
        store.maximumAreaSquareFeet = Double(maximumArea.replacingOccurrences(of: ",", with: ""))
        store.selectedFeatureIDs = featureIDs
        Task {
            await store.refresh()
            dismiss()
        }
    }
}

struct StorefrontRecommendationView: View {
    @Environment(StorefrontStore.self) private var store
    @Environment(CommunityStore.self) private var communityStore
    @State private var selectedCategories: [BusinessCategory] = []
    @State private var subcategory = ""
    @State private var budgetText = ""
    @State private var counties: [String] = []
    @State private var showsCategoryPicker = false
    @State private var isAuthorizingSpend = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                intro
                conditions
                if let job = store.recommendationJob {
                    recommendationState(job)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Find Sites by Area")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsCategoryPicker) {
            NavigationStack {
                StorefrontCategoryPicker(
                    title: "Select Business Category",
                    allowsMultiple: false,
                    selections: $selectedCategories
                )
            }
        }
        .alert(
            "Area Recommendation Incomplete",
            isPresented: Binding(
                get: { store.notice != nil },
                set: { if !$0 { store.notice = nil } }
            )
        ) {
            Button("Got it") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text("Up to 3 areas")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.82))
            }
            Text("Find Promising Areas")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("Uses Apple Maps–verified landmarks to focus your search.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(
            LinearGradient(colors: [AppTheme.deepClay, AppTheme.amber], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
    }

    private var conditions: some View {
        StorefrontFormCard(title: "Search Criteria", caption: "Add 1–5 markets") {
            Button { showsCategoryPicker = true } label: {
                HStack(spacing: 12) {
                    FeatureIcon(symbol: selectedCategories.first?.symbol ?? "square.grid.2x2.fill", tint: AppTheme.deepClay)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Business Category")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.muted)
                        Text(selectedCategories.first?.title ?? "Please select")
                            .font(.subheadline.bold())
                            .foregroundStyle(selectedCategories.isEmpty ? AppTheme.muted : AppTheme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.muted)
                }
                .padding(11)
                .background(AppTheme.canvas, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            StorefrontTextField(label: "Concept Details (Optional)", placeholder: "e.g., breakfast or specialty coffee", text: $subcategory)
            StorefrontTextField(label: "Investment Budget", placeholder: "USD, min 50,000", text: $budgetText, keyboard: .numberPad)

            VStack(alignment: .leading, spacing: 8) {
                Text("Target Markets")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.muted)
                if !counties.isEmpty {
                    StorefrontChipFlow(values: counties) { value in
                        counties.removeAll { $0 == value }
                    }
                }
                StorefrontAdministrativeCascade { value in
                    guard counties.count < 5, !counties.contains(value) else { return }
                    counties.append(value)
                }
                Text("Apple Maps verifies each market and its local jurisdiction.")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }

            Button {
                startRecommendation()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.magnifyingglass")
                    Text("Find Recommended Areas")
                    Spacer()
                    Label("3", systemImage: "circle.hexagongrid.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                    Image(systemName: "arrow.right")
                }
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(.horizontal, 18)
                .background(
                    LinearGradient(
                        colors: [AppTheme.deepClay, AppTheme.amber],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .buttonStyle(PressFeedbackStyle())
            .disabled(!canStart || isRunning || isAuthorizingSpend)
            .opacity(canStart && !isRunning && !isAuthorizingSpend ? 1 : 0.48)
            .accessibilityIdentifier("storefront.recommendation.start")
        }
    }

    @ViewBuilder
    private func recommendationState(_ job: StorefrontRecommendationJob) -> some View {
        if job.state == "ready", let result = job.result {
            recommendationResult(result)
        } else if job.state == "failed" {
            InlineStatusCard(
                title: UserFacingCopy.externalMessage(job.error?.message, fallback: "No Recommendations Yet"),
                detail: UserFacingCopy.externalMessage(
                    job.error?.remediation,
                    fallback: "Check the markets, network, and service status, then try again."
                ),
                tint: AppTheme.amber,
                symbol: "exclamationmark.triangle.fill"
            )
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.stage)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text(job.detail)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    Text("\(job.progressPercent)%")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(AppTheme.deepClay)
                }
                ProgressView(value: Double(job.progressPercent), total: 100)
                    .tint(AppTheme.deepClay)
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Usually takes about 40–90 seconds; the task continues even if you leave this page.")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .appCard(contentPadding: 17)
        }
    }

    private func recommendationResult(_ result: StorefrontRecommendationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Recommended Site Areas", caption: "\(result.areas.count) items")
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.ink)
                    .lineSpacing(4)
            }
            .appCard(contentPadding: 16)

            Map(
                initialPosition: .automatic,
                interactionModes: .all
            ) {
                ForEach(result.areas) { area in
                    Marker(area.name, coordinate: area.coordinate)
                        .tint(AppTheme.deepClay)
                    MapCircle(center: area.coordinate, radius: CLLocationDistance(area.radiusMeters))
                        .foregroundStyle(AppTheme.amber.opacity(0.12))
                        .stroke(AppTheme.deepClay.opacity(0.5), lineWidth: 1.5)
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            }

            ForEach(Array(result.areas.enumerated()), id: \.element.id) { index, area in
                StorefrontRecommendedAreaCard(index: index + 1, area: area)
            }

            if !result.sources.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(result.sources) { source in
                            if let url = URL(string: source.url) {
                                Link(destination: url) {
                                    HStack(alignment: .top, spacing: 9) {
                                        Image(systemName: "arrow.up.right.square")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(source.title)
                                                .font(.caption.bold())
                                                .foregroundStyle(AppTheme.ink)
                                                .lineLimit(2)
                                            Text(source.publisher ?? url.host ?? "Public Web Pages")
                                                .font(.caption2)
                                                .foregroundStyle(AppTheme.muted)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                } label: {
                    Label("\(result.sources.count) public data sources", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.deepClay)
                }
                .appCard(contentPadding: 16)
            }
        }
    }

    private var canStart: Bool {
        selectedCategories.count == 1 &&
            (Int(budgetText.replacingOccurrences(of: ",", with: "")) ?? 0) >= 50_000 &&
            !counties.isEmpty
    }

    private var isRunning: Bool {
        guard let state = store.recommendationJob?.state else { return false }
        return state == "queued" || state == "running"
    }

    private func startRecommendation() {
        guard
            let category = selectedCategories.first,
            let budget = Int(budgetText.replacingOccurrences(of: ",", with: ""))
        else { return }
        guard !isAuthorizingSpend else { return }
        isAuthorizingSpend = true
        Task {
            defer { isAuthorizingSpend = false }
            guard let reservation = await communityStore.reserveCreditUsage(
                .storefrontRecommendation
            ) else {
                return
            }
            await store.startRecommendation(
                StorefrontRecommendationRequest(
                    category: category,
                    subcategory: subcategory.trimmingCharacters(in: .whitespacesAndNewlines),
                    investmentBudgetUSD: budget,
                    counties: counties
                )
            )
            if store.recommendationJob?.state == "ready" {
                await communityStore.settleCreditUsage(reservation)
            } else {
                await communityStore.refundCreditUsage(reservation)
            }
        }
    }
}

private struct StorefrontChipFlow: View {
    let values: [String]
    let remove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button { remove(value) } label: {
                        HStack(spacing: 6) {
                            Text(value)
                            Image(systemName: "xmark")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.deepClay)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.amber.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(value)")
                }
            }
        }
    }
}

private struct StorefrontRecommendedAreaCard: View {
    let index: Int
    let area: StorefrontRecommendedArea

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.deepClay, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(area.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("\(area.county) · Suggested radius \(area.radiusMiles.formatted(.number.precision(.fractionLength(1)))) mi")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
            }
            Text(area.headline)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.deepClay)
            Text(area.reason)
                .font(.subheadline)
                .foregroundStyle(AppTheme.ink)
                .lineSpacing(4)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(area.fitNotes, id: \.self) { note in
                    Label(note, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mint)
                }
                Label(area.caution, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.amber)
            }
            if !area.contextHighlights.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(area.contextHighlights, id: \.self) { value in
                            Label(value, systemImage: "map.fill")
                                .font(.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("What the map verified")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.deepClay)
                }
            }
            NavigationLink {
                StorefrontMatchedListingsView(area: area)
            } label: {
                HStack {
                    Text(area.matchedListingIDs.isEmpty ? "View area (no listed sites available)" : "View \(area.matchedListingIDs.count) matching sites")
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(AppTheme.deepClay)
                .padding(12)
                .background(AppTheme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .appCard(contentPadding: 16)
    }
}

private struct StorefrontMatchedListingsView: View {
    @Environment(StorefrontStore.self) private var store
    let area: StorefrontRecommendedArea
    @State private var listings: [StorefrontListing] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(area.name)
                        .font(.title2.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text("\(area.radiusMiles.formatted(.number.precision(.fractionLength(1)))) mi radius · Verified active listings within budget")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                if isLoading {
                    ProgressView("Verifying listing status")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Area Listings Unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Reload") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 8)
                } else if listings.isEmpty {
                    ContentUnavailableView(
                        "No matching sites in this area",
                        systemImage: "storefront",
                        description: Text("Use the area guidance for field checks. Unverified listings are never added.")
                    )
                    .appCard(contentPadding: 8)
                } else {
                    ForEach(listings) { listing in
                        NavigationLink {
                            StorefrontDetailView(listing: listing)
                        } label: {
                            StorefrontListingCard(listing: listing)
                        }
                        .buttonStyle(PressFeedbackStyle())
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 90)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("Area sites")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            listings = try await store.fetchListings(ids: area.matchedListingIDs)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? "Cannot connect to Store Finder service. Check your network and try again."
        }
        isLoading = false
    }
}

struct StorefrontMyListingsView: View {
    @Environment(StorefrontStore.self) private var store
    @State private var listings: [StorefrontListing] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if isLoading {
                    ProgressView("Loading my listings")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("My Listings Unavailable", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("Reload") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 8)
                } else if listings.isEmpty {
                    ContentUnavailableView {
                        Label("No sites listed yet", systemImage: "tray")
                    } description: {
                        Text("After listing, you can view and remove them here.")
                    } actions: {
                        NavigationLink("Post a Listing") { StorefrontPublishView() }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 8)
                } else {
                    ForEach(listings) { listing in
                        VStack(spacing: 10) {
                            NavigationLink {
                                StorefrontDetailView(listing: listing)
                            } label: {
                                StorefrontListingCard(listing: listing)
                            }
                            .buttonStyle(PressFeedbackStyle())
                            Button(role: .destructive) {
                                archive(listing)
                            } label: {
                                Label("Listing expired. Remove it?", systemImage: "archivebox.fill")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(18)
            .padding(.bottom, 90)
        }
        .background(AppBackdrop(accent: AppTheme.amber))
        .navigationTitle("My Listings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        do {
            let page = try await StorefrontAPIClient()
                .mine(ownerToken: StorefrontCredentialStore().token())
            listings = page.items
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription
                ?? "Cannot connect to Store Finder service. Check your network and try again."
        }
    }

    private func archive(_ listing: StorefrontListing) {
        Task {
            do {
                try await StorefrontAPIClient().archive(
                    id: listing.id,
                    ownerToken: StorefrontCredentialStore().token()
                )
                await load()
                await store.refresh()
            } catch {
                store.notice = (error as? LocalizedError)?.errorDescription ?? "Removal failed."
            }
        }
    }
}
