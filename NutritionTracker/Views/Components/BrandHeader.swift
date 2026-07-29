import SwiftUI

// Кастомный зелёный хедер (как Android TopAppBar): ровный брендовый зелёный (AppColor.primary #1B9E3E), белые иконки БЕЗ
// системных glass-капсул iOS 26. Заменяет системный navigation bar на всех экранах.
// Использование: обернуть контент в VStack(spacing:0){ BrandHeader(...) ; content }
// и скрыть системный бар через .navigationBarHidden(true).
struct BrandHeader<Leading: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String,
         @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            HStack {
                leading().foregroundColor(.white)
                Spacer()
                trailing().foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(AppColor.primary)
    }
}
