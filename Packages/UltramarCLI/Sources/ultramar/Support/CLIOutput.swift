import Foundation

enum CLIOutput {
    static func print(_ fields: [String: JSONValue], format: OutputFormatOption) {
        switch format {
        case .text:
            for (key, value) in fields.sorted(by: { $0.key < $1.key }) {
                Swift.print("\(key): \(value.textRepresentation)")
            }
        case .json:
            let object = fields.mapValues(\.jsonObject)
            let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            Swift.print(String(data: data, encoding: .utf8)!)
        }
    }

    static func printEncodable(_ fields: [String: any Encodable], format: OutputFormatOption) {
        print(fields.mapValues { JSONValue.encodable($0) }, format: format)
    }

    static func printText(_ message: String, format: OutputFormatOption) {
        print(["message": .string(message)], format: format)
    }

    static func printError(
        _ message: String,
        hint: String? = nil,
        format: OutputFormatOption
    ) -> Never {
        switch format {
        case .text:
            fputs("Error: \(message)\n", stderr)
            if let hint {
                fputs("  \(hint)\n", stderr)
            }
        case .json:
            var payload: [String: JSONValue] = [
                "ok": .bool(false),
                "error": .string(message),
            ]
            if let hint { payload["hint"] = .string(hint) }
            let object = payload.mapValues(\.jsonObject)
            let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            fputs(String(data: data, encoding: .utf8)! + "\n", stderr)
        }
        Foundation.exit(1)
    }
}

enum JSONValue: Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case int64(Int64)
    case double(Double)
    case array([JSONValue])
    case object([String: JSONValue])

    var textRepresentation: String {
        switch self {
        case .string(let value):
            value
        case .bool(let value):
            value ? "true" : "false"
        case .int(let value):
            String(value)
        case .int64(let value):
            String(value)
        case .double(let value):
            String(value)
        case .array(let values):
            values.map(\.textRepresentation).joined(separator: ", ")
        case .object(let values):
            String(data: (try? JSONSerialization.data(withJSONObject: values.mapValues(\.jsonObject))) ?? Data(), encoding: .utf8) ?? "{}"
        }
    }

    var jsonObject: Any {
        switch self {
        case .string(let value):
            value
        case .bool(let value):
            value
        case .int(let value):
            value
        case .int64(let value):
            value
        case .double(let value):
            value
        case .array(let values):
            values.map(\.jsonObject)
        case .object(let values):
            values.mapValues(\.jsonObject)
        }
    }

    static func encodable(_ value: any Encodable) -> JSONValue {
        if let string = value as? String { return .string(string) }
        if let bool = value as? Bool { return .bool(bool) }
        if let int = value as? Int { return .int(int) }
        if let int64 = value as? Int64 { return .int64(int64) }
        if let double = value as? Double { return .double(double) }
        return .string(String(describing: value))
    }
}
