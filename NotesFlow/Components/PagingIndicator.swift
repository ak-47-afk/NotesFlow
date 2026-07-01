import SwiftUI

struct PagingIndicator: View {
    var numberOfPages: Int
    var currentPage: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<numberOfPages, id: \.self) { index in
                if index == currentPage {
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: 24, height: 6)
                        .animation(.spring(), value: currentPage)
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .animation(.spring(), value: currentPage)
                }
            }
        }
    }
}
