import Foundation

/// Columns that make `n` items the most **square** grid — the divisor of `n` closest to √n.
///
/// Uses the √n factor shortcut: divisors come in symmetric pairs (`a · b = n`), so one of each
/// pair is always ≤ √n. Scanning `i` only up to √n finds the largest small-side divisor in
/// **O(√n)** instead of O(n); `n / that` is its paired larger factor → the column count (wider
/// reads better than taller on a phone). A prime `n` has no middle factor, so it falls out as a
/// single row (1 × n), which is correct. Pure layout math — a tidiness win, not a memory one.
func squareGridColumns(_ n: Int) -> Int {
    guard n > 3 else { return max(1, n) }
    var smaller = 1
    var i = 1
    while i * i <= n {                 // ← the shortcut: only scan up to √n
        if n % i == 0 { smaller = i }  // the largest divisor that is ≤ √n
        i += 1
    }
    return max(1, n / smaller)         // its symmetric partner (the larger factor) = columns
}
