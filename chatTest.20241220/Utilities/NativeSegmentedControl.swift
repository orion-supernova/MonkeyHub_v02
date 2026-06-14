import SwiftUI

#if canImport(UIKit)
import UIKit

/// A native `UISegmentedControl` whose height is settable. SwiftUI's `Picker(.pickerStyle(.segmented))`
/// ignores `.frame(height:)` because `UISegmentedControl` has a fixed intrinsic height — wrapping it
/// and overriding `intrinsicContentSize` is the proper way to resize it. This is the same control
/// SwiftUI uses, so it keeps the native iOS 26 Liquid Glass draggable handle (press a segment and
/// slide between them).
struct NativeSegmentedControl<Value: Hashable>: UIViewRepresentable {
    @Binding var selection: Value
    let items: [(value: Value, title: String)]
    var height: CGFloat = 44
    /// When set, the selected segment is filled with this color so it can match tinted/prominent
    /// glass buttons elsewhere. IMPORTANT: setting this forces `UISegmentedControl` into its LEGACY
    /// flat filled style — it loses the iOS 26 Liquid Glass frosted handle. Leave nil to keep the
    /// native glass handle as the selected indicator.
    var selectedTint: Color?
    /// Color for the unselected segment titles. Needed when the control sits on a colored
    /// background (e.g. the header gradient) where the default label color reads poorly.
    var normalTitleColor: Color?
    /// Color for the selected segment title. Independent of `selectedTint` so the native glass handle
    /// can keep a readable (e.g. white) title without forcing the legacy filled style.
    var selectedTitleColor: Color?
    /// Clears the control's own track/divider so a glass effect placed BEHIND it (e.g. a SwiftUI
    /// `.glassEffect(in: .capsule)`) shows as the whole-control background, with the native handle
    /// remaining as the selected indicator.
    var clearsBackground: Bool = false

    func makeUIView(context: Context) -> ResizableSegmentedControl {
        let control = ResizableSegmentedControl(items: items.map(\.title))
        control.preferredHeight = height
        control.selectedSegmentIndex = index(of: selection)
        control.addTarget(context.coordinator,
                          action: #selector(Coordinator.valueChanged(_:)),
                          for: .valueChanged)
        if clearsBackground {
            control.backgroundColor = .clear
            control.setBackgroundImage(UIImage(), for: .normal, barMetrics: .default)
            control.setDividerImage(UIImage(),
                                    forLeftSegmentState: .normal,
                                    rightSegmentState: .normal,
                                    barMetrics: .default)
        }
        applyTint(control)
        return control
    }

    func updateUIView(_ control: ResizableSegmentedControl, context: Context) {
        context.coordinator.parent = self
        // Keep titles in sync (e.g. the Requests count) without rebuilding segments.
        for (i, item) in items.enumerated() where i < control.numberOfSegments {
            if control.titleForSegment(at: i) != item.title {
                control.setTitle(item.title, forSegmentAt: i)
            }
        }
        let idx = index(of: selection)
        if control.selectedSegmentIndex != idx { control.selectedSegmentIndex = idx }
        if control.preferredHeight != height {
            control.preferredHeight = height
            control.invalidateIntrinsicContentSize()
        }
        applyTint(control)
    }

    private func applyTint(_ control: UISegmentedControl) {
        let font = UIFont.preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        if let selectedTint {
            // Translucent — a fully opaque selectedSegmentTintColor kills the Liquid Glass; with
            // alpha the glass/background refracts through, so it reads as tinted glass, not flat.
            // (Setting this at all still drops to the legacy filled look — see property doc.)
            control.selectedSegmentTintColor = UIColor(selectedTint).withAlphaComponent(0.9)
        }
        if let normalTitleColor {
            control.setTitleTextAttributes([.foregroundColor: UIColor(normalTitleColor), .font: font], for: .normal)
        }
        if let selectedTitleColor {
            control.setTitleTextAttributes([.foregroundColor: UIColor(selectedTitleColor), .font: font], for: .selected)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private func index(of value: Value) -> Int {
        items.firstIndex { $0.value == value } ?? 0
    }

    final class Coordinator: NSObject {
        var parent: NativeSegmentedControl
        init(_ parent: NativeSegmentedControl) { self.parent = parent }
        @objc func valueChanged(_ sender: UISegmentedControl) {
            let i = sender.selectedSegmentIndex
            guard i >= 0, i < parent.items.count else { return }
            parent.selection = parent.items[i].value
        }
    }
}

private extension UIFont {
    /// Returns the same font (size/metrics preserved, so Dynamic Type still scales) at a new weight.
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// `UISegmentedControl` that reports a custom height so SwiftUI lays it out taller.
final class ResizableSegmentedControl: UISegmentedControl {
    var preferredHeight: CGFloat = 44
    override var intrinsicContentSize: CGSize {
        var size = super.intrinsicContentSize
        size.height = preferredHeight
        return size
    }
}
#endif
