import SwiftUI
import AuthenticationServices

// Login screen. Required before onboarding/main (see the plan — accounts phase).
// Apple/Google buttons follow the providers' branding guidelines.
struct LoginScreen: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader(L("Вход"))

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // Logo — a leaf in a green circle (shared vector with Android).
                    VStack(spacing: 8) {
                        Image("LoginLogo")
                            .resizable()
                            .frame(width: 88, height: 88)
                        Text("Nutrition Tracker")
                            .font(.title).bold()
                        Text("Войдите, чтобы сохранить прогресс и подписку")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 20)

                    VStack(spacing: 12) {
                        // ─── Sign in with Apple: black button, white logo + text ───
                        Button(action: { auth.signInWithApple() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "applelogo")
                                    .font(.system(size: 18, weight: .medium))
                                Text("Вход с Apple")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .foregroundColor(.white)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black))
                        }

                        // ─── Sign in with Google: white button, gray border, colored G ───
                        Button(action: { auth.signInWithGoogle() }) {
                            HStack(spacing: 10) {
                                Image("GoogleG")
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                Text("Войти через Google")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(Color(red: 0x1F/255, green: 0x1F/255, blue: 0x1F/255))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Color(red: 0x74/255, green: 0x77/255, blue: 0x75/255), lineWidth: 1)
                                    )
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .disabled(auth.isBusy)

                    if auth.isBusy {
                        ProgressView().padding(.top, 4)
                    }
                    if let err = auth.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: .infinity)
            }
            .background(AppColor.background)
        }
        .navigationBarHidden(true)
    }
}
