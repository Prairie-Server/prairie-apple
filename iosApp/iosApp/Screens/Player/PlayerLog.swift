//
//  PlayerLog.swift
//  Continuum (iOS + tvOS)
//
//  Single emission point for `[CMP-…]` player-pipeline trace lines.
//
//  The pipeline previously fanned out each diagnostic to both
//  `Logger.info(...)` (Apple unified logging) and `print(...)` (stdout) so
//  that tvOS's `devicectl --console`, which only sees stdout, could observe
//  the trace alongside iOS's Console.app, which observes both. The side
//  effect on iPhone capture was every `[CMP-…]` line appearing twice —
//  often with subtly different formatting (e.g. `startTime=0.0` vs
//  `startTime=0.000000`) which doubled the log volume during a session.
//
//  `cmpLog` collapses that to a single `print` call. `print` already
//  reaches both surfaces — stdout is captured by tvOS device console, and
//  the iOS process log mirrors stdout into the system log — so we lose
//  nothing by going through one path. Genuine errors that need
//  filterable subsystem/category routing keep their `Logger.error` call;
//  this helper only replaces the diagnostic-trace pairs.
//

import Foundation

@inline(__always)
func cmpLog(_ message: @autoclosure () -> String) {
    print(message())
}
