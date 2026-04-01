import SwiftUI

struct LoginView: View {
    @ObservedObject var authVM: AuthViewModel

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App logo
            Image("PineappleStackLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 24))

            Text("PineappleStack TV")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Connect to your PineappleStack server")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 20) {
                TextField("Server URL (e.g. 192.168.1.100)", text: $authVM.serverURL)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()

                Toggle("Remember Server", isOn: $authVM.rememberServer)
                    .padding(.horizontal)

                TextField("Username", text: $authVM.username)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .autocorrectionDisabled()

                SecureField("Password", text: $authVM.password)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(action: {
                    Task { await authVM.login() }
                }) {
                    if authVM.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Connect")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(authVM.isLoading)
                .padding()

                if let error = authVM.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .frame(maxWidth: 500)

            Spacer()
        }
        .padding(60)
    }
}
