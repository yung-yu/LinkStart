import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text(NSLocalizedString("settings_title", value: "Settings", comment: "Settings Title"))
                .font(.headline)
            
            Form {
                Section {
                    Picker(NSLocalizedString("codec_label", value: "Codec:", comment: "Codec Label"), selection: $viewModel.videoCodec) {
                        Text("H.264").tag("h264")
                        Text("H.265").tag("h265")
                        Text("AV1").tag("av1")
                    }
                    .pickerStyle(.menu)
                    
                    HStack {
                        Text(NSLocalizedString("max_fps_label", value: "Max FPS:", comment: "Max FPS Label"))
                        Spacer()
                        TextField("60", text: $viewModel.maxFps)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                    }
                    
                    HStack {
                        Text(NSLocalizedString("bit_rate_label", value: "Bit Rate:", comment: "Bit Rate Label"))
                        Spacer()
                        TextField("8", text: $viewModel.videoBitRate)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("Mbps")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Toggle(NSLocalizedString("turn_screen_off_toggle", comment: "Turn Screen Off"), isOn: $viewModel.turnScreenOff)
                    Toggle(NSLocalizedString("stay_awake_toggle", comment: "Stay Awake"), isOn: $viewModel.stayAwake)
                }
                
                Section {
                    Toggle(NSLocalizedString("new_display_toggle", comment: "New Display Toggle"), isOn: $viewModel.useNewDisplay)
                    
                    if viewModel.useNewDisplay {
                        HStack {
                            Text(NSLocalizedString("resolution_label", value: "Resolution:", comment: "Resolution Label"))
                            Spacer()
                            TextField(NSLocalizedString("width_label", comment: "Width"), text: $viewModel.displayWidth)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                            Text("x")
                                .foregroundColor(.secondary)
                            TextField(NSLocalizedString("height_label", comment: "Height"), text: $viewModel.displayHeight)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .frame(width: 350)
            
            Divider()
            
            HStack {
                Spacer()
                Button(action: {
                    viewModel.saveCurrentSettings()
                    viewModel.showSettings = false
                }) {
                    Text(NSLocalizedString("save_settings_btn", value: "Save", comment: "Save Button"))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
        .padding(.top, 16)
    }
}
