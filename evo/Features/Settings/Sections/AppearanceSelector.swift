import SwiftUI

struct AppearanceSelector: View {
    @Binding var selection: AppAppearance
    @Binding var fontScale: Double

    private struct Option: Identifiable {
        let id = UUID()
        let appearance: AppAppearance
        let imageName: String
        let title: String
    }

    private var options: [Option] {
        [
            .init(appearance: .light, imageName: "appearance-light", title: "Light"),
            .init(appearance: .dark, imageName: "appearance-dark", title: "Dark"),
            .init(appearance: .system, imageName: "appearance-system", title: "Auto")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance").foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    ForEach(options) { opt in
                        let isSelected = selection == opt.appearance
                        Button {
                            selection = opt.appearance
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(opt.imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 105, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text(opt.title)
                                    .fontWeight(isSelected ? .semibold : .regular)
                            }
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSelected ? Color(.controlColor) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Settings text size").foregroundStyle(.secondary)
                    Spacer()
                    Text(percentLabel(fontScale))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $fontScale,
                    in: SettingsStore.settingsFontScaleRange,
                    step: SettingsStore.settingsFontScaleStep
                ) {
                    Text("Settings text size")
                } minimumValueLabel: {
                    Text("A").font(.caption)
                } maximumValueLabel: {
                    Text("A").font(.title3)
                }

                Text("Adjusts text size inside this Settings window only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percentLabel(_ scale: Double) -> String {
        "\(Int((scale * 100).rounded()))%"
    }
}

extension Double {
    var asSettingsDynamicTypeSize: DynamicTypeSize {
        switch self {
        case ..<0.85: return .xSmall
        case ..<0.95: return .small
        case ..<1.05: return .large
        case ..<1.15: return .xLarge
        case ..<1.25: return .xxLarge
        case ..<1.35: return .xxxLarge
        case ..<1.45: return .accessibility1
        default: return .accessibility2
        }
    }
}
