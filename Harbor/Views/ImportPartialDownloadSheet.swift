import AppKit
import SwiftUI

struct ImportPartialDownloadSheet: View {
    let destinationFolder: URL
    let onImport: @MainActor (URL, URL) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    @State private var partialURL: URL?
    @State private var sourceText = ""
    @State private var didConfirmPaused = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var sourceURL: URL? {
        guard let url = URL(string: sourceText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            return nil
        }
        return url
    }

    private var partialSize: Int64? {
        guard let partialURL,
              let values = try? partialURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              size > 0 else {
            return nil
        }
        return Int64(size)
    }

    private var canContinue: Bool {
        switch step {
        case 1: partialURL != nil && partialSize != nil
        case 2: sourceURL != nil
        case 3: didConfirmPaused
        default: false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Import Partial Download")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("Step \(step) of 4")
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(step), total: 4)
                .progressViewStyle(.linear)

            Group {
                switch step {
                case 1: chooseFileStep
                case 2: sourceStep
                case 3: pauseStep
                default: reviewStep
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if step > 1 {
                    Button("Back") {
                        errorMessage = nil
                        step -= 1
                    }
                }
                if step < 4 {
                    Button("Continue") {
                        errorMessage = nil
                        step += 1
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(canContinue == false)
                } else {
                    Button(isImporting ? "Verifying…" : "Import and Prepare Resume") {
                        importFile()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting || partialURL == nil || sourceURL == nil)
                }
            }
        }
        .padding(24)
        .frame(width: 650)
    }

    private var chooseFileStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Select the browser partial file")
                .font(.headline)
            Text("First pause the download in Chrome or Chromium. Then choose the file ending in .crdownload. Harbor will copy it and will not modify the browser’s file.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(partialURL?.path ?? "No file selected")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose .crdownload…") { choosePartialFile() }
            }
            if let partialSize {
                Label("Snapshot size: \(ByteCountFormatter.string(fromByteCount: partialSize, countStyle: .file))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Provide the original download URL")
                .font(.headline)
            Text("Copy the direct HTTP/HTTPS URL from Chrome’s download details. Do not paste the page URL unless it is also the file URL.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://example.com/file.zip", text: $sourceText)
                .textFieldStyle(.roundedBorder)
            if sourceText.isEmpty == false && sourceURL == nil {
                Text("Enter a complete http:// or https:// URL.")
                    .foregroundStyle(.orange)
            }
        }
    }

    private var pauseStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Confirm the browser has stopped writing")
                .font(.headline)
            Text("A live .crdownload file can change while Harbor copies it. This could create a corrupt resume point. Pause or cancel the browser download before continuing.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("I paused the browser download and the partial file is no longer changing", isOn: $didConfirmPaused)
            Label("Harbor uses a safe copy and never writes to Chrome’s file.", systemImage: "lock.shield")
                .foregroundStyle(.secondary)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("4. Review before importing")
                .font(.headline)
            LabeledContent("Partial file", value: partialURL?.lastPathComponent ?? "-")
            LabeledContent("Snapshot size", value: partialSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "-")
            LabeledContent("Source", value: sourceURL?.absoluteString ?? "-")
            Text("Harbor will verify byte-range support and an ETag or Last-Modified value. If the server cannot prove the resource is unchanged, Harbor will refuse the import instead of risking corruption.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choosePartialFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.directoryURL = destinationFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "crdownload" else {
            errorMessage = "Choose a file ending in .crdownload."
            return
        }
        partialURL = url
        errorMessage = nil
    }

    private func importFile() {
        guard let partialURL, let sourceURL else { return }
        isImporting = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await onImport(partialURL, sourceURL)
                dismiss()
            } catch {
                isImporting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
