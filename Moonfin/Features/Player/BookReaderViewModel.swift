import Foundation
import SwiftUI
import ZIPFoundation

@MainActor
final class BookReaderViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var isLoading: Bool = true
    @Published var errorMessage: String?
    @Published var currentIndex: Int = 0
    @Published var totalCount: Int = 0
    @Published var currentImage: UIImage?
    @Published var overlayVisible: Bool = true

    private let container: AppContainer
    private let itemId: String
    private let serverId: String?

    private var pageProvider: PageProvider?
    private var hideTask: Task<Void, Never>?
    
    private let overlayTimeout: TimeInterval = 5
    private let thumbnailWidth: CGFloat = 3200
    private let thumbnailHeight: CGFloat = 1800
    private let chapterImageMaxWidth: CGFloat = 1920

    private enum BookFormat {
        case pdf
        case cbz
        case cbr
    }

    private enum PageProvider {
        case pdf(CGPDFDocument)
        case images([Data])

        var count: Int {
            switch self {
            case .pdf(let document):
                return document.numberOfPages
            case .images(let pages):
                return pages.count
            }
        }
    }

    init(container: AppContainer, itemId: String, serverId: String?) {
        self.container = container
        self.itemId = itemId
        self.serverId = serverId
    }

    func load() async {
        isLoading = true
        errorMessage = nil

        guard let client = await resolveClient() else {
            errorMessage = Strings.playerBookCouldNotConnect
            isLoading = false
            return
        }

        do {
            let item = try await client.userLibraryApi.getItem(itemId: itemId)
            title = item.name

            guard let format = detectFormat(item: item) else {
                throw NSError(domain: "BookReader", code: -104, userInfo: [NSLocalizedDescriptionKey: Strings.playerBookUnsupportedFormat])
            }

            if format == .cbr {
                let pages = try await loadServerComicPages(item: item, client: client)
                pageProvider = .images(pages)
            } else {
                let data = try await downloadBookData(item: item, client: client)
                pageProvider = try buildProvider(format: format, data: data)
            }
            totalCount = pageProvider?.count ?? 0

            guard totalCount > 0 else {
                throw NSError(domain: "BookReader", code: -108, userInfo: [NSLocalizedDescriptionKey: Strings.playerBookNoReadablePages])
            }

            currentIndex = min(max(0, currentIndex), totalCount - 1)
            renderCurrentPage()
            isLoading = false
            showOverlay()
        } catch {
            errorMessage = (error as NSError?)?.userInfo[NSLocalizedDescriptionKey] as? String ?? Strings.playerBookUnableToLoad
            isLoading = false
        }
    }

    func goToNextPage() {
        guard totalCount > 0 else { return }
        currentIndex = min(currentIndex + 1, totalCount - 1)
        renderCurrentPage()
        showOverlay()
    }

    func goToPreviousPage() {
        guard totalCount > 0 else { return }
        currentIndex = max(currentIndex - 1, 0)
        renderCurrentPage()
        showOverlay()
    }

    func showOverlay() {
        overlayVisible = true
        resetHideTimer()
    }

    func cleanup() {
        hideTask?.cancel()
    }

    var progressText: String {
        guard totalCount > 0 else { return "" }
        return "\(currentIndex + 1) / \(totalCount)"
    }

    private func resolveClient() async -> MediaServerClient? {
        if let serverId,
           let parsedId = UUID.from(rawId: serverId),
           let server = await container.serverRepository.getServer(id: parsedId, eagerUpdate: false) {
            return container.serverClientFactory.client(for: server)
        }

        guard let current = container.serverRepository.currentServer.value else { return nil }
        return container.serverClientFactory.client(for: current)
    }

    private func detectFormat(item: ServerItem) -> BookFormat? {
        let candidates: [String?] = [
            item.container,
            item.name,
            item.mediaSources?.first?.container,
            item.mediaSources?.first?.name,
        ]

        for candidate in candidates {
            guard let normalized = candidate?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !normalized.isEmpty else { continue }

            let isPDF = normalized == "pdf" || normalized == "application/pdf" || normalized.hasSuffix(".pdf")
            let isCBZ = normalized == "cbz" || normalized == "application/zip" || normalized.hasSuffix(".cbz") || normalized.hasSuffix(".zip")
            let isCBR = normalized == "cbr" || normalized.hasSuffix(".cbr") || normalized.hasSuffix(".rar")

            if isPDF { return .pdf }
            if isCBZ { return .cbz }
            if isCBR { return .cbr }
        }

        return nil
    }

    private func downloadBookData(item: ServerItem, client: MediaServerClient) async throws -> Data {
        let candidates = buildDownloadURLs(item: item, client: client)
        let headers = buildAuthHeaders(client: client)

        var lastError: Error?
        for url in candidates {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 60
                headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), !data.isEmpty {
                    return data
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? NSError(domain: "BookReader", code: -100, userInfo: [NSLocalizedDescriptionKey: Strings.playerBookDownloadFailed])
    }

    private func buildDownloadURLs(item: ServerItem, client: MediaServerClient) -> [URL] {
        guard let baseURL = client.baseURL else { return [] }

        let mediaSourceId = item.mediaSources?.first?.id
        let token = client.accessToken
        let encodedId = item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.id

        var urls: [URL] = []

        func buildURL(path: String, extraQuery: [URLQueryItem] = []) -> URL? {
            var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            var query: [URLQueryItem] = []
            if let mediaSourceId {
                query.append(URLQueryItem(name: "MediaSourceId", value: mediaSourceId))
            }
            if let token, !token.isEmpty {
                query.append(URLQueryItem(name: "api_key", value: token))
            }
            query.append(contentsOf: extraQuery)
            components?.queryItems = query.isEmpty ? nil : query
            return components?.url
        }

        if let url = buildURL(path: "Items/\(encodedId)/Download") {
            urls.append(url)
        }
        if let url = buildURL(path: "Items/\(encodedId)/File") {
            urls.append(url)
        }
        if let url = buildURL(path: "Videos/\(encodedId)/stream", extraQuery: [URLQueryItem(name: "Static", value: "true")]) {
            urls.append(url)
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private func buildAuthHeaders(client: MediaServerClient) -> [String: String] {
        guard let token = client.accessToken, !token.isEmpty else { return [:] }
        return [
            "X-Emby-Token": token,
            "Authorization": "MediaBrowser Token=\"\(token)\""
        ]
    }

    private func buildProvider(format: BookFormat, data: Data) throws -> PageProvider {
        switch format {
        case .pdf:
            guard let provider = CGDataProvider(data: data as CFData),
                  let document = CGPDFDocument(provider),
                  document.numberOfPages > 0 else {
                                throw NSError(domain: "BookReader", code: -102, userInfo: [NSLocalizedDescriptionKey: Strings.playerBookInvalidPdf])
            }
            return .pdf(document)

        case .cbz:
            let pages = try extractCBZPages(data: data)
            return .images(pages)

        case .cbr:
            throw NSError(domain: "BookReader", code: -107, userInfo: [NSLocalizedDescriptionKey: Strings.playerBookCbrNeedsServerChapters])
        }
    }

    private func extractCBZPages(data: Data) throws -> [Data] {
        guard let archive = Archive(data: data, accessMode: .read) else {
            throw NSError(domain: "BookReader", code: -103, userInfo: [NSLocalizedDescriptionKey: Strings.playerBookInvalidCbz])
        }
        let imageEntries = archive
            .filter { $0.type == .file && isImagePath($0.path) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        var pages: [Data] = []
        pages.reserveCapacity(imageEntries.count)

        for entry in imageEntries {
            var entryData = Data()
            _ = try archive.extract(entry, consumer: { entryData.append($0) })
            if !entryData.isEmpty {
                pages.append(entryData)
            }
        }

        return pages
    }

    private func loadServerComicPages(item: ServerItem, client: MediaServerClient) async throws -> [Data] {
        let chapterCount = max(item.chapters?.count ?? 0, 0)
        guard chapterCount > 0 else {
            throw NSError(domain: "BookReader", code: -105, userInfo: [NSLocalizedDescriptionKey: Strings.playerBookNoChapters])
        }

        let headers = buildAuthHeaders(client: client)
        var pages: [Data] = []
        pages.reserveCapacity(chapterCount)

        for index in 0..<chapterCount {
            let urlString = client.imageApi.getChapterImageUrl(
                itemId: item.id,
                chapterIndex: index,
                maxWidth: Int(chapterImageMaxWidth),
                tag: nil
            )

            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty,
                  UIImage(data: data) != nil else {
                continue
            }

            pages.append(data)
        }

        if pages.isEmpty {
            throw NSError(domain: "BookReader", code: -106, userInfo: [NSLocalizedDescriptionKey: Strings.playerBookComicPagesFailed])
        }

        return pages
    }

    private func isImagePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") || lower.hasSuffix(".webp") || lower.hasSuffix(".bmp")
    }

    private func renderCurrentPage() {
        guard let provider = pageProvider else {
            currentImage = nil
            return
        }

        switch provider {
        case .pdf(let document):
            guard let page = document.page(at: currentIndex + 1) else {
                currentImage = nil
                return
            }
            currentImage = renderPDFPage(page, maxSize: CGSize(width: thumbnailWidth, height: thumbnailHeight))

        case .images(let pages):
            currentImage = pages.indices.contains(currentIndex) ? UIImage(data: pages[currentIndex]) : nil
        }
    }

    private func renderPDFPage(_ page: CGPDFPage, maxSize: CGSize) -> UIImage? {
        let mediaBox = page.getBoxRect(.mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else { return nil }

        let aspectRatio = mediaBox.width / mediaBox.height
        let targetAspect = maxSize.width / maxSize.height
        let width: CGFloat
        let height: CGFloat
        if aspectRatio > targetAspect {
            width = min(maxSize.width, mediaBox.width)
            height = width / aspectRatio
        } else {
            height = min(maxSize.height, mediaBox.height)
            width = height * aspectRatio
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext
            cgCtx.setFillColor(UIColor.white.cgColor)
            cgCtx.fill(CGRect(origin: .zero, size: CGSize(width: width, height: height)))
            cgCtx.translateBy(x: 0, y: height)
            cgCtx.scaleBy(x: 1, y: -1)
            cgCtx.scaleBy(x: width / mediaBox.width, y: height / mediaBox.height)
            cgCtx.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)
            cgCtx.drawPDFPage(page)
        }
    }

    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(overlayTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            overlayVisible = false
        }
    }
}
