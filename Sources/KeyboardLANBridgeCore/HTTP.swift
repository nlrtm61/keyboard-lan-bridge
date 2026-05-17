import Foundation

public struct HTTPRequest {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public func header(named name: String) -> String? {
        headers[name.lowercased()]
    }
}

public struct HTTPResponse {
    public let statusCode: Int
    public let reasonPhrase: String
    public let headers: [String: String]
    public let body: Data

    public func serialized() -> Data {
        var response = "HTTP/1.1 \(statusCode) \(reasonPhrase)\r\n"
        for key in headers.keys.sorted() {
            if let value = headers[key] {
                response += "\(key): \(value)\r\n"
            }
        }
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"

        var data = Data(response.utf8)
        data.append(body)
        return data
    }

    public static func json(statusCode: Int, object: [String: Any]) -> HTTPResponse {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return HTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase(for: statusCode),
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: body
        )
    }

    public static func text(statusCode: Int, message: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            reasonPhrase: reasonPhrase(for: statusCode),
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(message.utf8)
        )
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 202: return "Accepted"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 413: return "Payload Too Large"
        case 422: return "Unprocessable Entity"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}

public enum HTTPParserError: Error, CustomStringConvertible {
    case invalidStartLine
    case invalidHeader
    case invalidEncoding
    case invalidContentLength

    public var description: String {
        switch self {
        case .invalidStartLine:
            return "invalid HTTP request line"
        case .invalidHeader:
            return "invalid HTTP header"
        case .invalidEncoding:
            return "invalid request encoding"
        case .invalidContentLength:
            return "invalid content-length header"
        }
    }
}

public enum HTTPParseResult {
    case incomplete
    case complete(HTTPRequest, consumedBytes: Int)
}

public enum HTTPParser {
    public static func parse(data: Data, maxBodyBytes: Int = 16 * 1024) throws -> HTTPParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            return .incomplete
        }

        let headersData = data.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headersData, encoding: .utf8) else {
            throw HTTPParserError.invalidEncoding
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let startLine = lines.first else {
            throw HTTPParserError.invalidStartLine
        }

        let startComponents = startLine.split(separator: " ")
        guard startComponents.count >= 2 else {
            throw HTTPParserError.invalidStartLine
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let separatorIndex = line.firstIndex(of: ":") else {
                throw HTTPParserError.invalidHeader
            }
            let name = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength: Int
        if let rawValue = headers["content-length"] {
            guard let parsed = Int(rawValue), parsed >= 0 else {
                throw HTTPParserError.invalidContentLength
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }

        if contentLength > maxBodyBytes {
            return .complete(
                HTTPRequest(
                    method: String(startComponents[0]),
                    path: String(startComponents[1]),
                    headers: headers,
                    body: Data()
                ),
                consumedBytes: Int.max
            )
        }

        let bodyOffset = headerRange.upperBound
        let expectedBytes = bodyOffset + contentLength
        guard data.count >= expectedBytes else {
            return .incomplete
        }

        let body = data.subdata(in: bodyOffset..<expectedBytes)
        let request = HTTPRequest(
            method: String(startComponents[0]),
            path: String(startComponents[1]),
            headers: headers,
            body: body
        )
        return .complete(request, consumedBytes: expectedBytes)
    }
}
