import SwiftUI

public struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showPhoneAuthAlert: Bool = false
    @State private var showEmailAuthSheet: Bool = false

    public init(viewModel: AuthViewModel, startInEmailLogin: Bool = false) {
        self.viewModel = viewModel
        self._showEmailAuthSheet = State(initialValue: startInEmailLogin)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // 1. Full-screen Cinematic Dark Background
                Color.black
                    .ignoresSafeArea()

                Image("CinematicSignInBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                // 2. Cinematic Gradient Overlay (Darkens lower half for text & button legibility)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.15), location: 0.38),
                        .init(color: .black.opacity(0.65), location: 0.58),
                        .init(color: .black.opacity(0.95), location: 0.74),
                        .init(color: .black, location: 0.86)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .ignoresSafeArea()

                // 3. Foreground Content (Aligned to lower portion matching reference)
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    // Optional Error Message Banner
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 14))

                            Text(error)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)

                            Spacer()

                            Button(action: {
                                viewModel.errorMessage = nil
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Header & Description
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in")
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(Color.lumaYellowAccent)

                        Text("Sign in with any of your Google account or phone and\nset your password through app.")
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.88))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)

                    // Buttons Group
                    VStack(spacing: 14) {
                        // Continue with Google Button
                        CinematicPillButton(
                            title: "Continue with Google",
                            iconType: .google,
                            isLoading: viewModel.isGoogleLoading
                        ) {
                            HapticFeedback.light()
                            Task {
                                await viewModel.signInWithGoogle()
                            }
                        }
                        .disabled(viewModel.isLoading || viewModel.isGoogleLoading)

                        // Continue with Phone Button
                        CinematicPillButton(
                            title: "Continue with Phone",
                            iconType: .phone,
                            isLoading: false
                        ) {
                            HapticFeedback.light()
                            showPhoneAuthAlert = true
                        }
                        .disabled(viewModel.isLoading || viewModel.isGoogleLoading)
                    }
                    .padding(.horizontal, 24)

                    // Subtle Email Sign-In Option
                    Button(action: {
                        HapticFeedback.selection()
                        showEmailAuthSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Text("Or continue with email")
                                .foregroundColor(.white.opacity(0.50))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .font(LumaTypography.captionMedium)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 8 : 24)
                }
                .frame(width: geometry.size.width)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .alert("Phone Sign-In", isPresented: $showPhoneAuthAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Phone number authentication requires an SMS OTP gateway which is not yet configured on the server. Please sign in with Google or your email account.")
        }
        .fullScreenCover(isPresented: $showEmailAuthSheet) {
            CinematicLoginView(viewModel: viewModel, isPresented: $showEmailAuthSheet)
        }
    }
}

// MARK: - Cinematic Login Screen (Matches Target Reference Image 2)

public struct CinematicLoginView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Binding var isPresented: Bool

    @State private var isPasswordVisible: Bool = false
    @State private var showForgotPasswordDialog: Bool = false
    @State private var resetEmailInput: String = ""

    public init(viewModel: AuthViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // 1. Full-screen Cinematic Dark Background
                Color.black
                    .ignoresSafeArea()

                Image("CinematicSignInBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .ignoresSafeArea()

                // 2. Cinematic Gradient Overlay (Tuned for contrast and low-key portrait view)
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black.opacity(0.10), location: 0.24),
                        .init(color: .black.opacity(0.50), location: 0.38),
                        .init(color: .black.opacity(0.94), location: 0.48),
                        .init(color: .black, location: 0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .ignoresSafeArea()

                // 3. Scrollable Content Layer
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Top spacing to position header below the man with glowing phone
                        Spacer(minLength: max(340, geometry.size.height * 0.41))

                        // Header (Welcome Back / Create Account)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.mode == .signIn ? "Welcome Back" : "Create Account")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(Color.lumaYellowAccent)

                            Text(viewModel.mode == .signIn
                                 ? "Log in to continue your\nthoughtful conversations."
                                 : "Join Luma AI to explore, think,\nand create.")
                                .font(.system(size: 14.5, weight: .regular))
                                .foregroundColor(.white.opacity(0.88))
                                .lineSpacing(3.5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 22)

                        // Error Banner (if any)
                        if let error = viewModel.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 13))

                                Text(error)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(2)

                                Spacer()

                                Button(action: {
                                    viewModel.errorMessage = nil
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                        }

                        // Success/Status Banner (e.g. Password Reset)
                        if let status = viewModel.statusMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 13))

                                Text(status)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(2)

                                Spacer()

                                Button(action: {
                                    viewModel.statusMessage = nil
                                }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.green.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                        }

                        // Form Fields
                        VStack(spacing: 14) {
                            if viewModel.mode == .register {
                                CinematicDarkField(title: "Full Name") {
                                    HStack {
                                        TextField("", text: $viewModel.fullName, prompt: Text(verbatim: "e.g. Jane Doe").foregroundColor(.white.opacity(0.35)))
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(.white)
                                            .tint(Color.lumaYellowAccent)
                                            .textContentType(.name)
                                            .autocapitalization(.words)

                                        Image(systemName: "person")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white.opacity(0.45))
                                    }
                                }
                            }

                            // Email Address Field
                            CinematicDarkField(title: "Email Address") {
                                HStack {
                                    TextField("", text: $viewModel.email, prompt: Text(verbatim: "you@example.com").foregroundColor(.white.opacity(0.35)))
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundColor(.white)
                                        .tint(Color.lumaYellowAccent)
                                        .keyboardType(.emailAddress)
                                        .textContentType(.emailAddress)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)

                                    Image(systemName: "envelope")
                                        .font(.system(size: 16))
                                        .foregroundColor(.white.opacity(0.45))
                                }
                            }

                            // Password Field with working Eye toggle
                            CinematicDarkField(title: "Password") {
                                HStack {
                                    if isPasswordVisible {
                                        TextField("", text: $viewModel.password, prompt: Text(verbatim: "Enter your password").foregroundColor(.white.opacity(0.35)))
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(.white)
                                            .tint(Color.lumaYellowAccent)
                                            .textContentType(viewModel.mode == .signIn ? .password : .newPassword)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                    } else {
                                        SecureField("", text: $viewModel.password, prompt: Text(verbatim: "Enter your password").foregroundColor(.white.opacity(0.35)))
                                            .font(.system(size: 15, weight: .regular))
                                            .foregroundColor(.white)
                                            .tint(Color.lumaYellowAccent)
                                            .textContentType(viewModel.mode == .signIn ? .password : .newPassword)
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                    }

                                    Button(action: {
                                        isPasswordVisible.toggle()
                                    }) {
                                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white.opacity(0.45))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 24)

                        // Remember Me & Forgot Password Row
                        HStack {
                            Button(action: {
                                HapticFeedback.selection()
                                viewModel.rememberMe.toggle()
                            }) {
                                HStack(spacing: 8) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(Color.white.opacity(0.40), lineWidth: 1.5)
                                            .frame(width: 18, height: 18)

                                        if viewModel.rememberMe {
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .fill(Color.lumaYellowAccent)
                                                .frame(width: 18, height: 18)
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.black)
                                        }
                                    }

                                    Text("Remember me")
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.white.opacity(0.85))
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(action: {
                                HapticFeedback.light()
                                resetEmailInput = viewModel.email
                                showForgotPasswordDialog = true
                            }) {
                                Text("Forgot password?")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color.lumaYellowAccent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                        .padding(.bottom, 22)

                        // Primary Action Button (Log In / Sign Up)
                        Button(action: {
                            HapticFeedback.medium()
                            if !viewModel.isFormValid {
                                if viewModel.email.trimmingCharacters(in: .whitespaces).isEmpty {
                                    viewModel.errorMessage = "Please enter your email address."
                                    return
                                }
                                if viewModel.password.isEmpty {
                                    viewModel.errorMessage = "Please enter your password."
                                    return
                                }
                                if viewModel.password.count < 6 {
                                    viewModel.errorMessage = "Password must be at least 6 characters."
                                    return
                                }
                                return
                            }
                            Task {
                                await viewModel.submit()
                                if viewModel.errorMessage == nil {
                                    isPresented = false
                                }
                            }
                        }) {
                            ZStack {
                                Capsule()
                                    .fill(Color.lumaYellowAccent)

                                if viewModel.isLoading {
                                    ProgressView()
                                        .tint(.black)
                                } else {
                                    Text(viewModel.mode == .signIn ? "Log In" : "Sign Up")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.black)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)

                        // OR Separator
                        HStack(spacing: 16) {
                            Rectangle()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 1)
                            Text("OR")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.45))
                            Rectangle()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)

                        // Continue with Google Button
                        Button(action: {
                            HapticFeedback.light()
                            Task {
                                await viewModel.signInWithGoogle()
                                if viewModel.errorMessage == nil {
                                    isPresented = false
                                }
                            }
                        }) {
                            ZStack {
                                Capsule()
                                    .fill(Color(white: 0.05))
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                    )

                                if viewModel.isGoogleLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    HStack(spacing: 0) {
                                        HStack(spacing: 0) {
                                            Spacer()
                                            GoogleIconView()
                                            Spacer()
                                        }
                                        .frame(width: 58)

                                        Rectangle()
                                            .fill(Color.white.opacity(0.22))
                                            .frame(width: 1, height: 20)

                                        Text("Continue with Google")
                                            .font(.system(size: 15.5, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.leading, 18)

                                        Spacer()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isLoading || viewModel.isGoogleLoading)
                        .padding(.horizontal, 24)

                        // Footer (Sign up / Log in link)
                        Button(action: {
                            HapticFeedback.selection()
                            viewModel.toggleMode()
                        }) {
                            HStack(spacing: 5) {
                                Text(viewModel.mode == .signIn ? "Don't have an account?" : "Already have an account?")
                                    .foregroundColor(.white.opacity(0.65))
                                Text(viewModel.mode == .signIn ? "Sign up" : "Log in")
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color.lumaYellowAccent)
                            }
                            .font(.system(size: 13, weight: .regular))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 22)
                        .padding(.bottom, max(32, geometry.safeAreaInsets.bottom + 16))
                        .frame(maxWidth: .infinity)
                    }
                    .frame(width: geometry.size.width)
                }
                .scrollDismissesKeyboard(.interactively)

                // 4. Fixed Top Header with < Back Button (Positioned safely below status bar)
                HStack {
                    Button(action: {
                        HapticFeedback.light()
                        isPresented = false
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16, weight: .regular))
                        }
                        .foregroundColor(.white)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .alert("Forgot Password", isPresented: $showForgotPasswordDialog) {
            TextField("you@example.com", text: $resetEmailInput)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)

            Button("Cancel", role: .cancel) { }
            Button("Send Reset Link") {
                Task {
                    _ = await viewModel.requestPasswordReset(emailToReset: resetEmailInput)
                }
            }
        } message: {
            Text("Enter your account email address to receive password reset instructions.")
        }
    }
}

// Retain EmailAuthSheet as an alias for backwards compatibility
public typealias EmailAuthSheet = CinematicLoginView

// MARK: - Cinematic Dark Input Field Container

public struct CinematicDarkField<Content: View>: View {
    let title: String
    let trailingContent: Content

    public init(title: String, @ViewBuilder trailingContent: () -> Content) {
        self.title = title
        self.trailingContent = trailingContent()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundColor(.white.opacity(0.55))

            trailingContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 58)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Cinematic Pill Button

public enum CinematicButtonIcon {
    case google
    case phone
}

public struct CinematicPillButton: View {
    let title: String
    let iconType: CinematicButtonIcon
    let isLoading: Bool
    let action: () -> Void

    public init(
        title: String,
        iconType: CinematicButtonIcon,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.iconType = iconType
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                // Capsule Background
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.black)
                        Spacer()
                    }
                } else {
                    HStack(spacing: 0) {
                        // Left Icon Area
                        HStack(spacing: 0) {
                            Spacer()
                            Group {
                                switch iconType {
                                case .google:
                                    GoogleIconView()
                                case .phone:
                                    PhoneIconView()
                                }
                            }
                            Spacer()
                        }
                        .frame(width: 62)

                        // Vertical Divider
                        Rectangle()
                            .fill(Color(white: 0.84))
                            .frame(width: 1, height: 22)

                        // Button Label (Both buttons align perfectly)
                        Text(title)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.leading, 18)

                        Spacer()
                    }
                }
            }
            .frame(height: 54)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Phone Icon

public struct PhoneIconView: View {
    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .stroke(Color.black, lineWidth: 1.8)
            .frame(width: 13.5, height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.black)
                    .frame(width: 5, height: 1.5)
                    .padding(.bottom, 2.5),
                alignment: .bottom
            )
    }
}

// MARK: - Google Icon

public struct GoogleIconView: View {
    public init() {}

    public var body: some View {
        if UIImage(named: "GoogleLogo") != nil {
            Image("GoogleLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        } else {
            GoogleLogoCanvas()
                .frame(width: 20, height: 20)
        }
    }
}

public struct GoogleLogoCanvas: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2
            let radius = min(w, h) / 2 * 0.9
            let lineWidth = radius * 0.4

            let blue = Color(red: 66/255, green: 133/255, blue: 244/255)
            let red = Color(red: 234/255, green: 67/255, blue: 53/255)
            let yellow = Color(red: 251/255, green: 188/255, blue: 5/255)
            let green = Color(red: 52/255, green: 168/255, blue: 83/255)

            var redPath = Path()
            redPath.addArc(center: CGPoint(x: cx, y: cy), radius: radius - lineWidth / 2, startAngle: .degrees(-135), endAngle: .degrees(-30), clockwise: false)
            context.stroke(redPath, with: .color(red), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

            var yellowPath = Path()
            yellowPath.addArc(center: CGPoint(x: cx, y: cy), radius: radius - lineWidth / 2, startAngle: .degrees(-225), endAngle: .degrees(-135), clockwise: false)
            context.stroke(yellowPath, with: .color(yellow), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

            var greenPath = Path()
            greenPath.addArc(center: CGPoint(x: cx, y: cy), radius: radius - lineWidth / 2, startAngle: .degrees(-330), endAngle: .degrees(-225), clockwise: false)
            context.stroke(greenPath, with: .color(green), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

            var bluePath = Path()
            bluePath.addArc(center: CGPoint(x: cx, y: cy), radius: radius - lineWidth / 2, startAngle: .degrees(-30), endAngle: .degrees(0), clockwise: false)
            context.stroke(bluePath, with: .color(blue), style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))

            var barPath = Path()
            barPath.addRect(CGRect(x: cx - 1, y: cy - lineWidth / 2, width: radius + 1, height: lineWidth))
            context.fill(barPath, with: .color(blue))
        }
    }
}
