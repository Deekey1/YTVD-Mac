import CoreTransferable
import Foundation
import Photos
import UniformTypeIdentifiers

/// Сохранение в «Фото»: просим только право добавлять, читать медиатеку незачем.
enum PhotosSaver {
    static func save(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw AppError.photosDenied }
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

/// Файл для «Поделиться» под человеческим именем, а не под внутренним UUID.
/// Ссылка на тот же файл (hard link) места не занимает.
struct SharedMediaFile: Transferable {
    let source: URL
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .movie) { file in
            SentTransferredFile(try file.namedCopy(), allowAccessingOriginalFile: true)
        }
        .exportingCondition { $0.source.pathExtension.lowercased() != "m4a" }

        FileRepresentation(exportedContentType: .mpeg4Audio) { file in
            SentTransferredFile(try file.namedCopy(), allowAccessingOriginalFile: true)
        }
    }

    private func namedCopy() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: target)
        do {
            try FileManager.default.linkItem(at: source, to: target)
        } catch {
            try FileManager.default.copyItem(at: source, to: target)
        }
        return target
    }
}
