import SwiftUI

public struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var isPasswordVisible: Bool = false
    @State private var showForgotPasswordDialog: Bool = false
    @State private var resetEmailInput: String = ""
    @FocusState private var focusedField: AuthField?

    enum AuthField: Hashable {
        case fullName
        case email
        case password
    }

    public init(viewModel: AuthViewModel, startInEmailLogin: Bool = false) {
        self.viewModel = viewModel
    }

    private func hideKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Orbix Studio Lavender-tinted background
                OrbixBackgroundView()
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: max(24, geometry.safeAreaInsets.top + 10))

                        // Luma AI Brand Emblem
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.orbixPurple)
                                    .frame(width: 58, height: 58)
                                    .shadow(color: Color.orbixPurple.opacity(0.35), radius: 12, x: 0, y: 6)

                                Image(systemName: "sparkle")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            VStack(spacing: 6) {
                                Text(viewModel.mode == .signIn ? "Welcome Back" : "Create Account")
                                    .font(.system(size: 32, weight: .bold))
                                    .foregroundColor(Color.orbixPrimaryText)

                                Text(viewModel.mode == .signIn
                                     ? "Log in to continue your thoughtful conversations."
                                     : "Join Luma AI to explore, think, and create.")
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(Color.orbixSecondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 28)
                            }
                        }
                        .padding(.bottom, 28)

                        // Error Banner if present
                        if let error = viewModel.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(Color.lumaError)
                                    .font(.system(size: 14))

                                Text(error)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(Color.lumaError)
                                    .lineLimit(2)

                                Spacer()

                                Button(action: {
                                    viewModel.errorMessage = nil
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color.orbixSecondaryText)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.lumaError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                        }

                        // Status Banner (e.g. Password Reset link sent)
                        if let status = viewModel.statusMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color.lumaSuccess)
                                    .font(.system(size: 14))

                                Text(status)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(Color.lumaSuccess)
                                    .lineLimit(2)

                                Spacer()

                                Button(action: {
                                    viewModel.statusMessage = nil
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Color.orbixSecondaryText)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.lumaSuccess.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                        }

                        // Form Card (White with subtle border and soft shadow)
                        VStack(spacing: 16) {
                            if viewModel.mode == .register {
                                orbixInputField(
                                    title: "Full Name",
                                    icon: "person",
                                    placeholder: "e.g. Jane Doe"
                                ) {
                                    TextField("", text: $viewModel.fullName)
                                        .focused($focusedField, equals: .fullName)
                                        .textContentType(.name)
                                        .autocapitalization(.words)
                                }
                            }

                            // Email Field
                            orbixInputField(
                                title: "Email Address",
                                icon: "envelope",
                                placeholder: "you@example.com"
                            ) {
                                TextField("", text: $viewModel.email)
                                    .focused($focusedField, equals: .email)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .autocorrectionDisabled(true)
                            }

                            // Password Field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Password")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.orbixSecondaryText)

                                HStack(spacing: 10) {
                                    Image(systemName: "lock")
                                        .font(.system(size: 15))
                                        .foregroundColor(Color.orbixSecondaryText)

                                    if isPasswordVisible {
                                        TextField("", text: $viewModel.password)
                                            .focused($focusedField, equals: .password)
                                            .autocapitalization(.none)
                                            .autocorrectionDisabled(true)
                                    } else {
                                        SecureField("", text: $viewModel.password)
                                            .focused($focusedField, equals: .password)
                                            .textContentType(.password)
                                            .autocapitalization(.none)
                                            .autocorrectionDisabled(true)
                                    }

                                    Button(action: {
                                        isPasswordVisible.toggle()
                                    }) {
                                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                            .font(.system(size: 15))
                                            .foregroundColor(Color.orbixSecondaryText)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background(Color.orbixBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.orbixCardBorder, lineWidth: 1)
                                )
                            }

                            // Remember Me & Forgot Password Row
                            HStack {
                                Button(action: {
                                    HapticFeedback.light()
                                    viewModel.rememberMe.toggle()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: viewModel.rememberMe ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 15))
                                            .foregroundColor(viewModel.rememberMe ? Color.orbixPurple : Color.orbixSecondaryText)
                                        Text("Remember me")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(Color.orbixSecondaryText)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                if viewModel.mode == .signIn {
                                    Button(action: {
                                        HapticFeedback.light()
                                        resetEmailInput = viewModel.email
                                        showForgotPasswordDialog = true
                                    }) {
                                        Text("Forgot password?")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(Color.orbixPurple)
                                    }
                                }
                            }
                            .padding(.top, 4)

                            // Primary Action Button (Black Pill)
                            Button(action: {
                                HapticFeedback.medium()
                                hideKeyboard()
                                Task {
                                    await viewModel.submit()
                                }
                            }) {
                                submitButtonContent
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(Color.orbixBlackPill)
                                    .clipShape(Capsule())
                                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)
                            }
                            .buttonStyle(PillPressStyle())
                            .disabled(viewModel.isLoading || viewModel.isGoogleLoading)
                            .padding(.top, 6)

                            // OR Separator
                            HStack(spacing: 12) {
                                Rectangle()
                                    .fill(Color.orbixCardBorder)
                                    .frame(height: 1)
                                Text("OR")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color.orbixSecondaryText)
                                Rectangle()
                                    .fill(Color.orbixCardBorder)
                                    .frame(height: 1)
                            }
                            .padding(.vertical, 4)

                            // Continue with Google Button
                            Button(action: {
                                HapticFeedback.light()
                                hideKeyboard()
                                Task {
                                    await viewModel.signInWithGoogle()
                                }
                            }) {
                                HStack(spacing: 10) {
                                    if viewModel.isGoogleLoading {
                                        ProgressView().tint(Color.orbixPrimaryText)
                                    } else {
                                        GoogleLogoView()
                                            .frame(width: 18, height: 18)
                                        Text("Continue with Google")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(Color.orbixPrimaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(Color.orbixCardBorder, lineWidth: 1.2)
                                )
                                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
                            }
                            .buttonStyle(PillPressStyle())
                            .disabled(viewModel.isLoading || viewModel.isGoogleLoading)
                        }
                        .padding(22)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.orbixCardBorder, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
                        .padding(.horizontal, 20)

                        // Toggle Mode Footer
                        Button(action: {
                            HapticFeedback.light()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                viewModel.mode = viewModel.mode == .signIn ? .register : .signIn
                                viewModel.errorMessage = nil
                                viewModel.statusMessage = nil
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(viewModel.mode == .signIn ? "Don't have an account?" : "Already have an account?")
                                    .foregroundColor(Color.orbixSecondaryText)
                                Text(viewModel.mode == .signIn ? "Sign up" : "Log in")
                                    .fontWeight(.bold)
                                    .foregroundColor(Color.orbixPurple)
                            }
                            .font(.system(size: 14))
                        }
                        .padding(.top, 24)
                        .padding(.bottom, max(30, geometry.safeAreaInsets.bottom + 16))
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .sheet(isPresented: $showForgotPasswordDialog) {
            forgotPasswordSheet
        }
    }

    private func orbixInputField<Content: View>(
        title: String,
        icon: String,
        placeholder: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.orbixSecondaryText)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(Color.orbixSecondaryText)

                content()
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color.orbixPrimaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.orbixBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orbixCardBorder, lineWidth: 1)
            )
        }
    }

    private var submitButtonContent: some View {
        HStack(spacing: 8) {
            if viewModel.isLoading {
                ProgressView().tint(.white)
            } else {
                Text(viewModel.mode == .signIn ? "Log In" : "Create Account")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    private var forgotPasswordSheet: some View {
        ZStack {
            OrbixBackgroundView().ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Text("Reset Password")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.orbixPrimaryText)
                    Spacer()
                    Button(action: { showForgotPasswordDialog = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color.orbixSecondaryText)
                    }
                }
                .padding(.top, 10)

                Text("Enter your email address and we'll send you instructions to reset your password.")
                    .font(.system(size: 14))
                    .foregroundColor(Color.orbixSecondaryText)
                    .lineSpacing(3)

                orbixInputField(
                    title: "Email Address",
                    icon: "envelope",
                    placeholder: "you@example.com"
                ) {
                    TextField("", text: $resetEmailInput)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }

                Button(action: {
                    HapticFeedback.medium()
                    Task {
                        _ = await viewModel.requestPasswordReset(emailToReset: resetEmailInput)
                        showForgotPasswordDialog = false
                    }
                }) {
                    Text("Send Reset Link")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.orbixBlackPill)
                        .clipShape(Capsule())
                }
                .buttonStyle(PillPressStyle())

                Spacer()
            }
            .padding(24)
        }
        .presentationDetents([.fraction(0.48), .medium])
    }
}

// MARK: - Official Google G Logo Vector
struct GoogleLogoView: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            let lineWidth = radius * 0.44

            // Blue arc (top-right to right)
            var bluePath = Path()
            bluePath.addArc(center: center, radius: radius - lineWidth/2, startAngle: .degrees(-45), endAngle: .degrees(45), clockwise: false)
            context.stroke(bluePath, with: .color(Color(red: 66/255, green: 133/255, blue: 244/255)), lineWidth: lineWidth)

            // Green arc (bottom to right)
            var greenPath = Path()
            greenPath.addArc(center: center, radius: radius - lineWidth/2, startAngle: .degrees(45), endAngle: .degrees(135), clockwise: false)
            context.stroke(greenPath, with: .color(Color(red: 52/255, green: 168/255, blue: 83/255)), lineWidth: lineWidth)

            // Yellow arc (bottom-left to left)
            var yellowPath = Path()
            yellowPath.addArc(center: center, radius: radius - lineWidth/2, startAngle: .degrees(135), endAngle: .degrees(225), clockwise: false)
            context.stroke(yellowPath, with: .color(Color(red: 251/255, green: 188/255, blue: 5/255)), lineWidth: lineWidth)

            // Red arc (top-left to top-right)
            var redPath = Path()
            redPath.addArc(center: center, radius: radius - lineWidth/2, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false)
            context.stroke(redPath, with: .color(Color(red: 234/255, green: 67/255, blue: 53/255)), lineWidth: lineWidth)

            // Center bar of G
            var barPath = Path()
            barPath.move(to: CGPoint(x: center.x, y: center.y))
            barPath.addLine(to: CGPoint(x: center.x + radius - lineWidth/2, y: center.y))
            context.stroke(barPath, with: .color(Color(red: 66/255, green: 133/255, blue: 244/255)), lineWidth: lineWidth)
        }
    }
}
