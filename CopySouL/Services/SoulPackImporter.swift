import Foundation

enum SoulPackImportError: LocalizedError {
    case notDirectory(URL)
    case missingRequiredFile(String)
    case invalidSettings(Error)

    var errorDescription: String? {
        switch self {
        case .notDirectory(let url):
            return "\(url.lastPathComponent) is not a SOUL pack folder."
        case .missingRequiredFile(let file):
            return "SOUL pack is missing required file: \(file)."
        case .invalidSettings(let error):
            return "setting.json could not be parsed: \(error.localizedDescription)"
        }
    }
}

struct SoulPackImporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func importPack(at rootURL: URL) throws -> SoulPack {
        guard rootURL.isDirectory else {
            throw SoulPackImportError.notDirectory(rootURL)
        }

        guard let soulURL = child(named: "SOUL.md", in: rootURL) else {
            throw SoulPackImportError.missingRequiredFile("SOUL.md")
        }
        guard let settingsURL = child(named: "setting.json", in: rootURL) else {
            throw SoulPackImportError.missingRequiredFile("setting.json")
        }

        let soulDefinition = try String(contentsOf: soulURL, encoding: .utf8)
        let settings: SoulSettings
        do {
            settings = try JSONDecoder().decode(SoulSettings.self, from: Data(contentsOf: settingsURL))
        } catch {
            throw SoulPackImportError.invalidSettings(error)
        }

        let id = UUID().uuidString
        var warnings = [String]()
        let assets = try scanAssets(in: rootURL, soulID: id, warnings: &warnings)
        let name = settings.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? rootURL.lastPathComponent

        return SoulPack(
            id: id,
            name: name,
            rootURL: rootURL,
            soulDefinition: soulDefinition,
            settings: settings,
            assets: assets,
            warnings: warnings,
            importedAt: Date()
        )
    }

    private func scanAssets(in packRoot: URL, soulID: String, warnings: inout [String]) throws -> [SoulAsset] {
        let rootDirectories = try childDirectories(of: packRoot)
        let knownAssetRoots = rootDirectories.filter { Self.assetRootNames.contains($0.lastPathComponent.normalizedAssetName) }
        let customAssetRoots = rootDirectories.filter { !Self.assetRootNames.contains($0.lastPathComponent.normalizedAssetName) }
        let assetRoots = knownAssetRoots + customAssetRoots

        var assets = [SoulAsset]()
        for assetRoot in assetRoots {
            let rootEntries = try children(of: assetRoot)
            let nestedDirectories = rootEntries.filter(\.isDirectory)
            let rootFiles = rootEntries.filter { !$0.isDirectory && !$0.isHiddenFile }

            if !rootFiles.isEmpty {
                assets += try scanFiles(rootFiles, type: inferType(forDirectory: assetRoot, files: rootFiles), root: packRoot, soulID: soulID, warnings: &warnings)
            }

            for directory in nestedDirectories where !directory.isHiddenFile {
                let files = try recursiveFiles(in: directory)
                let type = inferType(forDirectory: directory, files: files)
                assets += try scanFiles(files, type: type, root: packRoot, soulID: soulID, warnings: &warnings)
            }
        }

        return assets
    }

    private func scanFiles(_ files: [URL], type: SoulAssetType, root: URL, soulID: String, warnings: inout [String]) throws -> [SoulAsset] {
        let descriptionIndex = type == .meme ? try memeDescriptionIndex(from: files) : [:]
        var assets = [SoulAsset]()

        for file in files where !file.isHiddenFile {
            let ext = file.pathExtension.lowercased()
            guard !Self.markdownExtensions.contains(ext) else { continue }

            let assetType = type == .other ? inferType(forFile: file) : type
            guard assetType != .other || !Self.ignoredAssetExtensions.contains(ext) else { continue }

            let description = descriptionIndex[file.lastPathComponent.lowercased()]
            if assetType == .meme && description == nil {
                warnings.append("Meme \(file.lastPathComponent) has no markdown usage description, so it will not be exposed to select_meme.")
            }

            assets.append(SoulAsset(
                id: UUID().uuidString,
                soulID: soulID,
                relativePath: relativePath(for: file, root: root),
                fileURL: file,
                type: assetType,
                description: description?.description,
                usageHint: description?.usageHint
            ))
        }

        return assets
    }

    private func memeDescriptionIndex(from files: [URL]) throws -> [String: (description: String, usageHint: String)] {
        var index = [String: (description: String, usageHint: String)]()
        let markdownFiles = files.filter { Self.markdownExtensions.contains($0.pathExtension.lowercased()) }

        for markdown in markdownFiles {
            let body = try String(contentsOf: markdown, encoding: .utf8)
            let lines = body.components(separatedBy: .newlines)
            for line in lines {
                for imageName in Self.imageFilenames(in: line) {
                    let cleaned = line
                        .replacingOccurrences(of: "|", with: " ")
                        .replacingOccurrences(of: "`", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard cleaned.nonEmpty != nil else { continue }
                    index[imageName.lowercased()] = (description: cleaned, usageHint: cleaned)
                }
            }
        }

        return index
    }

    private func inferType(forDirectory directory: URL, files: [URL]) -> SoulAssetType {
        let name = directory.lastPathComponent.normalizedAssetName
        if Self.memeDirectoryNames.contains(name) { return .meme }
        if Self.documentDirectoryNames.contains(name) { return .document }
        if Self.imageDirectoryNames.contains(name) { return .image }

        let extensions = Set(files.map { $0.pathExtension.lowercased() })
        let hasImages = !extensions.intersection(Self.imageExtensions).isEmpty
        let hasMarkdown = !extensions.intersection(Self.markdownExtensions).isEmpty
        let hasDocuments = !extensions.intersection(Self.documentExtensions).isEmpty
        if hasImages && hasMarkdown { return .meme }
        if hasImages { return .image }
        if hasDocuments { return .document }
        return .other
    }

    private func inferType(forFile file: URL) -> SoulAssetType {
        let ext = file.pathExtension.lowercased()
        if Self.imageExtensions.contains(ext) { return .image }
        if Self.documentExtensions.contains(ext) { return .document }
        return .other
    }

    private func child(named name: String, in directory: URL) -> URL? {
        (try? children(of: directory))?.first { $0.lastPathComponent == name }
    }

    private func children(of directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        )
    }

    private func childDirectories(of directory: URL) throws -> [URL] {
        try children(of: directory).filter(\.isDirectory).filter { !$0.isHiddenFile }
    }

    private func recursiveFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey]) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }.filter { !$0.isDirectory }
    }

    private func relativePath(for file: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return file.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func imageFilenames(in line: String) -> [String] {
        let pattern = #"[^`\s\|\]\)\(\/\\]+?\.(?:png|jpg|jpeg|gif|webp)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            Range(match.range, in: line).map { String(line[$0]) }
        }
    }

    private static let assetRootNames: Set<String> = ["assets", "asset", "资源", "素材", "resource", "resources"]
    private static let memeDirectoryNames: Set<String> = ["meme", "memes", "emoji", "emojis", "sticker", "stickers", "表情", "表情包", "贴纸"]
    private static let documentDirectoryNames: Set<String> = ["doc", "docs", "document", "documents", "文档", "资料"]
    private static let imageDirectoryNames: Set<String> = ["image", "images", "img", "imgs", "picture", "pictures", "pic", "pics", "图片", "图像"]
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]
    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let documentExtensions: Set<String> = ["md", "markdown", "txt", "pdf", "doc", "docx", "rtf"]
    private static let ignoredAssetExtensions: Set<String> = ["ds_store"]
}

private extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    var isHiddenFile: Bool {
        lastPathComponent.hasPrefix(".")
    }
}

private extension String {
    var normalizedAssetName: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
