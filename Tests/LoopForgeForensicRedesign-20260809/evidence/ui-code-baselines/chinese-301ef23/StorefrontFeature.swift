import MapKit
import Observation
import OSLog
import PhotosUI
import Security
import SwiftUI
import UIKit

enum StorefrontTransactionType: String, Codable, CaseIterable, Identifiable {
    case rent
    case transfer
    case sale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rent: "租商铺"
        case .transfer: "买商铺"
        case .sale: "商铺出售"
        }
    }

    var shortTitle: String {
        switch self {
        case .rent: "出租"
        case .transfer: "转店"
        case .sale: "出售"
        }
    }

    var detail: String {
        switch self {
        case .rent: "房东直租或新铺招租"
        case .transfer: "接手现有装修与设备"
        case .sale: "购买商铺产权"
        }
    }

    var symbol: String {
        switch self {
        case .rent: "key.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        case .sale: "building.2.crop.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .rent: AppTheme.blue
        case .transfer: AppTheme.amber
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
    let district: String
    let latitude: Double
    let longitude: Double
    let coordinateReference: String
    let areaSquareMeters: Double
    let floorLabel: String
    let monthlyRentYuan: Int?
    let saleTotalYuan: Int?
    let transferFeeYuan: Int?
    let depositYuan: Int?
    let propertyFeeYuan: Int?
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
        case district
        case latitude
        case longitude
        case coordinateReference
        case areaSquareMeters
        case floorLabel
        case monthlyRentYuan
        case saleTotalYuan
        case transferFeeYuan
        case depositYuan
        case propertyFeeYuan
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
            monthlyRentYuan.map { "¥\($0.formatted()) / 月" } ?? "租金面议"
        case .transfer:
            transferFeeYuan.map { "转让费 ¥\($0.formatted())" } ?? "转让费面议"
        case .sale:
            saleTotalYuan.map { "¥\(Double($0 / 10_000).formatted(.number.precision(.fractionLength(0...1)))) 万" } ?? "售价面议"
        }
    }

    var secondaryPrice: String? {
        guard transactionType == .transfer, let monthlyRentYuan else { return nil }
        return "月租 ¥\(monthlyRentYuan.formatted())"
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
    let district: String
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
    let investmentBudgetYuan: Int
    let districts: [String]
}

struct StorefrontAdministrativeArea: Codable, Identifiable, Equatable {
    let name: String
    let adcode: String
    let level: String

    var id: String { "\(level)-\(adcode)" }
}

struct StorefrontListingCreateRequest: Codable {
    let transactionType: StorefrontTransactionType
    let title: String
    let currentBusiness: String?
    let suitableCategoryIDs: [BusinessCategory]
    let placeName: String
    let address: String
    let city: String
    let district: String
    let latitude: Double
    let longitude: Double
    let coordinateReference: String
    let areaSquareMeters: Double
    let floorLabel: String
    let monthlyRentYuan: Int?
    let saleTotalYuan: Int?
    let transferFeeYuan: Int?
    let depositYuan: Int?
    let propertyFeeYuan: Int?
    let featureIDs: [String]
    let description: String
    let contactName: String
    let contactPhone: String
    let photoIDs: [String]
    let acceptsContactPublication: Bool
}

struct StorefrontPublishDraft: Codable, Equatable {
    var transactionType: StorefrontTransactionType = .rent
    var title = ""
    var currentBusiness = ""
    var suitableCategoryIDs: [BusinessCategory] = []
    var location: LocationCandidate?
    var city = ""
    var district = ""
    var areaText = ""
    var floorLabel = "一层"
    var monthlyRentText = ""
    var saleTotalText = ""
    var transferFeeText = ""
    var depositText = ""
    var propertyFeeText = ""
    var featureIDs: Set<String> = []
    var description = ""
    var contactName = ""
    var contactPhone = ""
    var acceptsContactPublication = false

    var area: Double? { Double(areaText.replacingOccurrences(of: ",", with: "")) }
    var monthlyRent: Int? { Int(monthlyRentText.replacingOccurrences(of: ",", with: "")) }
    var saleTotal: Int? { Int(saleTotalText.replacingOccurrences(of: ",", with: "")) }
    var transferFee: Int? { Int(transferFeeText.replacingOccurrences(of: ",", with: "")) }
    var deposit: Int? { Int(depositText.replacingOccurrences(of: ",", with: "")) }
    var propertyFee: Int? { Int(propertyFeeText.replacingOccurrences(of: ",", with: "")) }

    func validationMessage(photoCount: Int) -> String? {
        if photoCount < 3 { return "请上传至少 3 张真实店铺照片" }
        if photoCount > 9 { return "最多上传 9 张照片" }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).count < 6 {
            return "请用至少 6 个字说明铺位特点"
        }
        guard location != nil else { return "请在地图上确认店铺位置" }
        if city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            district.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请补充店铺所在城市和区县"
        }
        guard let area, (5 ... 50_000).contains(area) else { return "请填写 5–50,000 ㎡的店铺面积" }
        if floorLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写店铺楼层" }
        switch transactionType {
        case .rent:
            if monthlyRent == nil { return "出租铺源需要填写月租" }
        case .transfer:
            if monthlyRent == nil || transferFee == nil { return "转店铺源需要填写月租和转让费" }
        case .sale:
            if saleTotal == nil { return "出售铺源需要填写总售价" }
        }
        if description.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
            return "请用至少 20 个字说明铺位现状与租约条件"
        }
        if contactName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
            return "请填写联系人姓名"
        }
        let phone = contactPhone.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        if phone.range(of: #"^(?:\+?86)?1[3-9]\d{9}$"#, options: .regularExpression) == nil {
            return "请填写有效的中国内地手机号"
        }
        if !acceptsContactPublication { return "请确认公开联系人姓名和电话" }
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
        ("street_front", "临街展示", "eye.fill"),
        ("independent_entrance", "独立入口", "door.left.hand.open"),
        ("water", "已通上水", "drop.fill"),
        ("drainage", "已通下水", "arrow.down.to.line.compact"),
        ("open_flame", "可做明火", "flame.fill"),
        ("three_phase_power", "三相电", "bolt.fill"),
        ("outdoor_space", "可做外摆", "table.furniture.fill"),
        ("parking", "停车方便", "parkingsign.circle.fill"),
        ("license_transferable", "证照可协商", "checkmark.seal.fill"),
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
        case .configuration: "旺铺服务尚未配置。"
        case .invalidResponse: "旺铺服务返回了无法识别的数据。"
        case let .server(message, _): message
        case .transport: "无法连接旺铺服务，请检查网络后重试。"
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
            return .unavailable((error as? LocalizedError)?.errorDescription ?? "旺铺服务暂不可用。")
        }
    }

    func listings(
        transactionType: StorefrontTransactionType?,
        districts: [String] = [],
        category: BusinessCategory? = nil,
        query: String? = nil,
        minimumPriceYuan: Int? = nil,
        maximumPriceYuan: Int? = nil,
        minimumAreaSquareMeters: Double? = nil,
        maximumAreaSquareMeters: Double? = nil,
        featureIDs: Set<String> = [],
        listingIDs: [String] = [],
        limit: Int = 30,
        offset: Int = 0
    ) async throws -> StorefrontListingPage {
        var items = districts.map { URLQueryItem(name: "districts", value: $0) }
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
            URLQueryItem(name: "minimum_price_yuan", value: minimumPriceYuan.map { String($0) }),
            URLQueryItem(name: "maximum_price_yuan", value: maximumPriceYuan.map { String($0) }),
            URLQueryItem(
                name: "minimum_area_square_meters",
                value: minimumAreaSquareMeters.map { String($0) }
            ),
            URLQueryItem(
                name: "maximum_area_square_meters",
                value: maximumAreaSquareMeters.map { String($0) }
            ),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return try await send(path: "api/v1/storefront/listings", method: "GET", query: items)
    }

    func administrativeAreas(parent: String = "中国") async throws -> [StorefrontAdministrativeArea] {
        try await send(
            path: "api/v1/storefront/administrative-areas",
            method: "GET",
            query: [URLQueryItem(name: "parent", value: parent)]
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
                    failure?.detail?.message ?? "旺铺请求失败（\(response.statusCode)）。",
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
    var selectedDistricts: [String] = []
    var selectedCategory: BusinessCategory?
    var minimumPriceYuan: Int?
    var maximumPriceYuan: Int?
    var minimumAreaSquareMeters: Double?
    var maximumAreaSquareMeters: Double?
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
    private static let favoritesKey = "easybusiness.storefront.favorites.v1"
    private static let draftKey = "easybusiness.storefront.publishDraft.v1"

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
                districts: selectedDistricts,
                category: selectedCategory,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query,
                minimumPriceYuan: minimumPriceYuan,
                maximumPriceYuan: maximumPriceYuan,
                minimumAreaSquareMeters: minimumAreaSquareMeters,
                maximumAreaSquareMeters: maximumAreaSquareMeters,
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
            notice = (error as? LocalizedError)?.errorDescription ?? "铺源加载失败。"
        }
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
                districts: selectedDistricts,
                category: selectedCategory,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query,
                minimumPriceYuan: minimumPriceYuan,
                maximumPriceYuan: maximumPriceYuan,
                minimumAreaSquareMeters: minimumAreaSquareMeters,
                maximumAreaSquareMeters: maximumAreaSquareMeters,
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
            notice = (error as? LocalizedError)?.errorDescription ?? "更多铺源加载失败。"
        }
    }

    func select(_ type: StorefrontTransactionType?) async {
        selectedTransactionType = type
        await refresh()
    }

    func clearBrowseFilters() async {
        selectedDistricts = []
        selectedCategory = nil
        minimumPriceYuan = nil
        maximumPriceYuan = nil
        minimumAreaSquareMeters = nil
        maximumAreaSquareMeters = nil
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
            notice = (error as? LocalizedError)?.errorDescription ?? "区域推荐未完成。"
        }
    }

    func publish(draft: StorefrontPublishDraft, images: [StorefrontDraftImage]) async -> Bool {
        guard draft.validationMessage(photoCount: images.count) == nil, let location = draft.location, let area = draft.area else {
            notice = draft.validationMessage(photoCount: images.count) ?? "发布信息不完整。"
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
                address: location.address ?? draft.city + draft.district + location.name,
                city: draft.city.trimmingCharacters(in: .whitespacesAndNewlines),
                district: draft.district.trimmingCharacters(in: .whitespacesAndNewlines),
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                coordinateReference: "wgs84",
                areaSquareMeters: area,
                floorLabel: draft.floorLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                monthlyRentYuan: draft.transactionType == .sale ? nil : draft.monthlyRent,
                saleTotalYuan: draft.transactionType == .sale ? draft.saleTotal : nil,
                transferFeeYuan: draft.transactionType == .transfer ? draft.transferFee : nil,
                depositYuan: draft.deposit,
                propertyFeeYuan: draft.propertyFee,
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
        .navigationTitle("找旺铺")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    StorefrontMyListingsView()
                } label: {
                    Image(systemName: "tray.full.fill")
                }
                .accessibilityLabel("我的发布")
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
            "提示",
            isPresented: Binding(
                get: { store.notice != nil },
                set: { if !$0 { store.notice = nil } }
            )
        ) {
            Button("知道了") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach([StorefrontTransactionType.rent, .transfer]) { type in
                    Button {
                        Task { await store.select(store.selectedTransactionType == type ? nil : type) }
                    } label: {
                        StorefrontQuickAction(
                            title: type.title,
                            symbol: type.symbol,
                            tint: type.tint,
                            isSelected: store.selectedTransactionType == type
                        )
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .accessibilityIdentifier("storefront.intent.\(type.rawValue)")
                }
            }
            NavigationLink {
                StorefrontPublishView()
            } label: {
                HStack(spacing: 12) {
                    FeatureIcon(symbol: "plus.circle.fill", tint: AppTheme.periwinkle)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("发布铺源")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text("出租、转让或出售，统一从这里发布")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
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

    private var activeFilterCount: Int {
        store.selectedDistricts.count +
            (store.selectedCategory == nil ? 0 : 1) +
            (store.minimumPriceYuan == nil ? 0 : 1) +
            (store.maximumPriceYuan == nil ? 0 : 1) +
            (store.minimumAreaSquareMeters == nil ? 0 : 1) +
            (store.maximumAreaSquareMeters == nil ? 0 : 1) +
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
                    Text("小易帮你挑区域")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("选品类、预算和区县，最多给出 3 个找铺范围")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
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
                TextField("搜商圈、街道或铺位特点", text: Binding(
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
                    .accessibilityLabel("清除搜索")
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
                    Text(store.selectedTransactionType?.title ?? "全部铺源")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(store.totalListings == 0 ? "等待真实铺源发布" : "共 \(store.totalListings) 条真实发布")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Button {
                    showsFilters = true
                } label: {
                    Label(
                        activeFilterCount == 0 ? "筛选" : "筛选 \(activeFilterCount)",
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
                Picker("展示方式", selection: $showsMap) {
                    Label("列表", systemImage: "list.bullet").tag(false)
                    Label("地图", systemImage: "map.fill").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 142)
            }
        }
    }

    @ViewBuilder
    private var listingContent: some View {
        switch store.serviceState {
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("正在连接旺铺服务")
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        case let .unavailable(message):
            ContentUnavailableView {
                Label("旺铺服务暂不可用", systemImage: "storefront")
            } description: {
                Text(message)
            } actions: {
                Button("重新连接") { Task { await store.bootstrap() } }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.deepClay)
            }
            .appCard(contentPadding: 8)
        case .ready:
            if store.isLoading && store.listings.isEmpty {
                ProgressView("正在加载真实铺源")
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if store.listings.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "storefront")
                        .font(.system(size: 28))
                        .foregroundStyle(AppTheme.amber)
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前条件下还没有铺源")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text("可调整筛选，或发布已确认位置、照片和联系方式的真实铺源。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        NavigationLink {
                            StorefrontPublishView()
                        } label: {
                            Label("发布第一条铺源", systemImage: "arrow.right")
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
            ProgressView("正在加载更多真实铺源")
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 48)
        } else if store.listings.count < store.totalListings {
            Button {
                Task { await store.loadMoreIfNeeded() }
            } label: {
                Label(
                    "继续查看（\(store.listings.count) / \(store.totalListings)）",
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
                    .accessibilityLabel(store.favoriteIDs.contains(listing.id) ? "取消收藏" : "收藏")
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
                    Text("\(listing.areaSquareMeters.formatted(.number.precision(.fractionLength(0...1))))㎡ · \(listing.floorLabel)")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                }
                if let secondaryPrice = listing.secondaryPrice {
                    Text(secondaryPrice)
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.amber)
                }
                Label("\(listing.district) · \(listing.placeName)", systemImage: "mappin.and.ellipse")
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
        .navigationTitle("铺源详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFavorite(listing) } label: {
                    Image(systemName: store.favoriteIDs.contains(listing.id) ? "heart.fill" : "heart")
                        .foregroundStyle(store.favoriteIDs.contains(listing.id) ? Color.red : AppTheme.deepClay)
                }
                .accessibilityLabel(store.favoriteIDs.contains(listing.id) ? "取消收藏" : "收藏")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showsContact = true
            } label: {
                PrimaryActionLabel(title: "联系发布者", systemImage: "phone.fill")
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
            await communityStore.recordFortuneEvent(
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
                    .accessibilityLabel("店铺图片 \(index + 1)，共 \(listing.photoURLs.count) 张")
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
            Label("\(listing.city)\(listing.district) · \(listing.placeName)", systemImage: "mappin.and.ellipse")
                .font(.subheadline)
                .foregroundStyle(AppTheme.muted)
        }
        .padding(.horizontal, 20)
    }

    private var facts: some View {
        HStack(spacing: 0) {
            fact("\(listing.areaSquareMeters.formatted(.number.precision(.fractionLength(0...1))))㎡", "建筑面积")
            Divider().frame(height: 42)
            fact(listing.floorLabel, "所在楼层")
            Divider().frame(height: 42)
            fact(listing.currentBusiness ?? "待核验", "当前业态")
        }
        .appCard(contentPadding: 16)
        .padding(.horizontal, 20)
    }

    private func fact(_ value: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.bold())
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                SectionTitle("经营条件", caption: "来自发布者填写，签约前逐项核实")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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
            SectionTitle("铺位说明", caption: "发布者原文")
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
            SectionTitle("位置与周边", caption: "真实地图可拖动、缩放")
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
                    Text("正在查询附近交通、商圈、学校和办公设施")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            } else if nearby.groups.isEmpty {
                Text(nearby.message ?? "系统地图暂未返回可核验的附近设施。")
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
                                Text(group.names.joined(separator: "、"))
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
            title: "签约前必须现场核验",
            detail: "平台展示的是用户发布信息和系统地图查询，不代表产权、消防、证照、租约或客流已经核验。请核对房本、出租权、用途、明火排烟、欠费和转让清单。",
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
            ("地铁站", "tram.fill", AppTheme.blue),
            ("商场", "bag.fill", AppTheme.amber),
            ("学校", "graduationcap.fill", AppTheme.periwinkle),
            ("写字楼", "building.2.fill", AppTheme.mint),
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
        if loaded.isEmpty { message = "系统地图当前没有返回可核验的附近设施，请直接查看地图或现场核对。" }
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
            Text("联系发布者")
                .font(.title2.bold())
                .foregroundStyle(AppTheme.ink)
            VStack(alignment: .leading, spacing: 7) {
                Text(listing.contactName)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(listing.contactPhone)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(AppTheme.deepClay)
                Text("电话由发布者主动公开，平台尚未完成产权、租约与号码实名核验。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = listing.contactPhone
                } label: {
                    Label("复制号码", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.deepClay)
                if let url = URL(string: "tel://\(listing.contactPhone)") {
                    Link(destination: url) {
                        Label("拨打电话", systemImage: "phone.fill")
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
        .navigationTitle("发布铺源")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { requestExit() } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("返回")
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
                            Text("正在发布 \(Int(store.publishProgress * 100))%")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(AppTheme.deepClay, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        PrimaryActionLabel(title: "确认并发布", systemImage: "paperplane.fill")
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
                    title: "适合经营的品类",
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
            "离开发布页面？",
            isPresented: $showsExitPrompt,
            titleVisibility: .visible
        ) {
            Button("保存文字草稿并退出") {
                store.saveDraft(draft)
                dismiss()
            }
            Button("放弃本次填写", role: .destructive) {
                store.clearDraft()
                dismiss()
            }
            Button("继续填写", role: .cancel) {}
        } message: {
            Text("位置和文字可以保存；为保护照片隐私，退出后需要重新选择照片。")
        }
        .alert("铺源已发布", isPresented: $showsPublished) {
            Button("完成") { dismiss() }
        } message: {
            Text("铺源已经进入平台列表。联系方式会按你的授权展示，条件变化后请及时下架。")
        }
    }

    private var publishHero: some View {
        HStack(spacing: 14) {
            FeatureIcon(symbol: "checkmark.shield.fill", tint: AppTheme.mint)
            VStack(alignment: .leading, spacing: 4) {
                Text("真实信息，比漂亮文案更重要")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text("确认位置、价格、照片和联系人；产权与经营许可仍由双方线下核验。")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .appCard(contentPadding: 15)
    }

    private var transactionCard: some View {
        StorefrontFormCard(title: "你要发布什么", caption: "先明确交易方式") {
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
        StorefrontFormCard(title: "真实照片", caption: "\(images.count) / 9，至少 3 张") {
            Text("建议依次上传门头、室内全景和临街/入口视角；请勿上传无权公开的人脸、车牌或证件。")
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
                                    .accessibilityLabel("删除第 \(index + 1) 张照片")
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
                Label(images.isEmpty ? "选择店铺照片" : "调整照片", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppTheme.deepClay)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AppTheme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityIdentifier("storefront.publish.photos")
        }
    }

    private var locationCard: some View {
        StorefrontFormCard(title: "店铺位置", caption: "以你在地图确认的点位为准") {
            NavigationLink {
                LocationPickerView { location in
                    acceptLocation(location)
                }
            } label: {
                HStack(spacing: 12) {
                    FeatureIcon(symbol: "map.fill", tint: AppTheme.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.location == nil ? "在地图上确认位置" : "已确认真实位置")
                            .font(.subheadline.bold())
                            .foregroundStyle(AppTheme.ink)
                        Text(draft.location.map {
                            [$0.name, $0.conciseAddress].compactMap { $0 }.joined(separator: " · ")
                        } ?? "支持搜索、点按地图和双指缩放")
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
            StorefrontTextField(label: "城市", placeholder: "由地图带入，可核对", text: $draft.city)
            StorefrontTextField(label: "区 / 县", placeholder: "由地图带入，可核对", text: $draft.district)
        }
    }

    private var basicsCard: some View {
        StorefrontFormCard(title: "铺位信息", caption: "让找铺的人快速判断是否值得看") {
            StorefrontTextField(label: "标题", placeholder: "例如临街、独立入口、适合什么业态", text: $draft.title)
            StorefrontTextField(label: "当前经营", placeholder: "空铺可填写“空铺”", text: $draft.currentBusiness)
            StorefrontTextField(label: "面积", placeholder: "平方米", text: $draft.areaText, keyboard: .decimalPad)
            StorefrontTextField(label: "楼层", placeholder: "例如一层、1-2层", text: $draft.floorLabel)
            Button { showsCategoryPicker = true } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("适合经营品类")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.muted)
                        Text(draft.suitableCategoryIDs.isEmpty
                             ? "可多选，帮助找铺者筛选"
                             : draft.suitableCategoryIDs.map(\.title).joined(separator: "、"))
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
        StorefrontFormCard(title: "价格与租约", caption: "金额均为人民币") {
            if draft.transactionType != .sale {
                StorefrontTextField(label: "月租", placeholder: "元 / 月", text: $draft.monthlyRentText, keyboard: .numberPad)
                StorefrontTextField(label: "押金（可选）", placeholder: "元", text: $draft.depositText, keyboard: .numberPad)
                StorefrontTextField(label: "每月物业费（可选）", placeholder: "元", text: $draft.propertyFeeText, keyboard: .numberPad)
            }
            if draft.transactionType == .transfer {
                StorefrontTextField(label: "转让费", placeholder: "元", text: $draft.transferFeeText, keyboard: .numberPad)
            }
            if draft.transactionType == .sale {
                StorefrontTextField(label: "出售总价", placeholder: "元", text: $draft.saleTotalText, keyboard: .numberPad)
            }
            Text("不要把押金、物业费或设备费藏进其他金额；合同口径与付款节奏请在说明里写清楚。")
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var featuresCard: some View {
        StorefrontFormCard(title: "经营条件", caption: "只勾选你能现场证明的") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
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
                Text("铺位与租约说明")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.muted)
                TextField(
                    "写清装修设备、剩余租期、递增、物业限制、交付时间，以及需要对方现场核验的事项",
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
        StorefrontFormCard(title: "联系人", caption: "平台只保留姓名和电话") {
            StorefrontTextField(label: "姓名", placeholder: "请填写真实联系人姓名", text: $draft.contactName)
            StorefrontTextField(label: "手机号", placeholder: "中国内地手机号", text: $draft.contactPhone, keyboard: .phonePad)
            Toggle(isOn: $draft.acceptsContactPublication) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("同意公开姓名与电话")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.ink)
                    Text("找铺者可在详情页查看并拨打；下架后不再公开。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .tint(AppTheme.deepClay)
        }
    }

    private var publishBoundary: some View {
        InlineStatusCard(
            title: "发布者对信息真实性负责",
            detail: "禁止冒用他人铺源、隐瞒产权或经营限制、发布已失效价格。平台会保留必要的安全审计记录，并支持后续下架。",
            tint: AppTheme.periwinkle,
            symbol: "person.badge.shield.checkmark.fill"
        )
    }

    private func acceptLocation(_ location: LocationCandidate) {
        draft.location = location
        let hint = location.administrativeAreaHint
        if let city = hint.city { draft.city = city }
        if let district = hint.district { draft.district = district }
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
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
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
                    TextField("搜索经营品类", text: $search)
                }
                .padding(.horizontal, 13)
                .frame(minHeight: 48)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            selectedSector = nil
                        } label: {
                            Text("全部")
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

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if selections.contains(category) {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .foregroundStyle(selections.contains(category) ? .white : AppTheme.ink)
                            .padding(.horizontal, 12)
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
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

private struct StorefrontAdministrativeCascade: View {
    let onSelect: (String) -> Void

    @State private var provinces: [StorefrontAdministrativeArea] = []
    @State private var cities: [StorefrontAdministrativeArea] = []
    @State private var districts: [StorefrontAdministrativeArea] = []
    @State private var province: StorefrontAdministrativeArea?
    @State private var city: StorefrontAdministrativeArea?
    @State private var district: StorefrontAdministrativeArea?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                areaMenu(title: "省", selection: province, values: provinces) { value in
                    Task { await chooseProvince(value) }
                }
                areaMenu(title: "市", selection: city, values: cities) { value in
                    Task { await chooseCity(value) }
                }
                .disabled(province == nil || cities.isEmpty)
                areaMenu(title: "区 / 县", selection: district, values: districts) { value in
                    district = value
                }
                .disabled(city == nil || districts.isEmpty)
            }
            if isLoading {
                Label("正在加载当前行政区", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            } else if let errorMessage {
                Button {
                    Task { await loadProvinces() }
                } label: {
                    Label(errorMessage, systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(AppTheme.deepClay)
                }
                .buttonStyle(.plain)
            }
            Button {
                guard let value = selectedQueryName else { return }
                onSelect(value)
            } label: {
                Label("加入这个区县", systemImage: "plus")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)
            .tint(AppTheme.deepClay)
            .disabled(selectedQueryName == nil)
            .accessibilityIdentifier("storefront.administrative.add")
        }
        .task {
            if provinces.isEmpty { await loadProvinces() }
        }
    }

    private func areaMenu(
        title: String,
        selection: StorefrontAdministrativeArea?,
        values: [StorefrontAdministrativeArea],
        choose: @escaping (StorefrontAdministrativeArea) -> Void
    ) -> some View {
        Menu {
            ForEach(values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { value in
                Button(value.name) { choose(value) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(AppTheme.muted)
                HStack(spacing: 4) {
                    Text(selection?.name ?? "请选择")
                        .font(.caption.bold())
                        .foregroundStyle(selection == nil ? AppTheme.muted : AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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
        .accessibilityLabel("\(title)：\(selection?.name ?? "未选择")")
    }

    private var selectedQueryName: String? {
        guard let province, let city, let district else { return nil }
        if district.adcode == city.adcode {
            return province.name + city.name
        }
        if city.adcode == province.adcode {
            return province.name + district.name
        }
        return city.name + district.name
    }

    private func loadProvinces() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            provinces = try await StorefrontAPIClient().administrativeAreas()
        } catch {
            errorMessage = "省市区加载失败，点击重试"
        }
    }

    private func chooseProvince(_ value: StorefrontAdministrativeArea) async {
        province = value
        city = nil
        district = nil
        cities = []
        districts = []
        await loadChildren(parent: value) { children in
            if !children.isEmpty, children.allSatisfy({ $0.level == "district" }) {
                let municipality = StorefrontAdministrativeArea(
                    name: value.name,
                    adcode: value.adcode,
                    level: "city"
                )
                cities = [municipality]
                city = municipality
                districts = children
            } else {
                cities = children.filter { $0.level != "street" }
            }
        }
    }

    private func chooseCity(_ value: StorefrontAdministrativeArea) async {
        city = value
        district = nil
        districts = []
        if value.adcode == province?.adcode {
            return
        }
        await loadChildren(parent: value) { children in
            let countyLevel = children.filter { $0.level == "district" }
            districts = countyLevel.isEmpty
                ? [StorefrontAdministrativeArea(name: value.name, adcode: value.adcode, level: "district")]
                : countyLevel
        }
    }

    private func loadChildren(
        parent: StorefrontAdministrativeArea,
        receive: ([StorefrontAdministrativeArea]) -> Void
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            receive(try await StorefrontAPIClient().administrativeAreas(parent: parent.adcode))
        } catch {
            errorMessage = "下级行政区加载失败，请重试"
        }
    }
}

private struct StorefrontBrowseFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StorefrontStore.self) private var store

    @State private var transactionType: StorefrontTransactionType?
    @State private var selectedCategory: BusinessCategory?
    @State private var districts: [String] = []
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
                Button("取消") { dismiss() }
                    .foregroundStyle(AppTheme.muted)
                Spacer()
                Text("筛选铺源")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Spacer()
                Button("重置") { reset() }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.deepClay)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    filterSection("交易方式") {
                        HStack(spacing: 8) {
                            filterChoice("全部", selected: transactionType == nil) {
                                transactionType = nil
                            }
                            ForEach(StorefrontTransactionType.allCases) { type in
                                filterChoice(type.shortTitle, selected: transactionType == type) {
                                    transactionType = type
                                }
                            }
                        }
                    }

                    filterSection("省 / 市 / 区县") {
                        if !districts.isEmpty {
                            StorefrontChipFlow(values: districts) { value in
                                districts.removeAll { $0 == value }
                            }
                        }
                        StorefrontAdministrativeCascade { value in
                            guard districts.count < 5, !districts.contains(value) else { return }
                            districts.append(value)
                        }
                    }

                    filterSection("金额与面积") {
                        Text(priceCaption)
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        HStack(spacing: 9) {
                            rangeField("最低金额", text: $minimumPrice, keyboard: .numberPad)
                            Text("—").foregroundStyle(AppTheme.muted)
                            rangeField("最高金额", text: $maximumPrice, keyboard: .numberPad)
                        }
                        Text("店铺面积（㎡）")
                            .font(.caption)
                            .foregroundStyle(AppTheme.muted)
                        HStack(spacing: 9) {
                            rangeField("最小面积", text: $minimumArea, keyboard: .decimalPad)
                            Text("—").foregroundStyle(AppTheme.muted)
                            rangeField("最大面积", text: $maximumArea, keyboard: .decimalPad)
                        }
                    }

                    filterSection("经营条件") {
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

                    filterSection("经营品类") {
                        Button { showsCategoryPicker = true } label: {
                            HStack {
                                Label(
                                    selectedCategory?.title ?? "全部品类",
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
                PrimaryActionLabel(title: "查看真实铺源", systemImage: "line.3.horizontal.decrease")
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
                    title: "筛选经营品类",
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
        case .rent: "月租范围（元）"
        case .transfer: "转让费范围（元）"
        case .sale: "出售总价范围（元）"
        case nil: "主要价格范围（按每条铺源的交易方式）"
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
        districts = store.selectedDistricts
        minimumPrice = store.minimumPriceYuan.map(String.init) ?? ""
        maximumPrice = store.maximumPriceYuan.map(String.init) ?? ""
        minimumArea = store.minimumAreaSquareMeters.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        maximumArea = store.maximumAreaSquareMeters.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? ""
        featureIDs = store.selectedFeatureIDs
    }

    private func reset() {
        transactionType = nil
        selectedCategory = nil
        districts = []
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
        store.selectedDistricts = districts
        store.minimumPriceYuan = Int(minimumPrice.replacingOccurrences(of: ",", with: ""))
        store.maximumPriceYuan = Int(maximumPrice.replacingOccurrences(of: ",", with: ""))
        store.minimumAreaSquareMeters = Double(minimumArea.replacingOccurrences(of: ",", with: ""))
        store.maximumAreaSquareMeters = Double(maximumArea.replacingOccurrences(of: ",", with: ""))
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
    @State private var districts: [String] = []
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
        .navigationTitle("区域找铺")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsCategoryPicker) {
            NavigationStack {
                StorefrontCategoryPicker(
                    title: "选择经营品类",
                    allowsMultiple: false,
                    selections: $selectedCategories
                )
            }
        }
        .alert(
            "区域推荐未完成",
            isPresented: Binding(
                get: { store.notice != nil },
                set: { if !$0 { store.notice = nil } }
            )
        ) {
            Button("知道了") { store.notice = nil }
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
                Text("最多 3 个区域")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.82))
            }
            Text("先找对一片，再看具体铺")
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text("小易只会从你选择的区县里推荐地图可确认的地标周边，并说明为什么值得继续找铺。")
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
        StorefrontFormCard(title: "找铺条件", caption: "可添加 1–5 个区县") {
            Button { showsCategoryPicker = true } label: {
                HStack(spacing: 12) {
                    FeatureIcon(symbol: selectedCategories.first?.symbol ?? "square.grid.2x2.fill", tint: AppTheme.deepClay)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("经营品类")
                            .font(.caption.bold())
                            .foregroundStyle(AppTheme.muted)
                        Text(selectedCategories.first?.title ?? "请选择")
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
            StorefrontTextField(label: "更具体的经营方式（可选）", placeholder: "例如社区早餐、精品咖啡", text: $subcategory)
            StorefrontTextField(label: "一次性总投资预算", placeholder: "元，最低 50,000", text: $budgetText, keyboard: .numberPad)

            VStack(alignment: .leading, spacing: 8) {
                Text("目标省 / 市 / 区县")
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.muted)
                if !districts.isEmpty {
                    StorefrontChipFlow(values: districts) { value in
                        districts.removeAll { $0 == value }
                    }
                }
                StorefrontAdministrativeCascade { value in
                    guard districts.count < 5, !districts.contains(value) else { return }
                    districts.append(value)
                }
                Text("行政区来自本次地图服务；加入后仍可继续选择其他区县。")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }

            Button {
                startRecommendation()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.magnifyingglass")
                    Text("让小易推荐找铺区域")
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
                title: job.error?.message ?? "这次没有形成推荐",
                detail: job.error?.remediation ?? "请核对区县名称、网络与服务状态后重试。",
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
                    Text("通常需要约 40–90 秒；离开本页后任务仍会继续")
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
                SectionTitle("推荐找铺区域", caption: "\(result.areas.count) 个")
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
                                            Text(source.publisher ?? url.host ?? "公开网页")
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
                    Label("\(result.sources.count) 个公开资料来源", systemImage: "doc.text.magnifyingglass")
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
            !districts.isEmpty
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
            guard let reservation = await communityStore.reserveFortuneUsage(
                .storefrontRecommendation
            ) else {
                return
            }
            await store.startRecommendation(
                StorefrontRecommendationRequest(
                    category: category,
                    subcategory: subcategory.trimmingCharacters(in: .whitespacesAndNewlines),
                    investmentBudgetYuan: budget,
                    districts: districts
                )
            )
            if store.recommendationJob?.state == "ready" {
                await communityStore.settleFortuneUsage(reservation)
            } else {
                await communityStore.refundFortuneUsage(reservation)
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
                    .accessibilityLabel("移除 \(value)")
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
                    Text("\(area.district) · 建议查看约 \(area.radiusMeters)m")
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
                    Text("地图核对了什么")
                        .font(.subheadline.bold())
                        .foregroundStyle(AppTheme.deepClay)
                }
            }
            NavigationLink {
                StorefrontMatchedListingsView(area: area)
            } label: {
                HStack {
                    Text(area.matchedListingIDs.isEmpty ? "查看区域（暂无上架铺源）" : "查看 \(area.matchedListingIDs.count) 个匹配铺源")
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
                    Text("推荐半径约 \(area.radiusMeters)m · 仅展示平台真实上架且预算初筛通过的铺源")
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                if isLoading {
                    ProgressView("正在核对上架状态")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("区域铺源暂未完成更新", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("重新加载") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 8)
                } else if listings.isEmpty {
                    ContentUnavailableView(
                        "这个区域暂时没有匹配铺源",
                        systemImage: "storefront",
                        description: Text("区域推荐仍可用于线下找铺；平台不会用来源不清的房源填满列表。")
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
        .navigationTitle("区域铺源")
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
                ?? "无法连接旺铺服务，请检查网络后重试。"
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
                    ProgressView("正在加载我的发布")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("我的发布暂未完成更新", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("重新加载") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AppTheme.deepClay)
                    }
                    .appCard(contentPadding: 8)
                } else if listings.isEmpty {
                    ContentUnavailableView {
                        Label("还没有发布铺源", systemImage: "tray")
                    } description: {
                        Text("发布后可以在这里查看和下架。")
                    } actions: {
                        NavigationLink("发布铺源") { StorefrontPublishView() }
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
                                Label("这条铺源已失效，立即下架", systemImage: "archivebox.fill")
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
        .navigationTitle("我的发布")
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
                ?? "无法连接旺铺服务，请检查网络后重试。"
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
                store.notice = (error as? LocalizedError)?.errorDescription ?? "下架失败。"
            }
        }
    }
}
