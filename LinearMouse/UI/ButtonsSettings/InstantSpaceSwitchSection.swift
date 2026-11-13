// MIT License
// Copyright (c) 2026 LinearMouse

import SwiftUI

struct InstantSpaceSwitchSection: View {
    @ObservedObject var state: ButtonsSettingsState = .shared

    var body: some View {
        Section {
            Toggle(isOn: $state.instantSpaceSwitch) {
                withDescription {
                    Text("Instant space switch (Dev)")
                    Text(
                        "When a button runs Move left a space or Move right a space, move one desktop immediately. Requires macOS 27 or later. Uses a private macOS API and falls back to the system animation if that is unavailable."
                    )
                }
            }
        }
        .modifier(SectionViewModifier())
    }
}
