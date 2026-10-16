//
//  AnisetteDataProvider.swift
//  XKit
//
//  Created by Kabir Oberai on 19/11/19.
//  Copyright © 2019 Kabir Oberai. All rights reserved.
//

import Foundation
import Dependencies

public protocol AnisetteDataProvider: Sendable {
    /// Stored alongside login data. If the provider reports a new ID, we log out.
    /// 
    /// This is useful when switching Anisette provider implementations if the old
    /// implementation's provisioning data won't work with the new implementation.
    ///
    /// The default implementation returns `nil`.
    var providerID: String? { get }

    // This is a suggestion and not a requirement.
    func resetProvisioning() async
    func provisioningData() -> ProvisioningData?

    func fetchAnisetteData() async throws -> AnisetteData

    /// Called when GSA asks for an Anisette resync (`hsc` 434), passing the server
    /// intermediate metadata it sent (`X-Apple-I-MD-DATA`). Returns corrected data.
    ///
    /// The default implementation resets provisioning and fetches fresh data.
    func resync(sim: Data) async throws -> AnisetteData
}

public struct ProvisioningData: Hashable, Codable, Sendable {
    public var localUserUID: UUID
    public var routingInfo: UInt64
    public var adiPb: Data
}

extension AnisetteDataProvider {
    public var providerID: String? { nil }
    public func provisioningData() -> ProvisioningData? { nil }
    public func resetProvisioning() async {}

    public func resync(sim: Data) async throws -> AnisetteData {
        await resetProvisioning()
        return try await fetchAnisetteData()
    }
}

extension DependencyValues {
    public var anisetteDataProvider: AnisetteDataProvider {
        get { self[AnisetteDataProviderDependencyKey.self] }
        set { self[AnisetteDataProviderDependencyKey.self] = newValue }
    }
}

private struct AnisetteDataProviderDependencyKey: DependencyKey {
    static let testValue: AnisetteDataProvider = UnimplementedAnisetteDataProvider()
    static let liveValue: AnisetteDataProvider = ADIDataProvider()
}

private struct UnimplementedAnisetteDataProvider: AnisetteDataProvider {
    func fetchAnisetteData() async throws -> AnisetteData {
        let closure: () async throws -> AnisetteData = unimplemented()
        return try await closure()
    }
}
