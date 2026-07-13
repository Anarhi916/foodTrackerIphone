import Foundation
import UIKit
import CoreImage.CIFilterBuiltins

/// Cross-platform food sharing via deep links.
///
/// Two URL formats are supported:
/// 1. Custom scheme (direct):  nutritrack://food?v=1&d=<base64url(json)>
/// 2. HTTPS (clickable everywhere): https://anarhi916.github.io/nutritrack/?v=1&d=<base64url(json)>
///
/// We SEND the HTTPS form so it clicks in messengers (Viber/Telegram/WhatsApp),
/// but ACCEPT both forms for backwards compatibility.
///
/// JSON keys are short and platform-neutral — compatible with the Android app.
struct SharedFood {
    let nameRu: String
    let nameEn: String
    let nutrients: NutrientData
}

enum FoodShare {

    private static let webHost = "anarhi916.github.io"
    private static let webPath = "/nutritrack/"
    private static let webBase = "https://\(webHost)\(webPath)"

    static func buildShareLink(nameRu: String, nameEn: String, nutrients: NutrientData) -> String? {
        let payload: [String: Any] = [
            "v": 1,
            "name": nameRu,
            "name_en": nameEn,
            "cal": nutrients.calories,
            "p": nutrients.protein,
            "f": nutrients.fat,
            "c": nutrients.carbs,
            "fiber": nutrients.fiber,
            "sat_f": nutrients.saturatedFat,
            "mono_f": nutrients.monounsaturatedFat,
            "poly_f": nutrients.polyunsaturatedFat,
            "chol": nutrients.cholesterol,
            "va": nutrients.vitaminA,
            "vb1": nutrients.vitaminB1,
            "vb2": nutrients.vitaminB2,
            "vb3": nutrients.vitaminB3,
            "vb5": nutrients.vitaminB5,
            "vb6": nutrients.vitaminB6,
            "vb7": nutrients.vitaminB7,
            "vb9": nutrients.vitaminB9,
            "vb12": nutrients.vitaminB12,
            "vc": nutrients.vitaminC,
            "vd": nutrients.vitaminD,
            "ve": nutrients.vitaminE,
            "vk": nutrients.vitaminK,
            "ca": nutrients.calcium,
            "fe": nutrients.iron,
            "mg": nutrients.magnesium,
            "ph": nutrients.phosphorus,
            "k": nutrients.potassium,
            "na": nutrients.sodium,
            "zn": nutrients.zinc,
            "cu": nutrients.copper,
            "mn": nutrients.manganese,
            "se": nutrients.selenium,
            "iod": nutrients.iodine
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        // URL-safe base64 (no padding) — same as Android Base64.URL_SAFE | NO_WRAP | NO_PADDING
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(webBase)?v=1&d=\(encoded)"
    }

    static func parseShareLink(_ url: URL) -> SharedFood? {
        // Accept both the custom scheme (nutritrack://food) and the HTTPS redirect page.
        let isCustomScheme = url.scheme == "nutritrack" && url.host == "food"
        let isWebLink = (url.scheme == "https" || url.scheme == "http") &&
            url.host == webHost && url.path.hasPrefix("/nutritrack")
        guard isCustomScheme || isWebLink else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encoded = components.queryItems?.first(where: { $0.name == "d" })?.value else { return nil }

        // Normalise URL-safe base64 → standard base64 with padding
        var standard = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder > 0 { standard += String(repeating: "=", count: 4 - remainder) }

        guard let data = Data(base64Encoded: standard, options: .ignoreUnknownCharacters),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        guard let nameRu = map["name"] as? String else { return nil }
        let nameEn = (map["name_en"] as? String) ?? ""

        func d(_ key: String) -> Double { (map[key] as? NSNumber)?.doubleValue ?? 0 }

        let nutrients = NutrientData(
            calories: d("cal"), protein: d("p"), fat: d("f"),
            saturatedFat: d("sat_f"), monounsaturatedFat: d("mono_f"),
            polyunsaturatedFat: d("poly_f"), cholesterol: d("chol"),
            carbs: d("c"), fiber: d("fiber"),
            vitaminA: d("va"), vitaminB1: d("vb1"), vitaminB2: d("vb2"),
            vitaminB3: d("vb3"), vitaminB5: d("vb5"), vitaminB6: d("vb6"),
            vitaminB7: d("vb7"), vitaminB9: d("vb9"), vitaminB12: d("vb12"),
            vitaminC: d("vc"), vitaminD: d("vd"), vitaminE: d("ve"), vitaminK: d("vk"),
            calcium: d("ca"), iron: d("fe"), magnesium: d("mg"), phosphorus: d("ph"),
            potassium: d("k"), sodium: d("na"), zinc: d("zn"), copper: d("cu"),
            manganese: d("mn"), selenium: d("se"), iodine: d("iod")
        )
        return SharedFood(nameRu: nameRu, nameEn: nameEn, nutrients: nutrients)
    }

    static func share(link: String, foodName: String, from viewController: UIViewController? = nil) {
        let text = String(format: String(localized: "Делюсь блюдом «%@» в NutriTrack:\n%@"), foodName, link)
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        let vc = viewController ?? UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        vc?.present(activity, animated: true)
    }

    /// Generate a QR code image from a share link. Uses CoreImage — no third-party deps.
    static func generateQrImage(from text: String) -> UIImage? {
        guard let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("L", forKey: "inputCorrectionLevel")
        guard let ciImage = filter.outputImage else { return nil }
        // Scale up so the QR is crisp on high-DPI screens
        let scale: CGFloat = 10
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
