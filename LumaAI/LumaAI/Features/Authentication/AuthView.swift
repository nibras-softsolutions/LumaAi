import SwiftUI

public struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var showPhoneAuthAlert: Bool = false
    @State private var showEmailAuthSheet: Bool = false

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
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
        .sheet(isPresented: $showEmailAuthSheet) {
            EmailAuthSheet(viewModel: viewModel, isPresented: $showEmailAuthSheet)
        }
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

// MARK: - Email Authentication Sheet

public struct EmailAuthSheet: View {
    @ObservedObject var viewModel: AuthViewModel
    @Binding var isPresented: Bool

    public init(viewModel: AuthViewModel, isPresented: Binding<Bool>) {
        self.viewModel = viewModel
        self._isPresented = isPresented
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.lumaCanvas
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Text(viewModel.mode == .signIn ? "Sign in to Luma AI" : "Create your account")
                                .font(LumaTypography.title)
                                .foregroundColor(.lumaPrimaryText)

                            Text(viewModel.mode == .signIn ? "Continue your thoughtful conversations" : "Your private space to think, create, and explore")
                                .font(LumaTypography.subheadline)
                                .foregroundColor(.lumaSecondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        VStack(spacing: 16) {
                            if viewModel.mode == .register {
                                LumaTextField(
                                    "Full Name",
                                    placeholder: "e.g. Jane Doe",
                                    text: $viewModel.fullName,
                                    textContentType: .name
                                )
                            }

                            LumaTextField(
                                "Email Address",
                                placeholder: "you@example.com",
                                text: $viewModel.email,
                                keyboardType: .emailAddress,
                                textContentType: .emailAddress
                            )

                            LumaTextField(
                                "Password",
                                placeholder: "••••••••",
                                text: $viewModel.password,
                                isSecure: true,
                                textContentType: viewModel.mode == .signIn ? .password : .newPassword
                            )

                            if let error = viewModel.errorMessage {
                                Text(error)
                                    .font(LumaTypography.captionMedium)
                                    .foregroundColor(.lumaError)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            LumaButton(
                                viewModel.mode == .signIn ? "Sign In" : "Create Account",
                                style: .primary,
                                isLoading: viewModel.isLoading
                            ) {
                                Task {
                                    await viewModel.submit()
                                    if viewModel.errorMessage == nil {
                                        isPresented = false
                                    }
                                }
                            }
                            .disabled(!viewModel.isFormValid || viewModel.isLoading)
                            .opacity(viewModel.isFormValid && !viewModel.isLoading ? 1.0 : 0.5)
                        }
                        .padding(24)
                        .background(Color.lumaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.lumaBorder, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)

                        Button(action: {
                            HapticFeedback.selection()
                            viewModel.toggleMode()
                        }) {
                            HStack(spacing: 4) {
                                Text(viewModel.mode == .signIn ? "Don't have an account?" : "Already have an account?")
                                    .foregroundColor(.lumaSecondaryText)
                                Text(viewModel.mode == .signIn ? "Sign up" : "Sign in")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.lumaPrimaryText)
                            }
                            .font(LumaTypography.subheadline)
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.lumaPrimaryText)
                }
            }
        }
    }
}
