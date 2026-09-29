// The panel shown from the menu bar icon.
import SwiftUI

private let japanese = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false

/// Japanese when the user's first language is Japanese, English otherwise.
func tr(_ ja: String, _ en: String) -> String {
    japanese ? ja : en
}

// State shown in the panel. The controller refreshes it on every tick.
final class PanelModel: ObservableObject {
    struct Monitor: Identifiable, Equatable {
        let id: String
        let name: String
        let connected: Bool
        let choice: String // "", "off" or "on"
    }

    @Published var builtInOn = true
    @Published var externalNames: [String] = []
    @Published var temporary = false
    @Published var settingWantsOn = true
    @Published var autoOff = true
    @Published var monitors: [Monitor] = []
    var switchNow: () -> Void = {}
    var setAutoOff: (Bool) -> Void = { _ in }
    var setChoice: (String, String) -> Void = { _, _ in }
    var close: () -> Void = {}
    var quit: () -> Void = {}
}

// A popover rather than a menu: a menu closes on every click. It also stays open
// while other apps are used, and closes only from its icon or its close button.
struct PanelView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.externalNames.isEmpty {
                Text(tr("モニター未接続（内蔵画面を使用中）", "No monitor connected (using the built-in display)"))
                    .font(.headline)
            } else {
                Text(tr("内蔵画面: ", "Built-in display: ")
                     + (model.builtInOn ? tr("オン", "On") : tr("オフ", "Off")))
                    .font(.headline)
                Text(tr("表示先: ", "Showing on: ") + model.externalNames.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(tr("今だけ（次にモニターをつなぐまで）", "Just for now (until a monitor is connected again)"))
                    .font(.subheadline).bold()
                Button(model.builtInOn ? tr("内蔵画面をオフにする", "Turn the built-in display off")
                                       : tr("内蔵画面をオンにする", "Turn the built-in display on")) {
                    model.switchNow()
                }
                if model.temporary {
                    Text(model.settingWantsOn
                         ? tr("一時的な状態です。設定では内蔵画面オン", "Temporary. Your setting keeps the built-in display on.")
                         : tr("一時的な状態です。設定では内蔵画面オフ", "Temporary. Your setting turns the built-in display off."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()
            Text(tr("設定（ずっと有効・変えるとすぐ反映）", "Settings (kept, applied immediately)"))
                .font(.subheadline).bold()
            Toggle(tr("モニターをつないだら内蔵画面をオフ", "Turn the built-in display off when a monitor is connected"),
                   isOn: Binding(get: { model.autoOff }, set: { model.setAutoOff($0) }))
                .toggleStyle(.switch)
            if !model.monitors.isEmpty {
                Text(tr("モニターごとの内蔵画面（未設定のモニターは上の設定に従います）",
                        "Per monitor (monitors left unset follow the setting above)"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.monitors) { monitor in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monitor.name + (monitor.connected ? "" : tr("（未接続）", " (not connected)")))
                        Picker("", selection: Binding(get: { monitor.choice },
                                                      set: { model.setChoice(monitor.id, $0) })) {
                            Text(tr("上の設定に従う", "Follow setting")).tag("")
                            Text(tr("オフ", "Off")).tag("off")
                            Text(tr("オン", "On")).tag("on")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }

            Divider()
            HStack {
                Button(tr("閉じる", "Close")) { model.close() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(tr("内蔵画面を戻して終了", "Restore built-in and quit")) { model.quit() }
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
