import SwiftUI
import AppKit
import DevbarCore

/// Scheda "Informazioni": icona, nome, versione, collegamenti e il pulsante "Offrimi una birra".
struct AboutSection: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            VStack(spacing: 16) {
                header
                HStack(spacing: 8) {
                    pill("GitHub", symbol: "chevron.left.forwardslash.chevron.right", url: AppInfo.repositoryURL)
                    pill("Segnala un problema", symbol: "exclamationmark.bubble", url: AppInfo.issuesURL)
                    pill("Licenza", symbol: "doc.text", url: AppInfo.licenseURL)
                }
                Button { openURL(AppInfo.supportURL) } label: { BeerLabel() }
                    .buttonStyle(BeerButtonStyle())
                    .help("Offrimi una birra su Buy Me a Coffee")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 68, height: 68)
            VStack(alignment: .leading, spacing: 4) {
                Text("devbar")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(AppInfo.tagline)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Versione \(AppInfo.versionText(Bundle.main.infoDictionary))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                    .foregroundStyle(Color.accentColor)
            }
            Spacer(minLength: 0)
        }
    }

    private func pill(_ title: String, symbol: String, url: URL) -> some View {
        Button { openURL(url) } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
    }
}

/// Il pulsante "Offrimi una birra": dorato come la schiuma, testo scuro, con la tazza in un cerchio.
struct BeerLabel: View {
    private static let gold = LinearGradient(
        colors: [Color(red: 1.0, green: 0.87, blue: 0.0), Color(red: 1.0, green: 0.70, blue: 0.12)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mug.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.black.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Offrimi una birra")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("devbar è gratuito: un grazie fa sempre piacere")
                    .font(.system(size: 11))
                    .opacity(0.72)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .bold))
                .opacity(0.6)
        }
        .foregroundStyle(Color.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Self.gold))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.10), lineWidth: 1))
        .shadow(color: Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.35), radius: 8, y: 3)
    }
}

/// Premuto: si schiaccia appena e si scurisce, così si sente il clic.
struct BeerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
