import Cocoa

/// Protocol for the minimal canvas state that TextEditingController needs for commit/show.
@MainActor
protocol TextEditingCanvas: AnyObject {
    func viewToCanvas(_ p: NSPoint) -> NSPoint
    func canvasToView(_ p: NSPoint) -> NSPoint
    func opacityAppliedColor(for tool: AnnotationTool) -> NSColor
    var currentStrokeWidth: CGFloat { get }
    var annotations: [Annotation] { get set }
    var undoStack: [UndoEntry] { get set }
    var redoStack: [UndoEntry] { get set }
    var currentColor: NSColor { get }
}

/// Manages inline text editing for the text annotation tool.
/// Owns ALL text state: style, NSTextView lifecycle, formatting, commit, cancel.
@MainActor
class TextEditingController {

    private(set) var wrapsAtFixedWidth = false

    // MARK: - Text style state

    var fontSize: CGFloat = 20
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
    var alignment: NSTextAlignment = .left
    var fontFamily = "System"
    var bgEnabled = false
    var outlineEnabled = false
    var glyphStrokeEnabled = false
    var bgColor = NSColor.black.withAlphaComponent(0.5)
    var outlineColor = NSColor.white
    var glyphStrokeColor = NSColor.white

    init() {
        restoreDefaults()
    }

    func restoreDefaults() {
        let defaults = UserDefaults.standard
        fontSize = defaults.object(forKey: "textFontSize") as? CGFloat ?? 20
        fontFamily = defaults.string(forKey: "textFontFamily") ?? "System"
        bold = defaults.bool(forKey: "textBold")
        italic = defaults.bool(forKey: "textItalic")
        underline = defaults.bool(forKey: "textUnderline")
        strikethrough = defaults.bool(forKey: "textStrikethrough")
        alignment = NSTextAlignment(rawValue: defaults.integer(forKey: "textAlignment")) ?? .left
        bgEnabled = defaults.bool(forKey: "textBgEnabled")
        outlineEnabled = defaults.bool(forKey: "textOutlineEnabled")
        glyphStrokeEnabled = defaults.bool(forKey: "textGlyphStrokeEnabled")
        bgColor = savedColor("textBgColor", fallback: NSColor.black.withAlphaComponent(0.5))
        outlineColor = savedColor("textOutlineColor", fallback: .white)
        glyphStrokeColor = savedColor("textGlyphStrokeColor", fallback: .white)
    }

    private func savedColor(_ key: String, fallback: NSColor) -> NSColor {
        guard let data = UserDefaults.standard.data(forKey: key),
              let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        else { return fallback }
        return color
    }

    // MARK: - NSTextView

    private(set) var textView: ScopedUndoTextView?
    private(set) var scrollView: NSScrollView?

    var isEditing: Bool { textView != nil }

    /// The annotation being re-edited (removed from canvas, restored on cancel).
    var editingAnnotation: Annotation?

    // MARK: - Font construction

    func currentFont() -> NSFont {
        let fm = NSFontManager.shared
        let baseFont: NSFont
        if fontFamily == "System" {
            baseFont = NSFont.systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        } else if let font = NSFont(name: fontFamily, size: fontSize) {
            baseFont = bold ? fm.convert(font, toHaveTrait: .boldFontMask) : font
        } else {
            baseFont = NSFont.systemFont(ofSize: fontSize, weight: bold ? .bold : .regular)
        }
        if italic {
            return fm.convert(baseFont, toHaveTrait: .italicFontMask)
        }
        return baseFont
    }

    /// Apply bold/italic to a font, handling system fonts that NSFontManager can't convert via traits.
    func applyBoldItalic(to font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        let size = font.pointSize
        let familyName = font.familyName ?? "System"

        // System font: use NSFont.systemFont directly (NSFontManager can't convert SF traits)
        if familyName.hasPrefix(".") || familyName == "System" || fontFamily == "System" {
            var base: NSFont
            if bold && italic {
                base = NSFont.systemFont(ofSize: size, weight: .bold)
                let desc = base.fontDescriptor.withSymbolicTraits(.italic)
                base = NSFont(descriptor: desc, size: size) ?? base
            } else if bold {
                base = NSFont.systemFont(ofSize: size, weight: .bold)
            } else if italic {
                let regular = NSFont.systemFont(ofSize: size, weight: .regular)
                let desc = regular.fontDescriptor.withSymbolicTraits(.italic)
                base = NSFont(descriptor: desc, size: size) ?? regular
            } else {
                base = NSFont.systemFont(ofSize: size, weight: .regular)
            }
            return base
        }

        // Non-system fonts: use NSFontManager trait conversion
        let fm = NSFontManager.shared
        var result = font
        if bold {
            result = fm.convert(result, toHaveTrait: .boldFontMask)
        } else {
            result = fm.convert(result, toNotHaveTrait: .boldFontMask)
        }
        if italic {
            result = fm.convert(result, toHaveTrait: .italicFontMask)
        } else {
            result = fm.convert(result, toNotHaveTrait: .italicFontMask)
        }
        return result
    }

    // MARK: - Style toggles

    private func selectedOrAllRange() -> NSRange {
        guard let tv = textView else { return NSRange(location: 0, length: 0) }
        let sel = tv.selectedRange()
        if sel.length > 0 { return sel }
        return NSRange(location: 0, length: tv.textStorage?.length ?? 0)
    }

    func toggleBold() {
        bold.toggle()
        UserDefaults.standard.set(bold, forKey: "textBold")
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = selectedOrAllRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newFont = self.applyBoldItalic(to: font, bold: self.bold, italic: self.italic)
                    ts.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            ts.endEditing()
        }
        tv.typingAttributes[.font] = currentFont()
        tv.window?.makeFirstResponder(tv)
    }

    func toggleItalic() {
        italic.toggle()
        UserDefaults.standard.set(italic, forKey: "textItalic")
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = selectedOrAllRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newFont = self.applyBoldItalic(to: font, bold: self.bold, italic: self.italic)
                    ts.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            ts.endEditing()
        }
        tv.typingAttributes[.font] = currentFont()
        tv.window?.makeFirstResponder(tv)
    }

    func toggleUnderline() {
        underline.toggle()
        UserDefaults.standard.set(underline, forKey: "textUnderline")
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = selectedOrAllRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.underlineStyle, in: range) { value, attrRange, _ in
                let current = (value as? Int) ?? 0
                if current != 0 {
                    ts.removeAttribute(.underlineStyle, range: attrRange)
                } else {
                    ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: attrRange)
                }
            }
            ts.endEditing()
        }
        if underline {
            tv.typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        } else {
            tv.typingAttributes.removeValue(forKey: .underlineStyle)
        }
        tv.window?.makeFirstResponder(tv)
    }

    func toggleStrikethrough() {
        strikethrough.toggle()
        UserDefaults.standard.set(strikethrough, forKey: "textStrikethrough")
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = selectedOrAllRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.strikethroughStyle, in: range) { value, attrRange, _ in
                let current = (value as? Int) ?? 0
                if current != 0 {
                    ts.removeAttribute(.strikethroughStyle, range: attrRange)
                } else {
                    ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: attrRange)
                }
            }
            ts.endEditing()
        }
        if strikethrough {
            tv.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            tv.typingAttributes.removeValue(forKey: .strikethroughStyle)
        }
        tv.window?.makeFirstResponder(tv)
    }

    func applyAlignment() {
        UserDefaults.standard.set(alignment.rawValue, forKey: "textAlignment")
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = NSRange(location: 0, length: ts.length)
        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = alignment
        ts.beginEditing()
        ts.addAttribute(.paragraphStyle, value: paraStyle, range: range)
        ts.endEditing()
        tv.alignment = alignment
        tv.typingAttributes[.paragraphStyle] = paraStyle
        tv.window?.makeFirstResponder(tv)
    }

    func applyFontSizeChange() {
        guard let tv = textView else { return }
        let range = selectedOrAllRange()
        tv.textStorage?.addAttribute(.font, value: currentFont(), range: range)
    }

    func applyColorToLiveText(color: NSColor) {
        guard let tv = textView else { return }
        let range = selectedOrAllRange()
        if range.length > 0 {
            tv.textStorage?.addAttribute(.foregroundColor, value: color, range: range)
        }
        tv.insertionPointColor = color
        tv.typingAttributes[.foregroundColor] = color
    }

    // MARK: - Show / Create text view

    func show(in parentView: NSView, at canvasPoint: NSPoint, color: NSColor,
              existingText: NSAttributedString? = nil, existingFrame: NSRect = .zero,
              canvas: TextEditingCanvas) {
        dismiss()
        if editingAnnotation == nil && existingFrame == .zero { restoreDefaults() }
        wrapsAtFixedWidth = editingAnnotation?.textWrapsAtFixedWidth ?? (existingFrame != .zero)

        let viewPt = canvas.canvasToView(canvasPoint)
        let viewFrame: NSRect
        if existingFrame != .zero {
            viewFrame = NSRect(origin: canvas.canvasToView(existingFrame.origin), size: existingFrame.size)
        } else {
            let height = max(28, fontSize + 12)
            viewFrame = NSRect(x: viewPt.x, y: viewPt.y - height, width: 20, height: height)
        }

        let sv = NSScrollView(frame: viewFrame)
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.borderType = .noBorder

        // Build the text view on an OutlineTextLayoutManager so the per-glyph
        // outline renders outside the fill live, identically to the committed
        // image (issue #257).
        let textStorage = NSTextStorage()
        let layoutManager = OutlineTextRenderer.makeLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(
            width: viewFrame.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let tv = ScopedUndoTextView(frame: NSRect(origin: .zero, size: viewFrame.size),
                                    textContainer: textContainer)
        tv.isRichText = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.containerSize = NSSize(width: viewFrame.width - 8, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true

        let font = currentFont()
        tv.font = font
        tv.textColor = color
        tv.insertionPointColor = color

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.alignment = alignment

        if let existing = existingText {
            tv.textStorage?.setAttributedString(existing)
        }

        // Build typingAttributes with ALL current style state
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paraStyle,
        ]
        if underline {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if strikethrough {
            attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if glyphStrokeEnabled {
            attrs[.macshotOutlineColor] = glyphStrokeColor
        }
        tv.typingAttributes = attrs
        tv.alignment = alignment

        // Apply paragraph style + outline to any existing text. Normalize first
        // so a legacy centered stroke (baked into re-opened text) is converted
        // to the outside outline (#257).
        let range = NSRange(location: 0, length: tv.textStorage?.length ?? 0)
        if range.length > 0, let storage = tv.textStorage {
            OutlineTextRenderer.normalizeLegacyStroke(storage)
            storage.addAttribute(.paragraphStyle, value: paraStyle, range: range)
            OutlineTextRenderer.applyOutline(glyphStrokeEnabled ? glyphStrokeColor : nil,
                                             to: storage, range: range)
        }

        sv.documentView = tv
        parentView.addSubview(sv)

        self.scrollView = sv
        self.textView = tv

        parentView.window?.makeFirstResponder(tv)

        if existingText != nil { resizeToFit() }
    }

    // MARK: - Commit / Cancel

    /// Commit the current text editing to an annotation on the canvas.
    func commit(canvas: TextEditingCanvas) {
        guard let tv = textView, let sv = scrollView else { return }
        let text = tv.string
        if !text.isEmpty {
            // Ensure scrollView frame matches actual text height before snapshotting
            resizeToFit()
            let attrStr = NSAttributedString(attributedString: tv.textStorage!)
            let inset = tv.textContainerInset
            let drawWidth = sv.frame.width - inset.width * 2

            // Measure with NSAttributedString.boundingRect — this matches the
            // layout engine used by attrStr.draw(in:), which can differ from
            // NSLayoutManager.usedRect (used by resizeToFit for live editing).
            // Using the wrong measurement caused the last line to be clipped.
            let textBounds = attrStr.boundingRect(
                with: NSSize(width: drawWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            let minH = max(28, fontSize + 12)
            let imgHeight = max(minH, ceil(textBounds.height) + inset.height * 2)
            let imgWidth = sv.frame.width
            let imgSize = NSSize(width: imgWidth, height: imgHeight)

            // Update scrollView frame to match the measured size so canvas
            // coordinates are correct (pin top-left edge).
            let topEdge = sv.frame.maxY
            sv.frame = NSRect(x: sv.frame.minX, y: topEdge - imgHeight,
                              width: imgWidth, height: imgHeight)

            // Render through the outline layout manager so a per-glyph outline
            // is baked outside the fill, matching the live editor (#257).
            guard SavedCaptureValidation.canRenderText(size: imgSize) else {
                cancel(canvas: canvas)
                return
            }
            let img = OutlineTextRenderer.renderImage(attrStr, size: imgSize, inset: inset.width)

            let canvasOrigin = canvas.viewToCanvas(sv.frame.origin)
            let canvasEnd = canvas.viewToCanvas(NSPoint(x: sv.frame.maxX, y: sv.frame.maxY))
            let canvasFrame = NSRect(
                x: canvasOrigin.x, y: canvasOrigin.y,
                width: canvasEnd.x - canvasOrigin.x,
                height: canvasEnd.y - canvasOrigin.y)

            let annotation = Annotation(
                tool: .text,
                startPoint: canvasFrame.origin,
                endPoint: NSPoint(x: canvasFrame.maxX, y: canvasFrame.maxY),
                color: canvas.opacityAppliedColor(for: .text),
                strokeWidth: canvas.currentStrokeWidth)
            annotation.attributedText = attrStr
            annotation.text = text
            annotation.fontSize = fontSize
            annotation.isBold = bold
            annotation.isItalic = italic
            annotation.isUnderline = underline
            annotation.isStrikethrough = strikethrough
            annotation.fontFamilyName = fontFamily == "System" ? nil : fontFamily
            annotation.textBgColor = bgEnabled ? bgColor : nil
            annotation.textOutlineColor = outlineEnabled ? outlineColor : nil
            annotation.textGlyphStrokeColor = glyphStrokeEnabled ? glyphStrokeColor : nil
            annotation.textAlignment = alignment
            annotation.textImage = img
            annotation.textDrawRect = canvasFrame
            annotation.textWrapsAtFixedWidth = wrapsAtFixedWidth
            canvas.annotations.append(annotation)
            canvas.undoStack.append(.added(annotation))
            canvas.redoStack.removeAll()
        }
        editingAnnotation = nil
        sv.removeFromSuperview()
        dismiss()
    }

    /// Cancel editing, restoring the original annotation if re-editing.
    func cancel(canvas: TextEditingCanvas) {
        if let ann = editingAnnotation {
            canvas.annotations.append(ann)
            editingAnnotation = nil
        }
        scrollView?.removeFromSuperview()
        dismiss()
    }

    func dismiss() {
        // Do not leave text operations pointing at a view that is about to be
        // removed. The scoped manager normally dies with the view; clearing it
        // explicitly also makes repeated show/dismiss calls safe.
        textView?.discardUndoHistory()
        scrollView?.removeFromSuperview()
        scrollView = nil
        textView = nil
    }

    // MARK: - Resize

    func resizeWidth(to width: CGFloat) {
        guard let sv = scrollView else { return }
        wrapsAtFixedWidth = true
        sv.frame.size.width = max(40, width)
        resizeToFit()
    }

    /// Fit the text, keeping the insertion point's top-left anchor stable.
    func resizeToFit() {
        guard let tv = textView, let sv = scrollView else { return }
        guard let layoutManager = tv.layoutManager, let textContainer = tv.textContainer else { return }

        let inset = tv.textContainerInset
        let width: CGFloat
        if !wrapsAtFixedWidth, let text = tv.textStorage {
            width = OutlineTextRenderer.naturalWidth(text, inset: inset.width)
        } else {
            width = sv.frame.width
        }
        tv.frame.size.width = width
        textContainer.containerSize = NSSize(
            width: max(1, width - inset.width * 2), height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let extraHeight = layoutManager.extraLineFragmentRect.height

        let minH = max(28, fontSize + 12)
        let newHeight = max(minH, ceil(usedRect.height + extraHeight) + inset.height * 2)

        let topEdge = sv.frame.maxY
        sv.frame = NSRect(x: sv.frame.minX, y: topEdge - newHeight, width: width, height: newHeight)
        tv.frame.size = NSSize(width: width, height: newHeight)
    }

    /// Restore formatting state from an existing annotation for re-editing.
    func restoreState(from annotation: Annotation) {
        fontSize = annotation.fontSize
        bold = annotation.isBold
        italic = annotation.isItalic
        underline = annotation.isUnderline
        strikethrough = annotation.isStrikethrough
        fontFamily = annotation.fontFamilyName ?? "System"
        alignment = annotation.textAlignment
        bgEnabled = annotation.textBgColor != nil
        bgColor = annotation.textBgColor ?? savedColor("textBgColor", fallback: NSColor.black.withAlphaComponent(0.5))
        outlineEnabled = annotation.textOutlineColor != nil
        if let ol = annotation.textOutlineColor { outlineColor = ol }
        glyphStrokeEnabled = annotation.textGlyphStrokeColor != nil
        if let gs = annotation.textGlyphStrokeColor { glyphStrokeColor = gs }
    }

}
