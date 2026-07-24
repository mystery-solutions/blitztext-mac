import Foundation

enum TranscriptionQualityService {
    static let minimumRecordingDuration: TimeInterval = 0.3

    static func shouldRejectRecording(duration: TimeInterval) -> Bool {
        duration < minimumRecordingDuration
    }

    static func cleanedTranscript(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizeNonSpeechArtifacts(trimmed)
    }

    static func isLikelyArtifact(_ text: String, recordingDuration: TimeInterval) -> Bool {
        let cleaned = cleanedTranscript(text)
        guard !cleaned.isEmpty else { return true }

        let words = cleaned.split { $0.isWhitespace || $0.isNewline }
        let letters = cleaned.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count

        if letters == 0 {
            return true
        }

        if recordingDuration < 0.55 && (words.count >= 5 || cleaned.count >= 32) {
            return true
        }

        if recordingDuration < 0.8 && cleaned.count >= 56 {
            return true
        }

        return false
    }

    // MARK: - Non-Speech-Filter
    //
    // Whisper wurde stark auf Untertitel-Daten trainiert und setzt deshalb
    // Non-Speech-Marker ("[Musik]", "(anhaltender Applaus)", "♪") und
    // halluzinierte Sender-Credits ("Untertitel der Amara.org-Community",
    // "Copyright SWR") in den Text, vor allem bei Stille und Atempausen.
    // Die OpenAI-API bietet dafuer keinen Schalter, deshalb filtern wir
    // deterministisch nach. Gilt fuer Cloud- und lokales Whisper gleichzeitig.

    /// Stichworte, die Whisper typischerweise als Non-Speech-Marker in
    /// runde Klammern oder *Sterne* setzt. Bei Bedarf hier ergaenzen.
    private static let nonSpeechKeywords: [String] = [
        "musik", "music", "applaus", "applause", "beifall", "klatschen",
        "lachen", "gelächter", "laughter", "räuspern", "husten", "niesen",
        "seufzen", "stöhnen", "stille", "schweigen", "silence", "pause",
        "geräusch", "geräusche", "rauschen", "piepen", "piept", "klingeln",
        "summen", "singt", "singing", "jingle", "intro", "outro",
        "vorspann", "abspann", "wind", "regen", "donner", "motor", "schritte"
    ]

    /// Ganze Segmente, die Whisper aus Untertitel-Trainingsdaten halluziniert
    /// (Sender-Credits, Copyright-Zeilen). Case-insensitive. Hier ergaenzen,
    /// falls neue Varianten auftauchen, die durchrutschen.
    private static let hallucinationPhrasePatterns: [String] = [
        #"untertitel(ung)?(\s+(der|von|im\s+auftrag|des))?[^\n]*"#,
        #"untertitel\s+im\s+auftrag[^\n]*"#,
        #"amara\.org[^\n]*"#,
        #"(copyright|©)[^\n]{0,40}\b(swr|wdr|zdf|ard|br|ndr|mdr|rbb|hr|arte|3sat|orf|srf|dw)\b[^\n]*"#
    ]

    /// Entfernt Non-Speech-Marker und bekannte Whisper-Halluzinationen.
    static func sanitizeNonSpeechArtifacts(_ text: String) -> String {
        var result = text

        // 1) Eckige Klammern und Notenzeichen immer entfernen. Beides wird bei
        //    echtem Diktat praktisch nie erzeugt und ist fast immer Non-Speech.
        result = strip(#"\[[^\]]*\]"#, in: result)
        result = strip(#"♪|♫|♬|🎵|🎶"#, in: result)

        // 2) Runde Klammern und *...* nur entfernen, wenn ein Non-Speech-
        //    Stichwort drinsteht (legitime Klammern bleiben so erhalten).
        let kw = nonSpeechKeywords.joined(separator: "|")
        result = strip("\\([^)]*\\b(?:\(kw))\\b[^)]*\\)", in: result)
        result = strip("\\*[^*]*\\b(?:\(kw))\\b[^*]*\\*", in: result)

        // 3) Bekannte Untertitel-/Copyright-Halluzinationen entfernen.
        for pattern in hallucinationPhrasePatterns {
            result = strip(pattern, in: result)
        }

        // 4) Aufraeumen: Leerzeichen vor Satzzeichen, Mehrfach-Leerzeichen,
        //    verwaiste Zeilenumbrueche und Rand.
        result = strip(#"\s+([.,!?;:])"#, in: result, replacement: "$1")
        result = strip(#"[ \t]{2,}"#, in: result, replacement: " ")
        result = strip(#"\n{3,}"#, in: result, replacement: "\n\n")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strip(_ pattern: String, in text: String, replacement: String = "") -> String {
        text.replacingOccurrences(
            of: pattern,
            with: replacement,
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
