import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(isEnabled ? Color.blue : Color.blue.opacity(0.5))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.primary)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Color.clear)
            .overlay(
                Capsule()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

struct CircularIconBackground: ViewModifier {
    var color: Color
    var size: CGFloat = 80
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: size * 0.4))
            .foregroundColor(color == .white ? .blue : .white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
    }
}

struct RoundedSquareIconBackground: ViewModifier {
    var color: Color
    var size: CGFloat = 80
    var cornerRadius: CGFloat = 20
    
    func body(content: Content) -> some View {
        content
            .font(.system(size: size * 0.4))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
