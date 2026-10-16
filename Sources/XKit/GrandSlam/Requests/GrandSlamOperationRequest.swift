//
//  GrandSlamOperationRequest.swift
//  XKit
//
//  Created by Kabir Oberai on 19/11/19.
//  Copyright © 2019 Kabir Oberai. All rights reserved.
//

import Foundation

struct GrandSlamOperationError: Error, LocalizedError {
    let code: Int
    let message: String

    var errorDescription: String? {
        "\(message) (\(code))"
    }
}

/// GSA wants us to resync Anisette (`hsc` 434) using the attached server intermediate metadata.
struct GrandSlamAnisetteResyncRequired: Error, LocalizedError {
    let sim: Data

    var errorDescription: String? {
        "Apple requested an Anisette resync, but it didn't take effect. Please try logging in again."
    }
}

struct GrandSlamOperationResponseStatusWrapper: Decodable {
    struct Status: Decodable {
        let errorCode: Int
        let errorMessage: String
        let httpStatusCode: Int?
        let authMode: String?
        let resyncSIM: Data?

        private enum CodingKeys: String, CodingKey {
            case errorCode = "ec"
            case errorMessage = "em"
            case httpStatusCode = "hsc"
            case authMode = "au"
            case resyncSIM = "X-Apple-I-MD-DATA"
        }

        init(from decoder: any Swift.Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            errorCode = try container.decode(Int.self, forKey: .errorCode)
            errorMessage = try container.decode(String.self, forKey: .errorMessage)
            httpStatusCode = try container.decodeIfPresent(Int.self, forKey: .httpStatusCode)
            authMode = try container.decodeIfPresent(String.self, forKey: .authMode)
            resyncSIM = container.decodeResyncSIM(forKey: .resyncSIM)
        }
    }
    let status: Status
    /// Some responses carry `X-Apple-I-MD-DATA` alongside `Status` rather than inside it.
    let resyncSIM: Data?

    private enum CodingKeys: String, CodingKey {
        case status = "Status"
        case resyncSIM = "X-Apple-I-MD-DATA"
    }

    init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(Status.self, forKey: .status)
        resyncSIM = container.decodeResyncSIM(forKey: .resyncSIM)
    }
}

extension KeyedDecodingContainer {
    /// `X-Apple-I-MD-DATA` may be sent either as <data> or as a base64 <string>.
    fileprivate func decodeResyncSIM(forKey key: Key) -> Data? {
        if let data = try? decodeIfPresent(Data.self, forKey: key) {
            return data
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Data(base64Encoded: string)
        }
        return nil
    }
}

struct GrandSlamOperationResponseWrapper<T: Decodable>: Decodable {
    let value: T
    private enum CodingKeys: String, CodingKey {
        case value = "Response"
    }
}

struct GrandSlamOperationDecoder<T: Decodable>: GrandSlamDataDecoder {
    static func decode(data: Data) throws -> T {
        let decoder = PropertyListDecoder()
        let response = try decoder.decode(
            GrandSlamOperationResponseWrapper<GrandSlamOperationResponseStatusWrapper>.self,
            from: data
        ).value
        let status = response.status
        if status.httpStatusCode == 434, let sim = status.resyncSIM ?? response.resyncSIM {
            throw GrandSlamAnisetteResyncRequired(sim: sim)
        }
        guard status.errorCode == 0 else {
            throw GrandSlamOperationError(code: status.errorCode, message: status.errorMessage)
        }
        return try decoder.decode(GrandSlamOperationResponseWrapper<T>.self, from: data).value
    }
}

protocol GrandSlamOperationRequest: GrandSlamRequest
    where Decoder == GrandSlamOperationDecoder<Value> {
    associatedtype Value: Decodable

    static var operation: String { get }

    var username: String { get }
    var parameters: [String: Any] { get }
}

extension GrandSlamOperationRequest {

    static var endpoint: GrandSlamEndpoint { .lookup(\.gsService) }

    func configure(request: inout HTTPRequest, deviceInfo: DeviceInfo, anisetteData: AnisetteData) {
        request.headerFields[.accept] = "*/*"
        request.headerFields[.userAgent] = deviceInfo.clientInfo.userAgent
    }

    func method(deviceInfo: DeviceInfo, anisetteData: AnisetteData) -> GrandSlamMethod {
        var clientData: [String: Any] = [
            "bootstrap": true,
            "icscrec": true,
            "pbe": false,
            "prkgen": true,
            "svct": "iCloud",
            "loc": Locale.current.identifier
        ]
        // Don't include deviceInfo.dictionary: its Mac hardware identifiers (ROM/MLB/serial)
        // contradict the Android client info and Anisette data.
        clientData.merge(anisetteData.dictionary) { _, b in b }

        var request: [String: Any] = [
            "o": Self.operation,
            "u": username,
            "cpd": clientData
        ]
        request.merge(parameters) { _, b in b }

        let body = [
            "Header": ["Version": "1.0.1"],
            "Request": request
        ]
        return .post(body)
    }

}
