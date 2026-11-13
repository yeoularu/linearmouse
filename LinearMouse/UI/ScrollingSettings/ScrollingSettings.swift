// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

struct ScrollingSettings: View {
    @ObservedObject private var state = ScrollingSettingsState.shared

    var body: some View {
        DetailView {
            VStack(alignment: .leading) {
                Header()

                Form {
                    ReverseScrollingSection()

                    if state.showsHighResolutionWheelControl {
                        LogitechHighResolutionWheelSection()
                    }

                    ScrollingModeSection()

                    Section {
                        Toggle(isOn: $state.actionThrottling) {
                            withDescription {
                                Text("Throttle scroll actions (Dev)")
                                Text("Limit wheel-triggered commands to once every 300 ms. Turning this off may repeat commands rapidly.")
                            }
                        }
                    }
                    .modifier(SectionViewModifier())

                    ModifierKeysSection()
                }
                .modifier(FormViewModifier())
            }
        }
        .onAppear {
            state.refreshHighResolutionWheelInfo()
        }
    }
}
