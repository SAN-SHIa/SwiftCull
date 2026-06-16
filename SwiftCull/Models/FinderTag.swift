import SwiftUI

struct FinderTag: Identifiable, Hashable, Sendable {
    let name: String
    let colorIndex: Int

    var id: String { name }

    var color: Color {
        switch colorIndex {
        case 1: return Color(red: 142/255, green: 142/255, blue: 147/255)
        case 2: return Color(red: 52/255, green: 199/255, blue: 89/255)
        case 3: return Color(red: 175/255, green: 82/255, blue: 222/255)
        case 4: return Color(red: 0/255, green: 122/255, blue: 255/255)
        case 5: return Color(red: 255/255, green: 204/255, blue: 0/255)
        case 6: return Color(red: 255/255, green: 59/255, blue: 48/255)
        case 7: return Color(red: 255/255, green: 149/255, blue: 0/255)
        default: return Color(red: 142/255, green: 142/255, blue: 147/255)
        }
    }

    var displayName: String {
        let colorNames: [Int: String] = [
            1: "灰色", 2: "绿色", 3: "紫色",
            4: "蓝色", 5: "黄色", 6: "红色", 7: "橙色"
        ]
        if let colorName = colorNames[colorIndex] {
            return "\(name) (\(colorName))"
        }
        return name
    }
}
