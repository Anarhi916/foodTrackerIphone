import SwiftUI

// Custom green header (like Android's TopAppBar): a flat brand green (AppColor.primary #1B9E3E), white icons WITHOUT
// the iOS 26 system glass capsules. Replaces the system navigation bar on all screens.
// Usage: wrap content in VStack(spacing:0){ BrandHeader(...) ; content }
// and hide the system bar via .navigationBarHidden(true).
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
