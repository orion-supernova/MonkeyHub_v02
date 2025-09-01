import SwiftUI

struct CustomBottomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    let content: Content
    var background: Color = .white
    var cornerRadius: CGFloat = 20

    init(isPresented: Binding<Bool>, background: Color = .white, cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self._isPresented = isPresented
        self.background = background
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        VStack {
            Spacer()
            VStack {
                Capsule()
                    .frame(width: 40, height: 6)
                    .foregroundColor(.gray)
                    .padding(.top, 8)

                content
            }
            .frame(maxWidth: .infinity)
            .background(background)
            .cornerRadius(cornerRadius)
            .offset(y: isPresented ? 0 : UIScreen.main.bounds.height)
            .animation(.spring(), value: isPresented)
        }
        .ignoresSafeArea()
        .background(
            Color.black.opacity(isPresented ? 0.3 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
                .animation(.easeOut(duration: 0.3), value: isPresented)
        )
    }
}
