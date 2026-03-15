# PRD: EasyNet v2.0 — Refactor & Production Hardening

**Author:** Claude (Expert Code Review)
**Date:** 2026-03-14
**Status:** Draft — Awaiting Review
**Package:** `seklabsnet/EasyNet`
**Current Version:** 1.0.1
**Target Version:** 2.0.0
**Platform:** iOS 18+ / macOS 15+
**Swift Tools Version:** 6.2
**Dependency:** Alamofire 5.10.2+

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current Architecture Analysis](#2-current-architecture-analysis)
3. [Issue Registry — Full Detail](#3-issue-registry--full-detail)
4. [Target Architecture](#4-target-architecture)
5. [Detailed Specifications per Goal](#5-detailed-specifications-per-goal)
6. [Dependency Graph](#6-dependency-graph)
7. [Migration Plan & Phases](#7-migration-plan--phases)
8. [Testing Strategy](#8-testing-strategy)
9. [Versioning & Release Strategy](#9-versioning--release-strategy)
10. [Risk Analysis](#10-risk-analysis)
11. [Success Criteria](#11-success-criteria)
12. [Open Questions](#12-open-questions)
13. [Appendix](#13-appendix)

---

## 1. Executive Summary

EasyNet is a lightweight networking abstraction layer built on top of Alamofire. It provides `NetworkManager` for executing requests, `NetworkServiceProvider` for building `URLRequest`s, and property wrappers (`@ServiceWrapper`, `@ServiceWrapperWithRequest`) for declarative endpoint definitions.

The package is **minimal and functional** (~250 lines), but has several issues spanning **code duplication, outdated patterns, protocol-implementation mismatch, and unnecessary type erasure**. None are critical crashes, but they add technical debt and miss opportunities for cleaner, more modern Swift.

### Impact Summary

| Category | Current State | Target State |
|----------|--------------|--------------|
| Code duplication | Error handling copy-pasted 4x | Single `mapError()` method |
| Async pattern | `withCheckedThrowingContinuation` bridge | Native Alamofire async/await |
| Type safety | `Encodable` → `[String: Any]` → encoding | Direct `Encodable` via `ParameterEncoder` |
| Protocol coverage | 3/4 methods in protocol | All methods in protocol |
| Duplicate extensions | `asDictionary()` defined twice | Single definition |
| Utility bloat | 3 methods doing same thing | 1 canonical method |
| Test coverage | 0% | Core methods covered |

---

## 2. Current Architecture Analysis

### 2.1 File Inventory

```
Sources/EasyNet/
├── EasyNet.swift                          # Empty entry point (3 lines)
├── Manager/
│   ├── NetworkManager.swift               # ⭐ Core — Alamofire executor (153 lines)
│   ├── NetworkManagerProtocol.swift       # Protocol definition (23 lines)
│   └── NetworkError.swift                 # Error enum (52 lines)
├── Providers/
│   └── NetworkServiceProvider.swift       # URLRequest builder (78 lines)
└── Utilities/
    ├── Extensions/
    │   └── Encodable+dict.swift           # JSON serialization helpers (36 lines)
    └── Wrappers/
        ├── ServiceWrapper.swift           # No-body endpoint wrapper (30 lines)
        ├── ServiceWrapperWithRequest.swift # With-body endpoint wrapper (32 lines)
        └── EmptyRequestContent.swift      # Empty body placeholder (8 lines)
```

**Total:** 10 files, ~415 lines
**Active logic:** ~300 lines (rest is boilerplate/empty)

### 2.2 Object Graph

```
┌─────────────────────────────────────────────────────────┐
│ Consumer (centauri-ios AppNetwork)                        │
│                                                          │
│   @ServiceWrapper(baseUrl: url, path: "users", method: .get)
│   var getUsers: URLRequestConvertible                    │
│                                                          │
│   @ServiceWrapperWithRequest(baseUrl: url, path: "auth/login",
│       data: LoginRequest(...), method: .post)            │
│   var login: URLRequestConvertible                       │
└──────────────┬───────────────────────────────────────────┘
               │ wrappedValue produces
               ▼
┌─────────────────────────────────────────────────────────┐
│ NetworkServiceProvider<R: Encodable & Sendable>           │
│   baseUrl: String                                        │
│   path: String                                           │
│   method: HTTPMethod                                     │
│   data: R                                                │
│                                                          │
│   asURLRequest() → URLRequest                            │
│     ├── GET → URLEncoding.queryString                    │
│     └── POST/PUT/PATCH → JSONEncoding.default            │
│                                                          │
│   ⚠️ Encodable → [String: Any] → ParameterEncoding      │
│      (loses type safety)                                 │
└──────────────┬───────────────────────────────────────────┘
               │ conforms to URLRequestConvertible
               ▼
┌─────────────────────────────────────────────────────────┐
│ NetworkManager (struct, Sendable)                         │
│   session: Alamofire.Session                             │
│   decoder: JSONDecoder                                   │
│                                                          │
│   execute<T>(urlRequest:) async throws -> T              │
│   executeCompletable(urlRequest:) async throws           │
│   executeUpload<T>(urlRequest:, multipartFormData:)      │
│   executeUploadCompletable(urlRequest:, multipartFormData:)
│                                                          │
│   ⚠️ All 4 methods use withCheckedThrowingContinuation   │
│   ⚠️ All 4 methods duplicate error handling logic        │
└──────────────┬───────────────────────────────────────────┘
               │ throws
               ▼
┌─────────────────────────────────────────────────────────┐
│ NetworkError (enum)                                       │
│   .invalidURL                                            │
│   .requestFailed(Error, Data?)                           │
│   .decodingFailed(Error, Data?)                          │
│   .serverError(String, Data?)                            │
│   .noData                                                │
│   .unauthorized(Data?)                                   │
│   .unknown                                               │
│                                                          │
│   responseData: Data? (computed)                         │
└─────────────────────────────────────────────────────────┘
```

### 2.3 Request Flow

```
Consumer creates @ServiceWrapper / @ServiceWrapperWithRequest
    │
    ▼
wrappedValue → NetworkServiceProvider<R>
    │
    ▼
NetworkServiceProvider.asURLRequest()
    ├── Construct URL: baseUrl + "/" + path
    ├── Set HTTPMethod
    ├── data.asDictionary() → [String: Any]    ← TYPE ERASURE POINT
    └── encoding.encode(request, with: params) ← Alamofire ParameterEncoding
    │
    ▼
NetworkManager.execute(urlRequest:)
    │
    ▼
withCheckedThrowingContinuation { continuation in    ← UNNECESSARY BRIDGE
    session.request(urlRequest)
        .validate()
        .responseDecodable(of: T.self, decoder: decoder) { response in
            switch response.result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                // 4x DUPLICATED error mapping logic
                continuation.resume(throwing: NetworkError.xxx)
            }
        }
}
```

---

## 3. Issue Registry — Full Detail

### ISSUE-001: Duplicate `asDictionary()` Extension [MEDIUM]

**Files:**
- `NetworkServiceProvider.swift:13-16` (file-scoped, internal)
- `Encodable+dict.swift:12-21` (module-scoped, internal)

**What happens:**

Two separate `Encodable.asDictionary()` extensions exist:

```swift
// NetworkServiceProvider.swift:13 — returns Optional
extension Encodable {
    func asDictionary() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
    }
}

// Encodable+dict.swift:12 — returns non-Optional
extension Encodable {
    func asDictionary() -> Parameters {   // Parameters = [String: Any]
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            return try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                as? [String: Any & Sendable] ?? [:]
        } catch {
            return [:]
        }
    }
}
```

**Problems:**
1. **Different return types** — one returns `[String: Any]?`, the other returns `[String: Any]` (non-optional). Swift resolves this by context, but it's confusing.
2. **Different error handling** — one returns `nil` on failure, the other returns empty dict `[:]`.
3. **Which one gets called?** Depends on whether caller expects optional or non-optional. In `NetworkServiceProvider.params`:
   ```swift
   private var params: Parameters? {
       return data.asDictionary()  // Calls the [String: Any]? version? Or Parameters version?
   }
   ```
   Since `Parameters?` is `[String: Any]?`, Swift will prefer the Optional-returning version from the same file. But this is fragile — a refactor could change which overload resolves.

**Impact:** Subtle bugs if the wrong overload resolves, or if one is changed without updating the other.

---

### ISSUE-002: `withCheckedThrowingContinuation` is Unnecessary [MEDIUM]

**File:** `NetworkManager.swift:19-51, 53-83, 85-117, 119-151`
**Severity:** Medium
**Category:** Modernization

**What happens:**

All 4 methods use the callback-to-async bridge pattern:

```swift
public func execute<T: Decodable & Sendable>(
    urlRequest: URLRequestConvertible
) async throws -> T {
    return try await withCheckedThrowingContinuation { continuation in
        session.request(urlRequest)
            .validate()
            .responseDecodable(of: T.self, decoder: decoder) { response in
                // ...
                continuation.resume(returning/throwing: ...)
            }
    }
}
```

**Why it's unnecessary:**

Alamofire 5.7+ (2023) introduced native `async/await` support. The modern equivalent:

```swift
public func execute<T: Decodable & Sendable>(
    urlRequest: URLRequestConvertible
) async throws -> T {
    let response = await session.request(urlRequest)
        .validate()
        .serializingDecodable(T.self, decoder: decoder)
        .response

    switch response.result {
    case .success(let value):
        return value
    case .failure(let error):
        throw mapError(error, responseData: response.data)
    }
}
```

**Benefits of native async:**
- No continuation management (no risk of "continuation leaked" warnings)
- No nested closure scope — flatter, more readable code
- Alamofire handles cancellation properly with structured concurrency
- Better stack traces in crash reports (no continuation frame noise)

**Migration risk:** Low — same behavior, cleaner implementation.

---

### ISSUE-003: Protocol-Implementation Mismatch [LOW]

**Files:**
- `NetworkManagerProtocol.swift` — 3 methods
- `NetworkManager.swift` — 4 methods

**What happens:**

The protocol declares:
```swift
public protocol NetworkManagerProtocol: Sendable {
    func execute<T: Decodable>(urlRequest:) async throws -> T
    func executeCompletable(urlRequest:) async throws
    func executeUpload<T: Decodable & Sendable>(urlRequest:, multipartFormData:) async throws -> T
}
```

But `NetworkManager` also implements:
```swift
// NOT in protocol:
public func executeUploadCompletable(
    urlRequest: URLRequestConvertible,
    multipartFormData: @escaping (MultipartFormData) -> Void
) async throws
```

**Problems:**
1. `executeUploadCompletable` can't be called through the protocol — only through concrete `NetworkManager` type
2. If consumer codes against `NetworkManagerProtocol` (as they should for testability), upload-completable is invisible
3. Mock implementations won't need to implement it, creating behavior divergence

**Also:** `execute<T>` in protocol has `T: Decodable` but implementation has `T: Decodable & Sendable`. Protocol is less restrictive — a consumer could try to call with non-Sendable type through the protocol, getting a runtime surprise.

---

### ISSUE-004: Error Handling Copy-Paste x4 [MEDIUM]

**File:** `NetworkManager.swift`
**Severity:** Medium
**Category:** Maintainability

**What happens:**

The exact same error mapping logic is duplicated across all 4 methods:

```swift
// This block appears 4 TIMES (lines 32-48, 66-79, 100-113, 134-147):
if let afError = error.asAFError {
    switch afError {
    case .responseValidationFailed(let reason):
        if case .unacceptableStatusCode(let code) = reason, code == 401 {
            continuation.resume(throwing: NetworkError.unauthorized(response.data))
        } else {
            continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
        }
    case .responseSerializationFailed:
        continuation.resume(throwing: NetworkError.decodingFailed(error, response.data))
    default:
        continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
    }
} else {
    continuation.resume(throwing: NetworkError.requestFailed(error, response.data))
}
```

**Problems:**
1. **4x maintenance cost** — fixing a bug or adding a new error case requires changing 4 places
2. **Inconsistency risk** — one copy might get updated while others don't
3. **Note:** The `executeCompletable` and `executeUploadCompletable` versions don't handle `.responseSerializationFailed` (because there's no response body to decode), but the code still has the same structure. This could mask a real behavioral difference.

**Fix:** Extract to a single `private func mapError(_ error: AFError, responseData: Data?) -> NetworkError`.

---

### ISSUE-005: Encodable → [String: Any] Type Erasure [LOW]

**File:** `NetworkServiceProvider.swift:67-69`
**Severity:** Low
**Category:** Type Safety

**What happens:**

```swift
private var params: Parameters? {
    return data.asDictionary()  // Encodable → JSONEncoder → Data → JSONSerialization → [String: Any]
}
```

Then Alamofire re-encodes this dictionary:
```swift
return try encoding.encode(request, with: params)  // [String: Any] → JSON Data again
```

**The data goes through:**
```
Encodable struct
    → JSONEncoder.encode() → Data
        → JSONSerialization → [String: Any]  ← TYPE INFORMATION LOST
            → Alamofire ParameterEncoding → Data again
```

This is a round-trip through untyped dictionary. Problems:
1. **Nested Encodable types** may not survive the `JSONSerialization` round-trip correctly (e.g., `Date`, `URL`, custom encoding strategies are lost)
2. **Performance waste** — encode → decode → re-encode
3. **Alamofire has `ParameterEncoder`** (not `ParameterEncoding`) that accepts `Encodable` directly:
   ```swift
   // Modern Alamofire:
   session.request(url, method: method, parameters: data, encoder: JSONParameterEncoder.default)
   ```

**Why it exists:** The code was likely written before Alamofire added `ParameterEncoder`, or the author was more familiar with the older `ParameterEncoding` API.

**Migration risk:** Medium — changing encoding strategy could affect how edge cases (Dates, nested objects, arrays) are serialized. Needs testing.

---

### ISSUE-006: Utility Method Bloat in Encodable Extension [LOW]

**File:** `Encodable+dict.swift`
**Severity:** Low
**Category:** Maintainability

**What happens:**

Three methods that do essentially the same thing:

```swift
// Method 1: Encodable → Data?
var jsonData: Data? {
    let encoder = JSONEncoder()
    return try? encoder.encode(self)
}

// Method 2: Encodable → String?
var jsonString: String? {
    guard let data = self.jsonData else { return nil }
    return String(data: data, encoding: .utf8)
}

// Method 3: Encodable → Data? (duplicate of jsonData!)
func toJson() -> Data? {
    return try? JSONEncoder().encode(self)
}
```

`jsonData` and `toJson()` are **identical**. One should be removed.

`jsonString` is fine as a convenience but could be a one-liner: `String(data: try JSONEncoder().encode(self), encoding: .utf8)`.

**Plus** `asDictionary()` in this same file creates yet another representation of the same data.

---

### ISSUE-007: No Unit Tests [HIGH]

**Severity:** High
**Category:** Quality

The package has **zero tests**. No `Tests/` directory.

For a networking layer that every API call flows through, this means:
1. No regression safety on error mapping changes
2. No contract verification for `NetworkServiceProvider` URL construction
3. No validation that `asDictionary()` round-trip preserves data correctly
4. No mock-based testing of the `NetworkManagerProtocol`

---

### ISSUE-008: `NetworkError.localizedDescription` Shadows Protocol [LOW]

**File:** `NetworkError.swift:34-51`
**Severity:** Low
**Category:** Correctness

```swift
public var localizedDescription: String {
    switch self { ... }
}
```

This is a **computed property**, not a protocol conformance override. `Error` protocol's `localizedDescription` is defined in `NSError` bridging. This shadow works in Swift code but if `NetworkError` is ever bridged to Objective-C or used in `error.localizedDescription` context through the `Error` protocol (not the concrete type), the custom description may not be called.

**Fix:** Override properly or use a custom `description` property instead:
```swift
extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self { ... }
    }
}
```

---

## 4. Target Architecture

### 4.1 Architecture Diagram — After Refactor

```
┌─────────────────────────────────────────────────────────┐
│ Consumer                                                 │
│   @ServiceWrapper / @ServiceWrapperWithRequest           │
│   (unchanged API)                                        │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│ NetworkServiceProvider<R: Encodable & Sendable>           │
│                                                          │
│   🆕 Option A: Still URLRequestConvertible               │
│      (use ParameterEncoder instead of ParameterEncoding) │
│                                                          │
│   🆕 Option B: Direct Alamofire request params           │
│      (skip URLRequest building entirely)                 │
│                                                          │
│   🆕 Single asDictionary() — no duplicates               │
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│ NetworkManager (struct, Sendable)                         │
│                                                          │
│   🆕 Native Alamofire async/await (no continuation)      │
│   🆕 Single mapError() method (no duplication)           │
│   🆕 All methods in protocol                             │
│                                                          │
│   execute<T>(urlRequest:) async throws -> T              │
│   executeCompletable(urlRequest:) async throws           │
│   executeUpload<T>(urlRequest:, multipartFormData:)      │
│   executeUploadCompletable(urlRequest:, multipartFormData:)
└──────────────┬───────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────────┐
│ NetworkError: Error, LocalizedError                       │
│   🆕 Proper LocalizedError conformance                   │
│   responseData: Data? (unchanged)                        │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Files — After Refactor

```
Sources/EasyNet/
├── EasyNet.swift                          # Entry point (unchanged)
├── Manager/
│   ├── NetworkManager.swift               # 🔄 Refactored — native async, mapError()
│   ├── NetworkManagerProtocol.swift       # 🔄 Updated — all 4 methods
│   └── NetworkError.swift                 # 🔄 Updated — LocalizedError conformance
├── Providers/
│   └── NetworkServiceProvider.swift       # 🔄 Updated — remove duplicate extension
└── Utilities/
    ├── Extensions/
    │   └── Encodable+dict.swift           # 🔄 Cleaned — remove duplicates
    └── Wrappers/
        ├── ServiceWrapper.swift           # Unchanged
        ├── ServiceWrapperWithRequest.swift # Unchanged
        └── EmptyRequestContent.swift      # Unchanged

Tests/EasyNetTests/
├── 🆕 NetworkManagerTests.swift
├── 🆕 NetworkServiceProviderTests.swift
├── 🆕 NetworkErrorTests.swift
└── 🆕 EncodableExtensionTests.swift
```

---

## 5. Detailed Specifications per Goal

### G1: Replace withCheckedThrowingContinuation with Native Alamofire Async

**Goal:** Use Alamofire's built-in async/await support.

**Affected files:** `NetworkManager.swift`

**Current — `execute` (to be replaced):**
```swift
public func execute<T: Decodable & Sendable>(
    urlRequest: URLRequestConvertible
) async throws -> T {
    return try await withCheckedThrowingContinuation { continuation in
        session.request(urlRequest)
            .validate()
            .responseDecodable(of: T.self, decoder: decoder) { response in
                switch response.result {
                case .success(let globalResponse):
                    continuation.resume(returning: globalResponse)
                case .failure(let error):
                    // ... error mapping ...
                    continuation.resume(throwing: ...)
                }
            }
    }
}
```

**New — `execute`:**
```swift
public func execute<T: Decodable & Sendable>(
    urlRequest: URLRequestConvertible
) async throws -> T {
    let response = await session.request(urlRequest)
        .validate()
        .serializingDecodable(T.self, decoder: decoder)
        .response

    switch response.result {
    case .success(let value):
        return value
    case .failure(let error):
        throw Self.mapError(error, responseData: response.data)
    }
}
```

**New — `executeCompletable`:**
```swift
public func executeCompletable(
    urlRequest: URLRequestConvertible
) async throws {
    let response = await session.request(urlRequest)
        .validate()
        .serializingData()
        .response

    if let error = response.error {
        throw Self.mapError(error, responseData: response.data)
    }
}
```

**New — `executeUpload`:**
```swift
public func executeUpload<T: Decodable & Sendable>(
    urlRequest: URLRequestConvertible,
    multipartFormData: @escaping (MultipartFormData) -> Void
) async throws -> T {
    let response = await session.upload(
        multipartFormData: multipartFormData,
        with: urlRequest
    )
    .validate()
    .serializingDecodable(T.self, decoder: decoder)
    .response

    switch response.result {
    case .success(let value):
        return value
    case .failure(let error):
        throw Self.mapError(error, responseData: response.data)
    }
}
```

**New — `executeUploadCompletable`:**
```swift
public func executeUploadCompletable(
    urlRequest: URLRequestConvertible,
    multipartFormData: @escaping (MultipartFormData) -> Void
) async throws {
    let response = await session.upload(
        multipartFormData: multipartFormData,
        with: urlRequest
    )
    .validate()
    .serializingData()
    .response

    if let error = response.error {
        throw Self.mapError(error, responseData: response.data)
    }
}
```

**Edge cases:**

| Scenario | Current Behavior | New Behavior |
|----------|-----------------|--------------|
| Request cancelled | Continuation may leak warning | Alamofire throws `AFError.explicitlyCancelled` — clean |
| Timeout | Error via callback | Same error via async |
| 401 response | Detected in error mapping | Same detection in `mapError` |
| Empty response body | `executeCompletable` succeeds | Same — `serializingData()` accepts empty |

**Acceptance criteria:**
- [ ] Zero `withCheckedThrowingContinuation` in codebase
- [ ] All 4 methods use Alamofire native async
- [ ] Error mapping produces identical `NetworkError` cases
- [ ] Cancellation works correctly with structured concurrency
- [ ] centauri-ios network calls work identically

---

### G2: Extract Error Mapping to Single Method

**Goal:** Eliminate 4x copy-pasted error handling.

**Affected files:** `NetworkManager.swift`

**New method:**
```swift
extension NetworkManager {
    /// Maps Alamofire errors to EasyNet NetworkError types.
    /// Single source of truth for all error mapping.
    static func mapError(_ error: AFError, responseData: Data?) -> NetworkError {
        switch error {
        case .responseValidationFailed(let reason):
            if case .unacceptableStatusCode(let code) = reason, code == 401 {
                return .unauthorized(responseData)
            }
            return .requestFailed(error, responseData)

        case .responseSerializationFailed:
            return .decodingFailed(error, responseData)

        default:
            return .requestFailed(error, responseData)
        }
    }
}
```

**Usage in all methods:**
```swift
case .failure(let error):
    throw Self.mapError(error, responseData: response.data)
```

**Extended error mapping (recommended additions):**
```swift
static func mapError(_ error: AFError, responseData: Data?) -> NetworkError {
    switch error {
    case .responseValidationFailed(let reason):
        if case .unacceptableStatusCode(let code) = reason {
            switch code {
            case 401:
                return .unauthorized(responseData)
            case 500...599:
                return .serverError("HTTP \(code)", responseData)
            default:
                return .requestFailed(error, responseData)
            }
        }
        return .requestFailed(error, responseData)

    case .responseSerializationFailed:
        return .decodingFailed(error, responseData)

    case .sessionTaskFailed(let urlError as URLError) where urlError.code == .notConnectedToInternet:
        return .requestFailed(error, responseData)

    case .explicitlyCancelled:
        return .requestFailed(error, responseData)

    default:
        return .requestFailed(error, responseData)
    }
}
```

> **Note:** The extended mapping is optional. The minimal version just extracts the existing logic. New error cases (like `.notConnectedToInternet`) are a separate enhancement.

**Acceptance criteria:**
- [ ] Error mapping logic exists in exactly ONE place
- [ ] All 4 execute methods call `mapError()`
- [ ] 401 → `.unauthorized` mapping preserved
- [ ] Decoding errors → `.decodingFailed` mapping preserved
- [ ] All other errors → `.requestFailed` mapping preserved

---

### G3: Fix Protocol-Implementation Mismatch

**Goal:** All public methods of `NetworkManager` are in the protocol.

**Affected files:** `NetworkManagerProtocol.swift`

**Current protocol (3 methods):**
```swift
public protocol NetworkManagerProtocol: Sendable {
    func execute<T: Decodable>(urlRequest: URLRequestConvertible) async throws -> T
    func executeCompletable(urlRequest: URLRequestConvertible) async throws
    func executeUpload<T: Decodable & Sendable>(urlRequest: URLRequestConvertible, multipartFormData: @escaping (MultipartFormData) -> Void) async throws -> T
}
```

**New protocol (4 methods + Sendable alignment):**
```swift
public protocol NetworkManagerProtocol: Sendable {
    func execute<T: Decodable & Sendable>(
        urlRequest: URLRequestConvertible
    ) async throws -> T

    func executeCompletable(
        urlRequest: URLRequestConvertible
    ) async throws

    func executeUpload<T: Decodable & Sendable>(
        urlRequest: URLRequestConvertible,
        multipartFormData: @escaping @Sendable (MultipartFormData) -> Void
    ) async throws -> T

    func executeUploadCompletable(
        urlRequest: URLRequestConvertible,
        multipartFormData: @escaping @Sendable (MultipartFormData) -> Void
    ) async throws
}
```

**Changes:**
1. Added `executeUploadCompletable` to protocol
2. Added `& Sendable` to `execute<T>` generic constraint (matches implementation)
3. Added `@Sendable` to `multipartFormData` closure (strict concurrency)

**Acceptance criteria:**
- [ ] Protocol has all 4 methods
- [ ] Generic constraints match between protocol and implementation
- [ ] Mock implementations compile when conforming to protocol
- [ ] centauri-ios `AppNetworkProtocol` works without changes

---

### G4: Remove Duplicate `asDictionary()` Extension

**Goal:** Single, canonical `Encodable.asDictionary()` method.

**Affected files:** `NetworkServiceProvider.swift`, `Encodable+dict.swift`

**Remove from `NetworkServiceProvider.swift` (lines 12-17):**
```swift
// DELETE THIS:
extension Encodable {
    func asDictionary() -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
    }
}
```

**Keep and clean up `Encodable+dict.swift`:**
```swift
import Foundation
import Alamofire

extension Encodable {
    /// Converts Encodable to dictionary for Alamofire ParameterEncoding.
    /// Returns empty dictionary on encoding failure.
    func asDictionary() -> Parameters {
        do {
            let data = try JSONEncoder().encode(self)
            return try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                as? [String: Any] ?? [:]
        } catch {
            return [:]
        }
    }

    /// Encodes to JSON Data.
    var jsonData: Data? {
        try? JSONEncoder().encode(self)
    }
}
```

**Remove `toJson()` and `jsonString`:**
- `toJson()` is identical to `jsonData` — remove it
- `jsonString` is unused and trivially derivable — remove it

> **Note:** If `jsonString` or `toJson()` are used by centauri-ios outside of EasyNet, they should stay. Check before removing.

**Acceptance criteria:**
- [ ] `asDictionary()` defined exactly once in entire package
- [ ] `toJson()` removed (duplicate of `jsonData`)
- [ ] No compilation errors in `NetworkServiceProvider.params`
- [ ] centauri-ios compiles without changes (or with trivial renames)

---

### G5: Fix LocalizedError Conformance

**Goal:** `NetworkError` properly conforms to `LocalizedError`.

**Affected files:** `NetworkError.swift`

**Current (shadow, not override):**
```swift
public enum NetworkError: Error {
    // cases...

    public var localizedDescription: String {
        switch self { ... }
    }
}
```

**New (proper conformance):**
```swift
public enum NetworkError: Error {
    case invalidURL
    case requestFailed(Error, Data? = nil)
    case decodingFailed(Error, Data? = nil)
    case serverError(String, Data? = nil)
    case noData
    case unauthorized(Data? = nil)
    case unknown

    public var responseData: Data? {
        switch self {
        case .requestFailed(_, let data): return data
        case .decodingFailed(_, let data): return data
        case .serverError(_, let data): return data
        case .unauthorized(let data): return data
        default: return nil
        }
    }
}

extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed(let error, _):
            return "Request failed: \(error.localizedDescription)"
        case .decodingFailed(let error, _):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let message, _):
            return "Server error: \(message)"
        case .noData:
            return "No data received from server"
        case .unauthorized:
            return "Unauthorized access"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
```

**Difference:** `LocalizedError.errorDescription` is the proper protocol requirement. `localizedDescription` on `Error` is a computed property that reads from `errorDescription` when `LocalizedError` is conformed. The current implementation bypasses this chain.

**Acceptance criteria:**
- [ ] `NetworkError` conforms to `LocalizedError`
- [ ] `error.localizedDescription` works correctly through `Error` protocol reference
- [ ] No duplicate `localizedDescription` property

---

### G6: Unit Tests

**Goal:** Test coverage for core functionality.

**New directory:** `Tests/EasyNetTests/`

#### NetworkManagerTests.swift
```swift
final class NetworkManagerTests: XCTestCase {

    // MARK: - Error Mapping

    func test_mapError_401_returnsUnauthorized() {
        let error = AFError.responseValidationFailed(
            reason: .unacceptableStatusCode(code: 401)
        )
        let result = NetworkManager.mapError(error, responseData: nil)
        if case .unauthorized = result {
            // pass
        } else {
            XCTFail("Expected .unauthorized, got \(result)")
        }
    }

    func test_mapError_serializationFailed_returnsDecodingFailed() { ... }

    func test_mapError_otherError_returnsRequestFailed() { ... }

    func test_mapError_preservesResponseData() { ... }
}
```

#### NetworkServiceProviderTests.swift
```swift
final class NetworkServiceProviderTests: XCTestCase {

    func test_asURLRequest_getMethod_usesQueryEncoding() { ... }

    func test_asURLRequest_postMethod_usesJSONEncoding() { ... }

    func test_asURLRequest_constructsCorrectURL() {
        let provider = NetworkServiceProvider(
            baseUrl: "https://api.example.com/",
            path: "/users/",
            method: .get,
            data: EmptyRequestContent()
        )
        let request = try provider.asURLRequest()
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/users")
    }

    func test_asURLRequest_handlesTrailingSlashes() { ... }

    func test_asURLRequest_encodesBodyForPost() { ... }
}
```

#### NetworkErrorTests.swift
```swift
final class NetworkErrorTests: XCTestCase {

    func test_responseData_returnsDataForRequestFailed() { ... }

    func test_responseData_returnsNilForInvalidURL() { ... }

    func test_localizedDescription_throughErrorProtocol() {
        let error: Error = NetworkError.unauthorized(nil)
        XCTAssertEqual(error.localizedDescription, "Unauthorized access")
    }
}
```

#### EncodableExtensionTests.swift
```swift
final class EncodableExtensionTests: XCTestCase {

    struct TestModel: Encodable {
        let name: String
        let age: Int
    }

    func test_asDictionary_preservesValues() {
        let model = TestModel(name: "Test", age: 25)
        let dict = model.asDictionary()
        XCTAssertEqual(dict["name"] as? String, "Test")
        XCTAssertEqual(dict["age"] as? Int, 25)
    }

    func test_asDictionary_nestedObjects() { ... }

    func test_jsonData_encodesCorrectly() { ... }
}
```

**Acceptance criteria:**
- [ ] Tests directory exists with 4 test files
- [ ] `mapError()` has tests for each `NetworkError` case
- [ ] `NetworkServiceProvider.asURLRequest()` URL construction tested
- [ ] `swift test` passes
- [ ] Tests run in < 3 seconds

---

## 6. Dependency Graph

```
G4 (Remove duplicate asDictionary)
G5 (LocalizedError)                    ── Independent, no deps ──
G3 (Protocol mismatch)

     │ all independent
     ▼

G2 (Extract mapError) ◄── MUST be done before or with G1
     │
     ▼
G1 (Native Alamofire async) ── depends on G2 (uses mapError)
     │
     ▼
G6 (Unit Tests) ── must be last, tests validate everything
```

**Execution order:**

1. **G4** — Remove duplicate `asDictionary()` (trivial)
2. **G5** — Fix `LocalizedError` (trivial)
3. **G3** — Fix protocol (trivial)
4. **G2** — Extract `mapError()` (small)
5. **G1** — Native async (medium — uses `mapError()` from G2)
6. **G6** — Tests (validates all above)

---

## 7. Migration Plan & Phases

### Phase 1 — Quick Wins (v1.1.0) — No API Breaking Changes

**Scope:** Internal cleanup, no public API changes.
**Effort:** ~2 hours
**Risk:** Low

| Step | Task | Files Changed | Effort |
|------|------|---------------|--------|
| 1.1 | Remove duplicate `asDictionary()` from NetworkServiceProvider | NetworkServiceProvider.swift | 5min |
| 1.2 | Remove `toJson()` duplicate | Encodable+dict.swift | 5min |
| 1.3 | Fix `LocalizedError` conformance | NetworkError.swift | 10min |
| 1.4 | Add `executeUploadCompletable` to protocol | NetworkManagerProtocol.swift | 5min |
| 1.5 | Align `Sendable` constraints in protocol | NetworkManagerProtocol.swift | 5min |
| 1.6 | Extract `mapError()` from 4 methods | NetworkManager.swift | 20min |
| 1.7 | Compile + test with centauri-ios | — | 30min |

**Deliverable:** Branch `fix/phase-1-cleanup`, PR to main.

### Phase 2 — Modernization (v2.0.0) — Internal Breaking Change

**Scope:** Replace continuation bridge with native async. Public API unchanged but internal behavior slightly different (cancellation semantics).
**Effort:** ~3 hours
**Risk:** Medium

| Step | Task | Files Changed | Effort |
|------|------|---------------|--------|
| 2.1 | Replace all 4 methods with native Alamofire async | NetworkManager.swift | 1h |
| 2.2 | Remove `withCheckedThrowingContinuation` entirely | NetworkManager.swift | included above |
| 2.3 | Write unit tests | +4 test files | 1.5h |
| 2.4 | Integration test with centauri-ios | — | 30min |

**Deliverable:** Branch `refactor/v2.0-native-async`, PR to main.

### Phase 3 — Type Safety (v2.1.0) — Optional, Needs Investigation

**Scope:** Replace `Encodable → [String: Any] → ParameterEncoding` with direct `ParameterEncoder`.
**Effort:** ~4 hours
**Risk:** Medium-High (encoding behavior may differ for edge cases)

| Step | Task | Files Changed | Effort |
|------|------|---------------|--------|
| 3.1 | Replace `ParameterEncoding` with `ParameterEncoder` | NetworkServiceProvider.swift | 2h |
| 3.2 | Test all API endpoints for encoding correctness | — | 2h |

> **Decision point:** This phase changes how request bodies are encoded. Needs thorough testing with actual backend endpoints to verify no regression.

**Deliverable:** Branch `refactor/v2.1-type-safe-encoding`, PR to main.

---

## 8. Testing Strategy

### 8.1 Unit Tests

See G6 specification above. Tests cover:
- Error mapping (`mapError` → `NetworkError`)
- URL construction (`NetworkServiceProvider.asURLRequest()`)
- Error conformance (`LocalizedError`)
- Encodable extensions (`asDictionary`, `jsonData`)

### 8.2 Integration Testing with centauri-ios

After each phase, verify with the actual app:

| Test Case | Endpoint | Expected |
|-----------|----------|----------|
| Login | `POST auth/login` | Token returned, stored in Keychain |
| OTP validation | `POST otp/validate` | Success/error handled correctly |
| Token refresh | `POST auth/refresh` | New tokens stored, original request retried |
| GET request | `GET test/list` | Decoded response matches DTO |
| 401 flow | Any endpoint with expired token | Auto-refresh + retry |
| Network error | Kill server | `NetworkError.requestFailed` thrown |
| Decoding error | Mismatched DTO | `NetworkError.decodingFailed` thrown |

### 8.3 Cancellation Testing (Phase 2 specific)

Native Alamofire async supports `Task` cancellation. Verify:
- Cancelling a `Task` that wraps a network call properly cancels the Alamofire request
- No "continuation leaked" warnings in console

---

## 9. Versioning & Release Strategy

| Version | Contains | Breaking | Release Type |
|---------|----------|----------|--------------|
| **1.1.0** | Phase 1 (cleanup, mapError, protocol fix) | No | Minor — safe for all consumers |
| **2.0.0** | Phase 2 (native async, tests) | Technically yes (cancellation semantics) | Major — cautious |
| **2.1.0** | Phase 3 (ParameterEncoder) | Potentially (encoding behavior) | Minor or Major |

**Recommended approach:**
1. Ship **1.1.0** immediately — zero risk
2. Ship **2.0.0** after testing async behavior with centauri-ios
3. Ship **2.1.0** only after thorough backend endpoint testing

---

## 10. Risk Analysis

### Phase 1 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Removing duplicate `asDictionary` changes which overload resolves | Low | Medium | Test URL construction explicitly |
| `LocalizedError` change affects error display in UI | Very Low | Low | Error messages are the same strings |
| Protocol change breaks centauri-ios compilation | Very Low | Low | Only adds methods, doesn't change existing |

### Phase 2 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Native async has different cancellation behavior | Medium | Medium | Test cancel scenarios explicitly |
| `serializingDecodable` vs `responseDecodable` decoding difference | Low | High | Same decoder, same type — should be identical |
| BearerInterceptor retry interacts differently with async | Low | High | Test 401 flow end-to-end |

### Phase 3 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| `ParameterEncoder` encodes differently than `ParameterEncoding` for edge cases | Medium | High | Test every endpoint with actual backend |
| Date/URL encoding strategy changes | Medium | Medium | Ensure JSONEncoder config matches |

### Rollback Plan

Each phase is a separate branch/PR. If issues found:
1. Revert PR
2. Pin centauri-ios to previous EasyNet version
3. Fix and re-release

---

## 11. Success Criteria

### Phase 1 Complete When:
- [ ] Zero duplicate `asDictionary()` extensions
- [ ] Zero duplicate utility methods (`toJson` removed)
- [ ] `NetworkError` conforms to `LocalizedError`
- [ ] Protocol has all 4 methods with matching constraints
- [ ] `mapError()` exists as single method, called from all execute methods
- [ ] centauri-ios compiles and all API calls work

### Phase 2 Complete When:
- [ ] Zero `withCheckedThrowingContinuation` in codebase
- [ ] All methods use Alamofire native async/await
- [ ] `swift test` passes with unit tests
- [ ] Task cancellation properly cancels Alamofire requests
- [ ] centauri-ios 401 flow works correctly
- [ ] No "continuation leaked" warnings

### Overall v2.0.0 Complete When:
All Phase 1 + Phase 2 criteria met, plus:
- [ ] Git tag `v2.0.0` created
- [ ] centauri-ios updated and verified on device

---

## 12. Open Questions

| # | Question | Needs Answer From | Blocks |
|---|----------|-------------------|--------|
| **OQ-1** | Are `jsonString` or `toJson()` used anywhere in centauri-ios outside of EasyNet? | Code search | G4 removal |
| **OQ-2** | Should we move to `ParameterEncoder` in Phase 3? Risk of encoding behavior change. | Team | Phase 3 |
| **OQ-3** | Is `EmptyRequestContent` needed? Could use `Never` or remove body entirely for GET requests. | Team | Future cleanup |
| **OQ-4** | Should `NetworkError` add more cases? (e.g., `.noInternet`, `.timeout`, `.cancelled`) | Product | Future enhancement |
| **OQ-5** | Should `NetworkManager` support request/response middleware? (logging, metrics, etc.) | Team | Future architecture |

---

## 13. Appendix

### A. Full File Diff Summary

| File | Phase 1 | Phase 2 | Phase 3 |
|------|---------|---------|---------|
| `NetworkManager.swift` | Extract `mapError()` | Replace with native async | — |
| `NetworkManagerProtocol.swift` | Add missing method, fix constraints | — | — |
| `NetworkError.swift` | `LocalizedError` conformance | — | — |
| `NetworkServiceProvider.swift` | Remove duplicate extension | — | `ParameterEncoder` |
| `Encodable+dict.swift` | Remove `toJson()`, clean up | — | May simplify |
| `Tests/*` | — | Add 4 test files | — |

### B. Public API Changes (v1.0.1 → v2.0.0)

**Added to protocol:**
- `NetworkManagerProtocol.executeUploadCompletable(urlRequest:multipartFormData:)`

**Changed:**
- `NetworkError` now conforms to `LocalizedError` (additive, non-breaking)
- `execute<T>` protocol constraint: `T: Decodable` → `T: Decodable & Sendable` (tightening, potentially breaking for consumers using non-Sendable Decodable types)

**Removed:**
- `toJson()` extension on `Encodable` (if unused in consumers)
- `jsonString` extension on `Encodable` (if unused in consumers)
- Duplicate `asDictionary()` from `NetworkServiceProvider.swift` (internal, non-breaking)

**Unchanged:**
- `NetworkManager` public API (all 4 methods)
- `@ServiceWrapper` / `@ServiceWrapperWithRequest` API
- `NetworkServiceProvider` public API
- `NetworkError` cases and `responseData` property
- `EmptyRequestContent`

### C. Alamofire Native Async Reference

```swift
// Alamofire 5.7+ async API:
let value = try await session.request(urlRequest)
    .validate()
    .serializingDecodable(MyType.self)
    .value  // throws on failure

// Or with full response access:
let response = await session.request(urlRequest)
    .validate()
    .serializingDecodable(MyType.self)
    .response  // DataResponse<MyType, AFError>
```

- [Alamofire Concurrency docs](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#using-alamofire-with-swift-concurrency)
- [serializingDecodable API](https://alamofire.github.io/Alamofire/Classes/DataRequest.html#/s:9Alamofire11DataRequestC21serializingDecodable_10automaticallyCancelling7decoder12emptyResponseCodes0M7Methods0lM16RequestBehaviorAA20DataResponseSerializerVyxGxm_SbAA15DataDecoder_pSaySiGSayAA10HTTPMethodOGAA05EmptyjK0OtSeRzlF)
