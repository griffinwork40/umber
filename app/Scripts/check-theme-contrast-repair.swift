//
//  check-theme-contrast-repair.swift
//  The promises unique to Classic Repaired, separate from Umber's design floors.
//
//  Classic Repaired is deliberately not a uniformly high-contrast palette: its quiet
//  foreground and saturated dark red/magenta are the qualities it preserves from
//  Terminal.app Basic. This file gates only the defects it claims to repair and the
//  figure/ground structure that justifies a distinct preset. Keeping these assertions
//  out of the main harness also preserves that file's 350-LOC ceiling.
//

import Foundation

func checkClassicRepaired(_ expect: (Bool, String, String) -> Void) {
    let p = ThemePalette.classicRepaired
    guard let bg = RGB(hex: p.background), let fg = RGB(hex: p.foreground),
          let white = RGB(hex: p.ansi[7]),
          let normalBlue = RGB(hex: p.ansi[4]), let brightBlue = RGB(hex: p.ansi[12]) else {
        expect(false, "classic-repaired parses", "one of its load-bearing colours did not parse")
        return
    }

    let normalLc = APCA.lc(text: normalBlue, background: bg)
    let brightLc = APCA.lc(text: brightBlue, background: bg)
    expect(normalLc >= 45, "classic-repaired blue", "ANSI 4 Lc \(normalLc) < 45")
    expect(brightLc >= 58, "classic-repaired bright blue", "ANSI 12 Lc \(brightLc) < 58")

    for i in 0..<8 {
        guard let normal = RGB(hex: p.ansi[i]), let bright = RGB(hex: p.ansi[i + 8]) else { continue }
        let distance = OKLab.distance(normal, bright)
        expect(distance >= 0.085, "classic-repaired ring \(i)",
               "normal/bright dE-OK \(distance) < 0.085")
    }

    let foregroundGap = OKLab.lightness(white) - OKLab.lightness(fg)
    expect(foregroundGap >= 0.18, "classic-repaired quiet foreground",
           "ANSI white is only \(foregroundGap) OKLab above body text")

    let brightChromatic = p.ansi[9...14].compactMap(RGB.init(hex:))
    let meanBright = brightChromatic.map(OKLab.lightness).reduce(0, +) / Double(brightChromatic.count)
    expect(meanBright - OKLab.lightness(fg) >= 0.10, "classic-repaired promotion channel",
           "bright chromatic mean is only \(meanBright - OKLab.lightness(fg)) above body text")

    expect(p.chromeForeground == p.ansi[7], "classic-repaired chrome foreground",
           "11pt document chrome must use ANSI white rather than quiet terminal body text")
}
