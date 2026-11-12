import SwiftUI

/// 「遊ぶ」の値を変える行（時刻・電池・電波・Wi-Fi）
struct PlayPanel: View {
    let model: PlayModel
    @State private var isPickingTime = false

    var body: some View {
        // 文字を大きくしていて入りきらないときは、スクロールさせる
        ViewThatFits(in: .vertical) {
            rows
            ScrollView {
                rows
            }
        }
        .padding(.horizontal, Theme.margin)
        .sheet(isPresented: $isPickingTime) {
            TimePickerSheet(model: model)
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            OptionSeparator()
            OptionRow("Time") {
                SegmentPicker(
                    options: [
                        .init(value: .keep, title: "Keep", identifier: "play.time.keep"),
                        .init(value: .hide, title: "Hide", identifier: "play.time.hide"),
                        .init(value: .set, verbatim: model.timeText, identifier: "play.time.set")
                    ],
                    selection: Binding(get: { model.timeChoice }, set: { model.setTimeChoice($0) }),
                    fillsWidth: false,
                    // 時刻を押したら、そのまま時刻を選ぶ画面を出す
                    onTap: { if $0 == .set { isPickingTime = true } }
                )
            }
            OptionSeparator()
            OptionRow("Battery") {
                HStack(spacing: 12) {
                    Slider(
                        value: Binding(get: { Double(model.batteryPercent) }, set: { model.setBatteryPercent(Int($0.rounded())) }),
                        in: Double(PlayModel.batteryRange.lowerBound)...Double(PlayModel.batteryRange.upperBound),
                        step: 1
                    )
                    .tint(.white)
                    .accessibilityLabel("Battery level")
                    .accessibilityValue(Text(verbatim: "\(model.batteryPercent)%"))
                    .accessibilityIdentifier("play.battery")
                    Text(verbatim: "\(model.batteryPercent)%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.darkInkSecondary)
                        .frame(minWidth: 48, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
            OptionSeparator()
            OptionRow("Signal") {
                SegmentPicker(
                    options: PlayModel.cellularRange.map { .init(value: $0, verbatim: "\($0)", identifier: "play.cellular.\($0)") },
                    selection: Binding(get: { model.cellularBars }, set: { model.setCellularBars($0) }),
                    fillsWidth: false
                )
            }
            OptionSeparator()
            OptionRow("Wi-Fi") {
                SegmentPicker(
                    options: [.init(value: Int?.none, title: "Off", identifier: "play.wifi.off")]
                        + (1...PlayModel.wifiRange.upperBound).map {
                            .init(value: Int?.some($0), verbatim: "\($0)", identifier: "play.wifi.\($0)")
                        },
                    selection: Binding(get: { model.wifiBars }, set: { model.setWiFiBars($0) }),
                    fillsWidth: false
                )
            }
        }
    }
}

/// 時刻を選ぶ画面（下から出る小さなシート）
private struct TimePickerSheet: View {
    let model: PlayModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .accessibilityIdentifier("play.timePicker")
            Button("Done") {
                dismiss()
            }
            .buttonStyle(BlockButtonStyle(kind: .primary))
            .accessibilityIdentifier("play.timePicker.done")
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .presentationDetents([.height(320)])
        .presentationBackground(Theme.darkSurfaceSecondary)
        .preferredColorScheme(.dark)
    }

    /// 選んでいる時・分を、今日の日付の時刻として読み書きする
    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: model.hour, minute: model.minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.setTime(hour: components.hour ?? model.hour, minute: components.minute ?? model.minute)
            }
        )
    }
}
