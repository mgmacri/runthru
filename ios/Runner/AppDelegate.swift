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

  /// Lists PDF file paths inside a security-scoped directory.
  private func listPdfsInSecurityScopedDirectory(path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    let accessing = url.startAccessingSecurityScopedResource()

    defer {
      if accessing { url.stopAccessingSecurityScopedResource() }
    }

    do {
      let contents = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      let pdfPaths = contents
        .filter { $0.pathExtension.lowercased() == "pdf" }
        .map { $0.path }
      result(pdfPaths)
    } catch {
      result(FlutterError(
        code: "LIST_FAILED",
        message: "Directory listing failed: \(error.localizedDescription)",
        details: nil
      ))
    }
  }

  /// Copies PDFs from a security-scoped directory to a local app directory.
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
      let contents = try fm.contentsOfDirectory(
        at: sourceUrl,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
      let pdfFiles = contents.filter { $0.pathExtension.lowercased() == "pdf" }
      var copied = 0

      for file in pdfFiles {
        let destFile = destUrl.appendingPathComponent(file.lastPathComponent)
        // Remove existing file at destination to allow overwrite.
        try? fm.removeItem(at: destFile)
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
        "total": pdfFiles.count,
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
}
