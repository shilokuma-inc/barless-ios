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
            if !model.allowance.isPro {
                quota
                    .padding(.bottom, 10)
            }
            OptionSeparator()
            OptionRow("Time") {
                SegmentPicker(
                    // 時刻の位置が分からなかった画像では、「そのまま」は選べない（出さない）
                    options: (model.canKeepTime ? [.init(value: .keep, title: "Keep", identifier: "play.time.keep")] : []) + [
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
                        .lineLimit(1)
                        .fixedSize()
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
            .disabled(!model.canDrawWiFi)
            .opacity(model.canDrawWiFi ? 1 : 0.4)
            if !model.canDrawWiFi {
                Text("There's no room to draw Wi-Fi next to the carrier name.")
                    .font(.caption)
                    .foregroundStyle(Theme.darkInkSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("play.wifi.unavailable")
            }
        }
    }
}

extension PlayPanel {
    /// 無料の残りの回数と、透かしが入ること。値を変える前に分かるように、いつも出しておく
    @ViewBuilder fileprivate var quota: some View {
        let remaining = model.allowance.remainingToday
        Group {
            if remaining > 0 || !model.usesAllowanceOnExport {
                Text("**\(remaining) free left today** · adds a watermark")
                    .foregroundStyle(Theme.darkInkSecondary)
            } else {
                // 使い切っていて、いまの中身は書き出せない
                Text("Free exports are limited to \(PlayAllowance.dailyLimit) a day. They reset tomorrow.")
                    .foregroundStyle(Theme.warning)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("play.quota")
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
