import SwiftUI

extension Color {
    init(hex: UInt64, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: opacity)
    }

    var contrastingContentColor: Color {
        let uiColor = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.4 ? Color(hex: 0x444444) : Color(hex: 0xDDDDDD)
    }

    // MARK: - Black & White
    static let colorBlack = Color(hex: 0x000000)
    static let colorWhite = Color(hex: 0xFFFFFF)

    // MARK: - Blue
    static let colorBlue25 = Color(hex: 0xF6FBFF)
    static let colorBlue50 = Color(hex: 0xEBF5FF)
    static let colorBlue100 = Color(hex: 0xD6EAFF)
    static let colorBlue200 = Color(hex: 0xB2D6FF)
    static let colorBlue300 = Color(hex: 0x81B9FD)
    static let colorBlue400 = Color(hex: 0x4E98F9)
    static let colorBlue500 = Color(hex: 0x1870EC)
    static let colorBlue600 = Color(hex: 0x0C54C0)
    static let colorBlue700 = Color(hex: 0x083F97)
    static let colorBlue800 = Color(hex: 0x032767)
    static let colorBlue850 = Color(hex: 0x021F55)
    static let colorBlue900 = Color(hex: 0x01163F)
    static let colorBlue950 = Color(hex: 0x000B25)
    static let colorBlue975 = Color(hex: 0x000510)

    // MARK: - Bluegrey
    static let colorBluegrey25 = Color(hex: 0xFCFCFD)
    static let colorBluegrey50 = Color(hex: 0xF5F6F8)
    static let colorBluegrey100 = Color(hex: 0xE8EAED)
    static let colorBluegrey200 = Color(hex: 0xCDD0D5)
    static let colorBluegrey300 = Color(hex: 0xB5B9BF)
    static let colorBluegrey400 = Color(hex: 0x9DA1A6)
    static let colorBluegrey500 = Color(hex: 0x7C8188)
    static let colorBluegrey600 = Color(hex: 0x62676F)
    static let colorBluegrey700 = Color(hex: 0x474A52)
    static let colorBluegrey800 = Color(hex: 0x36393F)
    static let colorBluegrey850 = Color(hex: 0x272A30)
    static let colorBluegrey900 = Color(hex: 0x1C2026)
    static let colorBluegrey950 = Color(hex: 0x101319)
    static let colorBluegrey975 = Color(hex: 0x05070A)

    // MARK: - Cyan
    static let colorCyan25 = Color(hex: 0xF5FDFF)
    static let colorCyan50 = Color(hex: 0xE5FAFF)
    static let colorCyan100 = Color(hex: 0xD1F6FF)
    static let colorCyan200 = Color(hex: 0xB4EDFE)
    static let colorCyan300 = Color(hex: 0x83DDFB)
    static let colorCyan400 = Color(hex: 0x48C7F5)
    static let colorCyan500 = Color(hex: 0x00A4DD)
    static let colorCyan600 = Color(hex: 0x0484AF)
    static let colorCyan700 = Color(hex: 0x026688)
    static let colorCyan800 = Color(hex: 0x00435C)
    static let colorCyan850 = Color(hex: 0x003447)
    static let colorCyan900 = Color(hex: 0x002533)
    static let colorCyan950 = Color(hex: 0x00121A)
    static let colorCyan975 = Color(hex: 0x00070A)

    // MARK: - Green
    static let colorGreen25 = Color(hex: 0xF0FEF4)
    static let colorGreen50 = Color(hex: 0xD8FCE3)
    static let colorGreen100 = Color(hex: 0xBBFBD0)
    static let colorGreen200 = Color(hex: 0x8BF7B1)
    static let colorGreen300 = Color(hex: 0x56E78B)
    static let colorGreen400 = Color(hex: 0x23C762)
    static let colorGreen500 = Color(hex: 0x0BA245)
    static let colorGreen600 = Color(hex: 0x057A32)
    static let colorGreen700 = Color(hex: 0x006326)
    static let colorGreen800 = Color(hex: 0x004119)
    static let colorGreen850 = Color(hex: 0x003214)
    static let colorGreen900 = Color(hex: 0x00240F)
    static let colorGreen950 = Color(hex: 0x001A0B)
    static let colorGreen975 = Color(hex: 0x000A04)

    // MARK: - Grey
    static let colorGrey25 = Color(hex: 0xFCFCFC)
    static let colorGrey50 = Color(hex: 0xF5F5F5)
    static let colorGrey100 = Color(hex: 0xEEEEEE)
    static let colorGrey200 = Color(hex: 0xCFCFCF)
    static let colorGrey300 = Color(hex: 0xB8B8B8)
    static let colorGrey400 = Color(hex: 0x9E9E9E)
    static let colorGrey500 = Color(hex: 0x808080)
    static let colorGrey600 = Color(hex: 0x666666)
    static let colorGrey700 = Color(hex: 0x4A4A4A)
    static let colorGrey800 = Color(hex: 0x383838)
    static let colorGrey850 = Color(hex: 0x2A2A2A)
    static let colorGrey900 = Color(hex: 0x1F1F1F)
    static let colorGrey950 = Color(hex: 0x121212)
    static let colorGrey975 = Color(hex: 0x080808)

    // MARK: - Lime
    static let colorLime25 = Color(hex: 0xF8FEF0)
    static let colorLime50 = Color(hex: 0xEDFCD8)
    static let colorLime100 = Color(hex: 0xE0FBBB)
    static let colorLime200 = Color(hex: 0xCAF78B)
    static let colorLime300 = Color(hex: 0xAAE78B)
    static let colorLime400 = Color(hex: 0x87CF23)
    static let colorLime500 = Color(hex: 0x5C9E00)
    static let colorLime600 = Color(hex: 0x4B8100)
    static let colorLime700 = Color(hex: 0x3A6300)
    static let colorLime800 = Color(hex: 0x264100)
    static let colorLime850 = Color(hex: 0x1D3200)
    static let colorLime900 = Color(hex: 0x142400)
    static let colorLime950 = Color(hex: 0x0E1A00)
    static let colorLime975 = Color(hex: 0x050A00)

    // MARK: - Magenta
    static let colorMagenta25 = Color(hex: 0xFFF8FC)
    static let colorMagenta50 = Color(hex: 0xFFEEF9)
    static let colorMagenta100 = Color(hex: 0xFFDBF3)
    static let colorMagenta200 = Color(hex: 0xFFB8E8)
    static let colorMagenta300 = Color(hex: 0xFD96DC)
    static let colorMagenta400 = Color(hex: 0xFB74D0)
    static let colorMagenta500 = Color(hex: 0xEE47BC)
    static let colorMagenta600 = Color(hex: 0xC10B8D)
    static let colorMagenta700 = Color(hex: 0x8D0863)
    static let colorMagenta800 = Color(hex: 0x6A024C)
    static let colorMagenta850 = Color(hex: 0x480137)
    static let colorMagenta900 = Color(hex: 0x320127)
    static let colorMagenta950 = Color(hex: 0x1F0018)
    static let colorMagenta975 = Color(hex: 0x0F000C)

    // MARK: - Orange
    static let colorOrange25 = Color(hex: 0xFFFAF3)
    static let colorOrange50 = Color(hex: 0xFFF1DE)
    static let colorOrange100 = Color(hex: 0xFFE2BF)
    static let colorOrange200 = Color(hex: 0xFFC387)
    static let colorOrange300 = Color(hex: 0xF8A049)
    static let colorOrange400 = Color(hex: 0xF68E2C)
    static let colorOrange500 = Color(hex: 0xF07C00)
    static let colorOrange600 = Color(hex: 0xB25600)
    static let colorOrange700 = Color(hex: 0x803900)
    static let colorOrange800 = Color(hex: 0x5C2600)
    static let colorOrange850 = Color(hex: 0x471E00)
    static let colorOrange900 = Color(hex: 0x2E1300)
    static let colorOrange950 = Color(hex: 0x1A0A00)
    static let colorOrange975 = Color(hex: 0x0A0400)

    // MARK: - Purple
    static let colorPurple25 = Color(hex: 0xFCF8FF)
    static let colorPurple50 = Color(hex: 0xF6EEFF)
    static let colorPurple100 = Color(hex: 0xEDDBFF)
    static let colorPurple200 = Color(hex: 0xDDBDFF)
    static let colorPurple300 = Color(hex: 0xC086FD)
    static let colorPurple400 = Color(hex: 0xAE67FA)
    static let colorPurple500 = Color(hex: 0x893BE3)
    static let colorPurple600 = Color(hex: 0x7011E4)
    static let colorPurple700 = Color(hex: 0x5407A6)
    static let colorPurple800 = Color(hex: 0x300367)
    static let colorPurple850 = Color(hex: 0x250254)
    static let colorPurple900 = Color(hex: 0x19013F)
    static let colorPurple950 = Color(hex: 0x0E0024)
    static let colorPurple975 = Color(hex: 0x06000F)

    // MARK: - Red
    static let colorRed25 = Color(hex: 0xFFF6F6)
    static let colorRed50 = Color(hex: 0xFFECEC)
    static let colorRed100 = Color(hex: 0xFFDAD9)
    static let colorRed200 = Color(hex: 0xFFBAB8)
    static let colorRed300 = Color(hex: 0xFB7E7E)
    static let colorRed400 = Color(hex: 0xF85A5A)
    static let colorRed500 = Color(hex: 0xDF2222)
    static let colorRed600 = Color(hex: 0xB9090F)
    static let colorRed700 = Color(hex: 0x8C0205)
    static let colorRed800 = Color(hex: 0x570009)
    static let colorRed850 = Color(hex: 0x3D0005)
    static let colorRed900 = Color(hex: 0x330004)
    static let colorRed950 = Color(hex: 0x170002)
    static let colorRed975 = Color(hex: 0x0F0002)

    // MARK: - Yellow
    static let colorYellow25 = Color(hex: 0xFFFEF3)
    static let colorYellow50 = Color(hex: 0xFFFDDE)
    static let colorYellow100 = Color(hex: 0xFFFABF)
    static let colorYellow200 = Color(hex: 0xFFF587)
    static let colorYellow300 = Color(hex: 0xF8E749)
    static let colorYellow400 = Color(hex: 0xF6DF2C)
    static let colorYellow500 = Color(hex: 0xF0D400)
    static let colorYellow600 = Color(hex: 0xB29B00)
    static let colorYellow700 = Color(hex: 0x806F00)
    static let colorYellow800 = Color(hex: 0x5C4E00)
    static let colorYellow850 = Color(hex: 0x473D00)
    static let colorYellow900 = Color(hex: 0x2E2600)
    static let colorYellow950 = Color(hex: 0x1A1400)
    static let colorYellow975 = Color(hex: 0x0A0800)

    // MARK: - Legacy aliases
    static let jellyfinBlue = Color.colorCyan500
    static let jellyfinPurple = Color(hex: 0xAA5CC3)
    static let notQuiteBlack = Color(hex: 0x101010)
}
