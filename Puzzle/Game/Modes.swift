enum Players { case single, p2p }

/// Raw values match the wire format shared with the Android app.
enum Mode: String, Codable { case timeBased = "TIME_BASED", free = "FREE" }
