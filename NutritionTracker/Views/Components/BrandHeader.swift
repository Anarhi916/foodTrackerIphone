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
        HStack(spacing: 0) {
            leading().foregroundColor(.white)
            // Left-aligned title next to the nav icon, like Android's TopAppBar (titleLarge 18/600).
            Text(title)
                .font(AppFont.roboto(18, .semibold, relativeTo: .headline))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.leading, leadingHasContent ? 4 : 0)
            Spacer(minLength: 8)
            trailing().foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(AppColor.primary)
    }

    private var leadingHasContent: Bool { Leading.self != EmptyView.self }
}
