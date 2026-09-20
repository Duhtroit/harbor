import Foundation

struct PartialDownloadProbe: Sendable {
    let expectedBytes: Int64
    let entityTag: String?
    let lastModified: String?
}

enum PartialDownloadImportError: LocalizedError, Equatable {
    case unsupportedFile
    case sourceUnavailable
    case rangeUnsupported
    case missingValidator
    case invalidLength
    case sourceChangedWhileCopying

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "Choose a regular .crdownload file with a nonzero size."
        case .sourceUnavailable:
            "Harbor could not verify the source URL. Check the link and try again."
        case .rangeUnsupported:
            "The source server does not support byte-range resume. Harbor cannot safely continue this partial file."
        case .missingValidator:
            "The source did not provide an ETag or Last-Modified validator. Harbor cannot safely continue this partial file."
        case .invalidLength:
            "The source did not report a valid total size, or the partial file is already complete."
        case .sourceChangedWhileCopying:
            "The partial file changed while it was being imported. Pause the browser download and try again."
        }
    }
}

enum PartialDownloadImportService {
    static func probe(
        sourceURL: URL,
        session: URLSession = .shared
    ) async throws -> PartialDownloadProbe {
        // Probe the exact operation Harbor will need for continuation. A HEAD
        // response can claim a resource is downloadable while the server still
        // ignores Range on GET.
        try await probeWithRangeGET(sourceURL: sourceURL, session: session)
    }

    static func makeProbe(
        from response: HTTPURLResponse,
        requireRangeSupport: Bool
    ) throws -> PartialDownloadProbe {
        let acceptsRanges = response.value(forHTTPHeaderField: "Accept-Ranges")?
            .split(separator: ",")
            .contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == "bytes" } == true
        guard requireRangeSupport == false || acceptsRanges else {
            throw PartialDownloadImportError.rangeUnsupported
        }

        let entityTag = response.value(forHTTPHeaderField: "ETag")
        let lastModified = response.value(forHTTPHeaderField: "Last-Modified")
        guard entityTag?.isEmpty == false || lastModified?.isEmpty == false else {
            throw PartialDownloadImportError.missingValidator
        }

        let expectedBytes = response.value(forHTTPHeaderField: "Content-Length")
            .flatMap(Int64.init)
            ?? 0
        guard expectedBytes > 0 else {
            throw PartialDownloadImportError.invalidLength
        }
        return PartialDownloadProbe(
            expectedBytes: expectedBytes,
            entityTag: entityTag,
            lastModified: lastModified
        )
    }

    private static func probeWithRangeGET(
        sourceURL: URL,
        session: URLSession
    ) async throws -> PartialDownloadProbe {
        var request = URLRequest(url: sourceURL)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PartialDownloadImportError.sourceUnavailable
        }
        _ = data
        guard response.statusCode == 206,
              let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
              let slash = contentRange.lastIndex(of: "/"),
              let total = Int64(contentRange[contentRange.index(after: slash)...]),
              total > 0 else {
            throw PartialDownloadImportError.rangeUnsupported
        }
        let base = try makeProbe(
            from: response,
            requireRangeSupport: false
        )
        return PartialDownloadProbe(
            expectedBytes: total,
            entityTag: base.entityTag,
            lastModified: base.lastModified
        )
    }
}
