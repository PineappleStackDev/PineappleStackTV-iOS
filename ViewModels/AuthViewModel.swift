import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var serverURL: String = ""
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var rememberServer: Bool = false

    init() {
        // Load "Remember Server" preference
        rememberServer = UserDefaults.standard.bool(forKey: Constants.rememberServerKey)
        if rememberServer, let savedURL = UserDefaults.standard.string(forKey: Constants.savedServerURLKey) {
            serverURL = savedURL
        }
        Task { await loadSavedCredentials() }
    }

    func loadSavedCredentials() async {
        if let savedURL = await KeychainService.shared.load(forKey: Constants.keychainServerURL),
           let savedAccess = await KeychainService.shared.load(forKey: Constants.keychainAccessToken),
           let savedRefresh = await KeychainService.shared.load(forKey: Constants.keychainRefreshToken) {
            serverURL = savedURL
            await APIClient.shared.configure(
                baseURL: savedURL,
                accessToken: savedAccess,
                refreshToken: savedRefresh
            )
            isAuthenticated = true
        }
    }

    func login() async {
        guard !serverURL.isEmpty, !username.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }

        isLoading = true
        errorMessage = nil

        // Normalize URL
        var url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("http") {
            // Use http for any IP address or localhost, https for domain names
            let isIP = url.first?.isNumber == true || url.hasPrefix("localhost") || url.hasPrefix("[")
            url = isIP ? "http://\(url)" : "https://\(url)"
        }
        // Only append default port for IP addresses or localhost without an explicit port
        if let parsed = URLComponents(string: url),
           parsed.port == nil,
           let host = parsed.host,
           (host == "localhost" || host.contains(":") || host.allSatisfy({ $0.isNumber || $0 == "." })) {
            url = "\(url):\(Constants.defaultPort)"
        }

        await APIClient.shared.configure(baseURL: url, accessToken: nil, refreshToken: nil)

        do {
            let response = try await APIClient.shared.login(username: username, password: password)

            // Save to keychain
            try await KeychainService.shared.save(url, forKey: Constants.keychainServerURL)
            try await KeychainService.shared.save(response.access, forKey: Constants.keychainAccessToken)
            try await KeychainService.shared.save(response.refresh, forKey: Constants.keychainRefreshToken)
            try await KeychainService.shared.save(username, forKey: Constants.keychainUsername)

            // Save server URL for "Remember Server"
            if rememberServer {
                UserDefaults.standard.set(serverURL, forKey: Constants.savedServerURLKey)
            }
            UserDefaults.standard.set(rememberServer, forKey: Constants.rememberServerKey)

            isAuthenticated = true
            password = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func logout() async {
        await APIClient.shared.clearTokens()
        await KeychainService.shared.deleteAll()
        isAuthenticated = false
        // Keep serverURL if "Remember Server" is on
        if !rememberServer {
            serverURL = ""
        }
        username = ""
        password = ""
    }
}
