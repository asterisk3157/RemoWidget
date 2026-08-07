import Foundation

// MARK: - API レスポンス型
// 実機レスポンスに基づく（DEVICE-PROFILE.md 参照）。
// JSONDecoder は .convertFromSnakeCase / .iso8601 前提。

public struct Appliance: Codable, Sendable {
    public let id: String
    public let type: String          // "AC" / "LIGHT" / ...
    public let nickname: String
    public let settings: AirconSettings?
    public let aircon: Aircon?
    public let light: Light?
}

public struct AirconSettings: Codable, Sendable, Equatable {
    public var temp: String          // "22" / "22.5"、blow モードでは ""
    public var mode: String          // cool / warm / dry / blow / auto
    public var vol: String           // "1"..."4" / "auto" / ""
    public var dir: String
    public var dirh: String?
    public var button: String        // "" = 運転中 / "power-off" = 停止
    public var tempUnit: String?

    public var isOn: Bool { button != "power-off" }

    public init(temp: String, mode: String, vol: String, dir: String,
                dirh: String? = nil, button: String, tempUnit: String? = nil) {
        self.temp = temp; self.mode = mode; self.vol = vol
        self.dir = dir; self.dirh = dirh; self.button = button; self.tempUnit = tempUnit
    }
}

public struct Aircon: Codable, Sendable {
    public let range: AirconRange
    public let tempUnit: String?
}

public struct AirconRange: Codable, Sendable {
    /// キーは "cool" / "warm" / "dry" / "blow" / "auto"。機種により欠けうる。
    public let modes: [String: ModeRange]
}

public struct ModeRange: Codable, Sendable, Equatable {
    /// 実機では 0.5 刻み。blow モードでは [""] が返る。
    public let temp: [String]
    /// 実機では ["1","2","3","4","auto"]。dry モードでは [""] が返る。
    public let vol: [String]
    public let dir: [String]?
    public let dirh: [String]?

    /// [""] や [] は「その軸を指定できない」を意味する。
    public var supportsTemperature: Bool { temp.contains { !$0.isEmpty } }
    public var supportsVolume: Bool { vol.contains { !$0.isEmpty } }

    /// 空要素を除いた温度リスト。
    public var temperatures: [String] { temp.filter { !$0.isEmpty } }
}

public struct Light: Codable, Sendable {
    public let buttons: [LightButton]
    public let state: LightState?
}

public struct LightButton: Codable, Sendable {
    public let name: String          // on / off / on-100 / night / bright-up ...
    public let label: String?
    public let image: String?
}

public struct LightState: Codable, Sendable {
    public let brightness: String?
    public let power: String?        // "on" / "off"
    public let lastButton: String?
}

public struct Device: Codable, Sendable {
    public let id: String
    /// ⚠️ /1/devices は nickname ではなく name。/1/appliances 側は nickname。
    public let name: String
    public let firmwareVersion: String?
    public let online: Bool?
    /// キーは "te"(温度) / "hu"(湿度) / "il"(照度) / "mo"(人感)。
    /// Remo mini は "te" のみを返す。
    public let newestEvents: [String: SensorEvent]?
}

public struct SensorEvent: Codable, Sendable {
    public let val: Double
    public let createdAt: Date
}

// MARK: - ウィジェットが描画する共有スナップショット

public struct SensorReading: Codable, Sendable, Equatable {
    public var temperature: Double?
    public var humidity: Double?
    public var illuminance: Double?
    public var measuredAt: Date?
    public var isOnline: Bool

    public init(temperature: Double? = nil, humidity: Double? = nil,
                illuminance: Double? = nil, measuredAt: Date? = nil, isOnline: Bool = true) {
        self.temperature = temperature; self.humidity = humidity
        self.illuminance = illuminance; self.measuredAt = measuredAt; self.isOnline = isOnline
    }
}

/// エアコンの表示状態。range を同梱するのは、ウィジェット側で
/// 「次に押せる温度があるか」をネットワークなしで判定するため。
public struct AirconState: Codable, Sendable, Equatable {
    public var applianceId: String
    public var settings: AirconSettings
    public var modes: [String: ModeRange]

    public init(applianceId: String, settings: AirconSettings, modes: [String: ModeRange]) {
        self.applianceId = applianceId; self.settings = settings; self.modes = modes
    }

    public var currentRange: ModeRange? { modes[settings.mode] }
}

public struct RateLimitInfo: Codable, Sendable, Equatable {
    public var limit: Int
    public var remaining: Int
    public var resetAt: Date

    public var isExhausted: Bool { remaining <= 0 && resetAt > Date() }
}

/// App Group 経由でアプリ ↔ ウィジェット拡張が共有する唯一の状態。
public struct Snapshot: Codable, Sendable, Equatable {
    public var aircon: AirconState?
    public var sensor: SensorReading?
    /// 対象の照明が**全台とも同じシーン**のときだけ値が入る。
    /// 食い違っている場合や判断できない場合は nil（UI ではどれも強調しない）。
    public var lightScene: LightScene?
    public var fetchedAt: Date
    public var rateLimit: RateLimitInfo?
    public var lastError: String?

    public init(aircon: AirconState? = nil, sensor: SensorReading? = nil,
                lightScene: LightScene? = nil,
                fetchedAt: Date = .distantPast, rateLimit: RateLimitInfo? = nil,
                lastError: String? = nil) {
        self.aircon = aircon; self.sensor = sensor; self.lightScene = lightScene
        self.fetchedAt = fetchedAt; self.rateLimit = rateLimit; self.lastError = lastError
    }
}

/// コンテナアプリの設定画面で選んだ内容。
public struct Configuration: Codable, Sendable, Equatable {
    public var airconId: String?
    public var lightIds: [String]
    public var deviceId: String?

    public init(airconId: String? = nil, lightIds: [String] = [], deviceId: String? = nil) {
        self.airconId = airconId; self.lightIds = lightIds; self.deviceId = deviceId
    }

    public var isComplete: Bool { airconId != nil || !lightIds.isEmpty }
}

// MARK: - Codable ヘルパ

extension JSONDecoder {
    public static var nature: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

extension JSONEncoder {
    public static var nature: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
