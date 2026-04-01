import SwiftUI

/// A shimmer/skeleton loading placeholder
struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .overlay(
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, Color.gray.opacity(0.25), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: phase * geo.size.width)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

/// Skeleton placeholder for a channel card
struct ChannelCardSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ShimmerView()
                    .frame(width: 80, height: 50)
                Spacer()
                ShimmerView()
                    .frame(width: 30, height: 16)
            }
            ShimmerView()
                .frame(height: 20)
            ShimmerView()
                .frame(height: 16)
            ShimmerView()
                .frame(height: 4)
        }
        .padding()
        .frame(width: 280, height: 180)
        .background(Color(.systemGray).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
