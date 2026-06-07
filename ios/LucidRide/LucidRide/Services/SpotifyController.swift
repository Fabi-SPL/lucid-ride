import Foundation
import SwiftUI
import UIKit
import AuthenticationServices
import CryptoKit

/// Spotify playback control via the Web API + PKCE OAuth — no native SDK, so it
/// links cleanly in the XcodeGen / GitHub-Actions build (pure system frameworks).
///
/// Flow: one-time `connect()` from Settings opens an ASWebAuthenticationSession,
/// we exchange the code for tokens (PKCE — no client secret), persist them, and
/// the ride HUD then sends play / pause / next / previous and shows the current
/// track. Control acts on the account's currently-active device (Spotify running
/// on this phone). Requires Spotify Premium — the Web API rejects playback
/// control on free accounts with 403.
@MainActor
final class SpotifyController: NSObject, ObservableObject {

    static let shared = SpotifyController()

    // Client ID is public — it ships inside every app build. Never embed the secret.
    private let clientID    = "4b6bc22bcd16410498d0f1685791251f"
    private let redirectURI = "lucidride://spotify-callback"
    private let scopes      = "user-modify-playback-state user-read-playback-state user-read-currently-playing"

    @Published private(set) var isConnected = false
    @Published private(set) var trackTitle: String?
    @Published private(set) var artistName: String?
    @Published private(set) var isPlaying  = false
    @Published private(set) var statusNote = ""

    private var authSession: ASWebAuthenticationSession?
    private var pendingVerifier: String?

    private enum K {
        static let access  = "spotify.accessToken"
        static let refresh = "spotify.refreshToken"
        static let expiry  = "spotify.expiry"          // timeIntervalSince1970
    }
    private var accessToken: String?  { UserDefaults.standard.string(forKey: K.access) }
    private var refreshToken: String? { UserDefaults.standard.string(forKey: K.refresh) }
    private var expiry: Date { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: K.expiry)) }

    override init() {
        super.init()
        isConnected = (refreshToken != nil)
    }

    // MARK: - Auth

    func connect() {
        let verifier = Self.randomCodeVerifier()
        pendingVerifier = verifier
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: scopes)
        ]
        guard let url = comps.url else { return }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lucidride") { [weak self] callback, _ in
            guard let self else { return }
            guard let callback,
                  let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                      .queryItems?.first(where: { $0.name == "code" })?.value else {
                self.statusNote = "Login cancelled"
                return
            }
            Task { await self.exchangeCode(code) }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: K.access)
        UserDefaults.standard.removeObject(forKey: K.refresh)
        UserDefaults.standard.removeObject(forKey: K.expiry)
        isConnected = false
        trackTitle = nil; artistName = nil; isPlaying = false; statusNote = ""
    }

    private func exchangeCode(_ code: String) async {
        guard let verifier = pendingVerifier else { return }
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        await tokenRequest(body: form.percentEncodedQuery ?? "")
        if isConnected { await refreshNowPlaying() }
    }

    private func refreshAccessToken() async {
        guard let refresh = refreshToken else { return }
        var form = URLComponents()
        form.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refresh),
            URLQueryItem(name: "client_id", value: clientID)
        ]
        await tokenRequest(body: form.percentEncodedQuery ?? "")
    }

    private func tokenRequest(body: String) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                statusNote = "Login failed"
                return
            }
            if let access = json["access_token"] as? String { UserDefaults.standard.set(access, forKey: K.access) }
            if let refresh = json["refresh_token"] as? String { UserDefaults.standard.set(refresh, forKey: K.refresh) }
            let expiresIn = (json["expires_in"] as? Double) ?? 3600
            UserDefaults.standard.set(Date().timeIntervalSince1970 + expiresIn - 60, forKey: K.expiry)
            isConnected = (UserDefaults.standard.string(forKey: K.refresh) != nil)
            statusNote = ""
        } catch {
            statusNote = "Network error"
        }
    }

    private func validToken() async -> String? {
        if accessToken != nil, Date() < expiry { return accessToken }
        await refreshAccessToken()
        return accessToken
    }

    // MARK: - Playback control

    func togglePlayPause() { Task { await control(isPlaying ? "pause" : "play", method: "PUT"); await afterAction() } }
    func next()            { Task { await control("next", method: "POST"); await afterAction() } }
    func previous()        { Task { await control("previous", method: "POST"); await afterAction() } }

    private func afterAction() async {
        // Spotify needs a beat before currently-playing reflects the change.
        try? await Task.sleep(nanoseconds: 350_000_000)
        await refreshNowPlaying()
    }

    private func control(_ action: String, method: String) async {
        guard let token = await validToken() else { statusNote = "Connect Spotify"; return }
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/\(action)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return }
            switch http.statusCode {
            case 200..<300: statusNote = ""
            case 401:       await refreshAccessToken()
            case 403:       statusNote = "Premium required"
            case 404:       statusNote = "Open Spotify & play once"
            default:        statusNote = "Spotify \(http.statusCode)"
            }
        } catch {
            statusNote = "No signal"
        }
    }

    func refreshNowPlaying() async {
        guard let token = await validToken() else { return }
        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return }
        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if (resp as? HTTPURLResponse)?.statusCode == 204 { isPlaying = false }   // nothing playing
            return
        }
        isPlaying = (json["is_playing"] as? Bool) ?? false
        if let item = json["item"] as? [String: Any] {
            trackTitle = item["name"] as? String
            if let artists = item["artists"] as? [[String: Any]] {
                artistName = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
            }
        }
    }

    // MARK: - PKCE helpers

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        for i in bytes.indices { bytes[i] = UInt8.random(in: UInt8.min...UInt8.max) }
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

extension SpotifyController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
