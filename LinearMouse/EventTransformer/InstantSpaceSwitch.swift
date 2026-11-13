// MIT License
// Copyright (c) 2026 LinearMouse

import AppKit
import CoreGraphics

enum InstantSpaceDirection {
    case left, right
}

enum InstantSpaceSwitch {
    struct Space: Equatable {
        var id: UInt64
        var type: Int
    }

    struct Display: Equatable {
        var identifier: String
        var current: UInt64
        var spaces: [Space]

        init?(record: [String: Any]) {
            guard let identifier = record["Display Identifier"] as? String,
                  let currentSpace = record["Current Space"] as? [String: Any],
                  let current = Self.identifier(currentSpace["ManagedSpaceID"]) else {
                return nil
            }
            self.identifier = identifier
            self.current = current
            spaces = (record["Spaces"] as? [[String: Any]] ?? []).compactMap { space in
                guard let id = Self.identifier(space["ManagedSpaceID"]),
                      let type = Self.number(space["type"]) else {
                    return nil
                }
                return Space(id: id, type: type)
            }
        }

        init(identifier: String, current: UInt64, spaces: [Space]) {
            self.identifier = identifier
            self.current = current
            self.spaces = spaces
        }

        private static func identifier(_ value: Any?) -> UInt64? {
            (value as? NSNumber)?.uint64Value
        }

        private static func number(_ value: Any?) -> Int? {
            (value as? NSNumber)?.intValue
        }
    }

    /// Desktop and full-screen Spaces, in Mission Control order.
    static let visibleTypes: Set<Int> = [0, 4]

    static func target(
        displays: [Display],
        pointerDisplayIdentifier: String?,
        direction: InstantSpaceDirection
    ) -> (display: String, from: UInt64, to: UInt64)? {
        let display = displays.first { $0.identifier == pointerDisplayIdentifier } ?? displays.first
        guard let display else {
            return nil
        }
        let visible = display.spaces.filter { visibleTypes.contains($0.type) }
        guard let index = visible.firstIndex(where: { $0.id == display.current }) else {
            return nil
        }
        let next = direction == .left ? index - 1 : index + 1
        guard visible.indices.contains(next), visible[next].id != display.current else {
            return nil
        }
        return (display.identifier, display.current, visible[next].id)
    }

    /// One outstanding request per display; rapid input changes only the final destination.
    final class Coordinator {
        struct Pending {
            var from: UInt64
            var to: UInt64
            var desired: UInt64
            var deadline: TimeInterval
        }

        private(set) var pending: [String: Pending] = [:]
        let submit: (String, UInt64, UInt64) -> Bool

        init(submit: @escaping (String, UInt64, UInt64) -> Bool) {
            self.submit = submit
        }

        func perform(display: Display, direction: InstantSpaceDirection, now: TimeInterval) -> Bool {
            if let request = pending[display.identifier],
               display.current != request.from, display.current != request.to {
                pending[display.identifier] = nil
            }
            var effective = display
            if let request = pending[display.identifier] {
                effective.current = request.desired
            }
            guard let choice = target(
                displays: [effective], pointerDisplayIdentifier: display.identifier, direction: direction
            ) else {
                // An edge is a handled no-op, not a reason to start a system animation.
                return true
            }
            if var request = pending[display.identifier] {
                request.desired = choice.to
                pending[display.identifier] = request
                return true
            }
            guard submit(choice.display, choice.to, choice.from) else { return false }
            pending[choice.display] = Pending(
                from: choice.from, to: choice.to, desired: choice.to, deadline: now + 0.5
            )
            return true
        }

        func reconcile(displays: [Display]?, now: TimeInterval) {
            guard let displays else {
                pending.removeAll()
                return
            }
            for (identifier, request) in pending {
                guard let display = displays.first(where: { $0.identifier == identifier }) else {
                    pending[identifier] = nil
                    continue
                }
                if display.current == request.to {
                    pending[identifier] = nil
                    guard request.desired != display.current,
                          display.spaces.contains(where: { $0.id == request.desired && visibleTypes.contains($0.type) })
                    else { continue }
                    if submit(identifier, request.desired, display.current) {
                        pending[identifier] = Pending(
                            from: display.current, to: request.desired, desired: request.desired, deadline: now + 0.5
                        )
                    }
                } else if display.current != request.from || now >= request.deadline {
                    pending[identifier] = nil
                }
            }
        }
    }

    private static let coordinator = Coordinator {
        LMInstantSpaceSwitch.submitSwitchDisplay($0, toSpace: $1, fromSpace: $2)
    }
    private static var pollScheduled = false

    private static func displays() -> [Display]? {
        (LMInstantSpaceSwitch.displays() as? [[String: Any]])?.compactMap(Display.init(record:))
    }

    static func perform(_ direction: InstantSpaceDirection) -> Bool {
        precondition(Thread.isMainThread)
        guard #available(macOS 27.0, *) else { return false }
        guard let records = displays(),
              let display = records.first(where: { $0.identifier == pointerDisplayIdentifier() }) ?? records.first
        else {
            coordinator.reconcile(displays: nil, now: ProcessInfo.processInfo.systemUptime)
            return false
        }
        let handled = coordinator.perform(
            display: display, direction: direction, now: ProcessInfo.processInfo.systemUptime
        )
        schedulePoll()
        return handled
    }

    private static func schedulePoll() {
        guard !pollScheduled, !coordinator.pending.isEmpty else { return }
        pollScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            pollScheduled = false
            coordinator.reconcile(displays: displays(), now: ProcessInfo.processInfo.systemUptime)
            schedulePoll()
        }
    }

    private static func pointerDisplayIdentifier() -> String? {
        let location = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        guard let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))
        return uuid.map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }
}
