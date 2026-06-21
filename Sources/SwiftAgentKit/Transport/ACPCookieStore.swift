//
//  ACPCookieStore.swift
//  SwiftAgentKit
//

import Foundation

/// Stores and returns HTTP cookies for ACP remote transports (required by the draft RFD).
public actor ACPCookieStore {
    private var cookies: [HTTPCookie] = []

    public init() {}

    public func store(from response: HTTPURLResponse, for url: URL) {
        if let headerFields = response.allHeaderFields as? [String: String] {
            let newCookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            merge(newCookies)
        }
    }

    public func cookies(for url: URL) -> [HTTPCookie] {
        cookies.filter { cookie in
            if let domain = cookie.domain.isEmpty ? nil : cookie.domain {
                let host = url.host ?? ""
                return host.hasSuffix(domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
            }
            return true
        }
    }

    public func apply(to request: inout URLRequest, url: URL) {
        let relevant = cookies(for: url)
        guard !relevant.isEmpty else { return }
        let headers = HTTPCookie.requestHeaderFields(with: relevant)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    public func clear() {
        cookies.removeAll()
    }

    private func merge(_ newCookies: [HTTPCookie]) {
        for cookie in newCookies {
            cookies.removeAll {
                $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
            }
            cookies.append(cookie)
        }
    }
}
