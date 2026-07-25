import Foundation

/// "2026-07-25T09:30:00-05:00" → "9:30" (frames drop the leading zero)
func hhmm(_ iso: String) -> String {
    let t = iso.dropFirst(11).prefix(5)
    return t.first == "0" ? String(t.dropFirst()) : String(t)
}

func minutesSinceMidnight(_ iso: String) -> Int {
    let h = Int(iso.dropFirst(11).prefix(2)) ?? 0
    let m = Int(iso.dropFirst(14).prefix(2)) ?? 0
    return h * 60 + m
}

/// "2026-07-24" → "Thu, Jul 24"
func displayDate(_ ymd: String) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: ymd) else { return ymd }
    let out = DateFormatter()
    out.dateFormat = "EEE, MMM d"
    return out.string(from: d)
}

var todayYMD: String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

/// "FRI JUL 25" — chat header
var headerDate: String {
    let f = DateFormatter()
    f.dateFormat = "EEE MMM d"
    return f.string(from: Date()).uppercased()
}
