import SwiftUI

public struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    public init(viewModel: AuthViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            Color.lumaCanvas
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    // Brand Logo & Header
                    VStack(spacing: 12) {
                        Circle()
                            .fill(Color.lumaSurfaceElevated)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Image(systemName: "sparkle")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundColor(.lumaPrimaryText)
                            )
                            .padding(.top, 40)

                        Text(viewModel.mode == .signIn ? "Sign in to Luma AI" : "Create your account")
                            .font(LumaTypography.title)
                            .foregroundColor(.lumaPrimaryText)

                        Text(viewModel.mode == .signIn ? "Continue your thoughtful conversations" : "Your private space to think, create, and explore")
                            .font(LumaTypography.subheadline)
                            .foregroundColor(.lumaSecondaryText)
                            .multilineTextAlignment(.center)
                    }

                    // Form Container Card
                    VStack(spacing: 20) {
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

                        VStack(alignment: .leading, spacing: 4) {
                            LumaTextField(
                                "Password",
                                placeholder: "At least 12 characters",
                                text: $viewModel.password,
                                isSecure: true,
                                textContentType: viewModel.mode == .signIn ? .password : .newPassword
                            )

                            if viewModel.mode == .register {
                                Text("Password must be at least 12 characters.")
                                    .font(LumaTypography.caption)
                                    .foregroundColor(viewModel.password.count >= 12 ? .lumaSuccess : .lumaTertiaryText)
                                    .padding(.horizontal, 4)
                                    .padding(.top, 2)
                            }
                        }

                        if let error = viewModel.errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.lumaError)
                                Text(error)
                                    .font(LumaTypography.caption)
                                    .foregroundColor(.lumaError)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.lumaError.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }

                        LumaButton(
                            viewModel.mode == .signIn ? "Sign In" : "Create Account",
                            style: .primary,
                            isLoading: viewModel.isLoading
                        ) {
                            Task {
                                await viewModel.submit()
                            }
                        }
                        .disabled(!viewModel.isFormValid || viewModel.isLoading || viewModel.isGoogleLoading)
                        .opacity(viewModel.isFormValid && !viewModel.isGoogleLoading ? 1.0 : 0.5)

                        // Divider
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.lumaBorder)
                                .frame(height: 1)
                            Text("or")
                                .font(LumaTypography.caption)
                                .foregroundColor(.lumaTertiaryText)
                            Rectangle()
                                .fill(Color.lumaBorder)
                                .frame(height: 1)
                        }
                        .padding(.vertical, 2)

                        // Continue with Google Button
                        Button(action: {
                            HapticFeedback.light()
                            Task {
                                await viewModel.signInWithGoogle()
                            }
                        }) {
                            HStack(spacing: 10) {
                                if viewModel.isGoogleLoading {
                                    ProgressView()
                                        .tint(.lumaPrimaryText)
                                } else {
                                    GoogleIconView()
                                    Text("Continue with Google")
                                        .font(LumaTypography.bodyMedium)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.lumaSurfaceElevated)
                            .foregroundColor(.lumaPrimaryText)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.lumaBorder, lineWidth: 1)
                            )
                        }
                        .disabled(viewModel.isLoading || viewModel.isGoogleLoading)
                        .buttonStyle(.plain)
                    }
                    .padding(24)
                    .background(Color.lumaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.lumaBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    // Switch Mode Toggle
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
    }
}

private struct GoogleIconView: View {
    var body: some View {
        if UIImage(named: "google_logo") != nil {
            Image("google_logo")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            GoogleLogoCanvas()
                .frame(width: 18, height: 18)
        }
    }
}

private struct GoogleLogoCanvas: View {
    var body: some View {
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
