import SwiftUI

struct MoonfinColorScheme {
    // MARK: - Background & Surface
    let background: Color
    let onBackground: Color
    let surface: Color
    let scrim: Color

    // MARK: - Buttons
    let button: Color
    let onButton: Color
    let buttonFocused: Color
    let onButtonFocused: Color
    let buttonDisabled: Color
    let onButtonDisabled: Color
    let buttonActive: Color
    let onButtonActive: Color

    // MARK: - Input
    let input: Color
    let onInput: Color
    let inputFocused: Color
    let onInputFocused: Color

    // MARK: - Range / Seekbar
    let rangeControlBackground: Color
    let rangeControlFill: Color
    let rangeControlKnob: Color
    let seekbarBuffer: Color

    // MARK: - Recording
    let recording: Color
    let onRecording: Color

    // MARK: - Badge
    let badge: Color
    let onBadge: Color

    // MARK: - List
    let listHeader: Color
    let listOverline: Color
    let listHeadline: Color
    let listCaption: Color
    let listButton: Color
    let listButtonFocused: Color
}

extension MoonfinColorScheme {
    static let `default` = MoonfinColorScheme(
        background: .colorGrey975,
        onBackground: .colorBluegrey25,
        surface: .colorBluegrey900,
        scrim: Color(hex: 0x000000, opacity: 0.67),

        button: Color(hex: 0x747474, opacity: 0.7),
        onButton: Color(hex: 0xDDDDDD),
        buttonFocused: Color(hex: 0xCCCCCC, opacity: 0.9),
        onButtonFocused: Color(hex: 0x444444),
        buttonDisabled: Color(hex: 0x747474, opacity: 0.2),
        onButtonDisabled: Color(hex: 0x686868),
        buttonActive: Color(hex: 0xCCCCCC, opacity: 0.3),
        onButtonActive: Color(hex: 0xDDDDDD),

        input: Color(hex: 0x747474, opacity: 0.7),
        onInput: Color(hex: 0xCCCCCC, opacity: 0.9),
        inputFocused: Color(hex: 0xCCCCCC, opacity: 0.9),
        onInputFocused: Color(hex: 0xDDDDDD),

        rangeControlBackground: .colorBluegrey700,
        rangeControlFill: .colorCyan500,
        rangeControlKnob: .colorBluegrey100,
        seekbarBuffer: .colorBluegrey300,

        recording: .colorRed300,
        onRecording: .colorRed25,

        badge: .colorCyan500,
        onBadge: .colorBluegrey100,

        listHeader: .colorGrey50,
        listOverline: .colorGrey500,
        listHeadline: .colorGrey25,
        listCaption: .colorGrey200,
        listButton: .clear,
        listButtonFocused: .colorBluegrey800
    )
}
