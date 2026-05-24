import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.runthru/ios_file_access",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "listPdfsInDirectory":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
          return
        }
        self?.listPdfsInSecurityScopedDirectory(path: path, result: result)

      case "copyPdfsToLocal":
        guard let args = call.arguments as? [String: Any],
              let sourcePath = args["sourcePath"] as? String,
              let destPath = args["destPath"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing sourcePath or destPath", details: nil))
          return
        }
        self?.copyPdfsFromSecurityScopedDirectory(sourcePath: sourcePath, destPath: destPath, result: result)

      case "getAppGroupPath":
        let path = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "group.com.mgmacri.runthru"
        )?.path
        result(path)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Lists supported book file paths inside a security-scoped directory.
  private func listPdfsInSecurityScopedDirectory(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    let accessing = url.startAccessingSecurityScopedResource()

    defer {
      if accessing { url.stopAccessingSecurityScopedResource() }
    }

    do {
      guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      ) else {
        result(FlutterError(
          code: "LIST_FAILED",
          message: "Directory enumeration failed",
          details: nil
        ))
        return
      }
      var bookPaths: [String] = []
      for case let file as URL in enumerator {
        if self.isSupportedBook(file) {
          bookPaths.append(file.path)
        }
      }
      result(bookPaths)
    } catch {
      result(FlutterError(
        code: "LIST_FAILED",
        message: "Directory listing failed: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  /// Copies supported books from a security-scoped directory to a local app directory.
  /// Returns the number of files successfully copied.
  private func copyPdfsFromSecurityScopedDirectory(
    sourcePath: String,
    destPath: String,
    result: @escaping FlutterResult
  ) {
    let sourceUrl = URL(fileURLWithPath: sourcePath)
    let accessing = sourceUrl.startAccessingSecurityScopedResource()

    defer {
      if accessing { sourceUrl.stopAccessingSecurityScopedResource() }
    }

    let destUrl = URL(fileURLWithPath: destPath)
    let fm = FileManager.default

    // Ensure destination exists.
    try? fm.createDirectory(at: destUrl, withIntermediateDirectories: true)

    do {
      guard let enumerator = fm.enumerator(
        at: sourceUrl,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      ) else {
        result(FlutterError(
          code: "COPY_FAILED",
          message: "Failed to enumerate source directory",
          details: nil
        ))
        return
      }

      var bookFiles: [URL] = []
      for case let file as URL in enumerator {
        if self.isSupportedBook(file) {
          bookFiles.append(file)
        }
      }
      var copied = 0

      for file in bookFiles {
        let destinationDirectory = try self.destinationDirectory(
          for: file,
          sourceUrl: sourceUrl,
          destUrl: destUrl,
          fileManager: fm
        )
        let destFile = self.uniqueDestinationFile(
          in: destinationDirectory,
          fileName: file.lastPathComponent,
          fileManager: fm
        )
        do {
          try fm.copyItem(at: file, to: destFile)
          copied += 1
        } catch {
          // Log but continue with other files.
          NSLog("RunThru: failed to copy \(file.lastPathComponent): \(error)")
        }
      }

      result([
        "copied": copied,
        "total": bookFiles.count,
        "destPath": destPath,
      ] as [String: Any])
    } catch {
      result(FlutterError(
        code: "COPY_FAILED",
        message: "Failed to read source directory: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  private func isSupportedBook(_ url: URL) -> Bool {
    let extensionName = url.pathExtension.lowercased()
    return extensionName == "pdf" || extensionName == "epub"
  }

  private func destinationDirectory(
    for file: URL,
    sourceUrl: URL,
    destUrl: URL,
    fileManager: FileManager
  ) throws -> URL {
    let sourcePath = sourceUrl.standardizedFileURL.path
    let fileDirectoryPath = file.deletingLastPathComponent().standardizedFileURL.path
    let relativeDirectory: String
    if fileDirectoryPath.hasPrefix(sourcePath) {
      relativeDirectory = String(fileDirectoryPath.dropFirst(sourcePath.count))
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    } else {
      relativeDirectory = ""
    }

    let destination: URL
    if relativeDirectory.isEmpty {
      destination = destUrl
    } else {
      destination = destUrl.appendingPathComponent(relativeDirectory, isDirectory: true)
    }
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    return destination
  }

  private func uniqueDestinationFile(
    in directory: URL,
    fileName: String,
    fileManager: FileManager
  ) -> URL {
    var candidate = directory.appendingPathComponent(fileName)
    if !fileManager.fileExists(atPath: candidate.path) {
      return candidate
    }

    let fileUrl = URL(fileURLWithPath: fileName)
    let stem = fileUrl.deletingPathExtension().lastPathComponent
    let extensionName = fileUrl.pathExtension
    var suffix = 2

    repeat {
      let suffixedName: String
      if extensionName.isEmpty {
        suffixedName = "\(stem) (\(suffix))"
      } else {
        suffixedName = "\(stem) (\(suffix)).\(extensionName)"
      }
      candidate = directory.appendingPathComponent(suffixedName)
      suffix += 1
    } while fileManager.fileExists(atPath: candidate.path)

    return candidate
  }
}
