import Foundation
import Testing
@testable import DevbarCore

struct AppInfoTests {
    @Test func versionWithBuild() {
        #expect(AppInfo.versionText(["CFBundleShortVersionString": "0.3.0", "CFBundleVersion": "123"]) == "0.3.0 (123)")
    }

    @Test func versionWithoutBuildOrSameAsVersion() {
        #expect(AppInfo.versionText(["CFBundleShortVersionString": "0.3.0"]) == "0.3.0")
        #expect(AppInfo.versionText(["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1.0"]) == "1.0")
    }

    @Test func missingVersion() {
        #expect(AppInfo.versionText(nil) == "sconosciuta")
        #expect(AppInfo.versionText(["CFBundleShortVersionString": ""]) == "sconosciuta")
    }

    @Test func links() {
        #expect(AppInfo.repositoryURL.absoluteString == "https://github.com/savez/devbar")
        #expect(AppInfo.issuesURL.absoluteString == "https://github.com/savez/devbar/issues")
        #expect(AppInfo.licenseURL.lastPathComponent == "LICENSE")
        #expect(AppInfo.supportURL.host == "buymeacoffee.com")
        #expect(AppInfo.supportURL.scheme == "https")
    }
}
