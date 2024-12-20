import SwiftUI

struct ICloudErrorView: View {
    let message: String
    let openSettings: () -> Void
    
    @EnvironmentObject private var cloudKitManager: CloudKitManager

    init(
        message: String,
        openSettings: @escaping () -> Void = {
            
#if os(iOS)
if let settingsUrl = URL(string: "App-prefs:") {
    UIApplication.shared.open(settingsUrl, options: [:], completionHandler: nil)
}
#elseif os(macOS)
    // macOS doesn't have a direct way to open system settings
    // You can show an alert or guide the user manually to open System Preferences
    print("macOS doesn't have a direct way to open system settings.")
#endif
        }
    ) {
        self.message = message
        self.openSettings = openSettings
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 60))
                .foregroundColor(.red)

            Text("iCloud Required")
                .font(.title)
                .bold()

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: openSettings) {
                Text("Open Settings")
                    .bold()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .padding()
    }
}
