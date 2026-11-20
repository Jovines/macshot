import Foundation

/// Keep a manually positioned toolbar and its options together and reachable.
enum ToolbarPlacement {
    static func origin(_ proposed: NSPoint, barSize: NSSize, optionsSize: NSSize = .zero,
                       optionsAbove: Bool = false, bounds: NSRect,
                       obstructions: [NSRect] = []) -> NSPoint {
        let hasOptions = optionsSize.width > 0 && optionsSize.height > 0
        let extraHeight = hasOptions ? optionsSize.height + 2 : 0
        let width = max(barSize.width, optionsSize.width)
        let left = (width - barSize.width) / 2
        let bottom = optionsAbove ? 0 : extraHeight
        let size = NSSize(width: width, height: barSize.height + extraHeight)
        let safe = bounds.insetBy(dx: 4, dy: 4)
        var group = NSRect(x: proposed.x - left, y: proposed.y - bottom,
                           width: size.width, height: size.height)
        group.origin.x = max(safe.minX, min(group.minX, safe.maxX - size.width))
        group.origin.y = max(safe.minY, min(group.minY, safe.maxY - size.height))
        for obstruction in obstructions where group.intersects(obstruction) {
            group.origin.y = max(safe.minY, obstruction.minY - size.height - 2)
        }
        return NSPoint(x: group.minX + left, y: group.minY + bottom)
    }
}
