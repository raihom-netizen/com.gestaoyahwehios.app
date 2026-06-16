/// Modelo partilhado — Termos de Uso e Política de Privacidade (Firestore + UI).
class LegalSectionEntry {
  final String title;
  final String body;

  const LegalSectionEntry({required this.title, required this.body});

  LegalSectionEntry copyWith({String? title, String? body}) {
    return LegalSectionEntry(
      title: title ?? this.title,
      body: body ?? this.body,
    );
  }

  Map<String, dynamic> toMap() => {'title': title, 'body': body};

  static LegalSectionEntry fromMap(Map<String, dynamic> map) {
    return LegalSectionEntry(
      title: (map['title'] ?? '').toString(),
      body: (map['body'] ?? '').toString(),
    );
  }
}

class LegalDocumentContent {
  final String title;
  final String intro;
  final List<LegalSectionEntry> sections;

  const LegalDocumentContent({
    required this.title,
    required this.intro,
    required this.sections,
  });

  LegalDocumentContent copyWith({
    String? title,
    String? intro,
    List<LegalSectionEntry>? sections,
  }) {
    return LegalDocumentContent(
      title: title ?? this.title,
      intro: intro ?? this.intro,
      sections: sections ?? this.sections,
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'intro': intro,
        'sections': sections.map((s) => s.toMap()).toList(),
      };

  static LegalDocumentContent fromMap(Map<String, dynamic> map) {
    final raw = map['sections'];
    final list = <LegalSectionEntry>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          list.add(LegalSectionEntry.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    }
    return LegalDocumentContent(
      title: (map['title'] ?? '').toString(),
      intro: (map['intro'] ?? '').toString(),
      sections: list,
    );
  }
}

class LegalDocumentsBundle {
  final String lastUpdatedLabel;
  final String supportEmail;
  final String supportWhatsAppDisplay;
  final LegalDocumentContent terms;
  final LegalDocumentContent privacy;
  final int revision;

  const LegalDocumentsBundle({
    required this.lastUpdatedLabel,
    required this.supportEmail,
    required this.supportWhatsAppDisplay,
    required this.terms,
    required this.privacy,
    this.revision = 0,
  });

  LegalDocumentsBundle copyWith({
    String? lastUpdatedLabel,
    String? supportEmail,
    String? supportWhatsAppDisplay,
    LegalDocumentContent? terms,
    LegalDocumentContent? privacy,
    int? revision,
  }) {
    return LegalDocumentsBundle(
      lastUpdatedLabel: lastUpdatedLabel ?? this.lastUpdatedLabel,
      supportEmail: supportEmail ?? this.supportEmail,
      supportWhatsAppDisplay:
          supportWhatsAppDisplay ?? this.supportWhatsAppDisplay,
      terms: terms ?? this.terms,
      privacy: privacy ?? this.privacy,
      revision: revision ?? this.revision,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'lastUpdatedLabel': lastUpdatedLabel.trim(),
        'supportEmail': supportEmail.trim(),
        'supportWhatsAppDisplay': supportWhatsAppDisplay.trim(),
        'terms': terms.toMap(),
        'privacy': privacy.toMap(),
      };

  static LegalDocumentsBundle fromFirestore(Map<String, dynamic> data) {
    final termsRaw = data['terms'];
    final privacyRaw = data['privacy'];
    final rev = data['revision'];
    return LegalDocumentsBundle(
      lastUpdatedLabel: (data['lastUpdatedLabel'] ?? '').toString(),
      supportEmail: (data['supportEmail'] ?? '').toString(),
      supportWhatsAppDisplay:
          (data['supportWhatsAppDisplay'] ?? '').toString(),
      terms: termsRaw is Map
          ? LegalDocumentContent.fromMap(Map<String, dynamic>.from(termsRaw))
          : const LegalDocumentContent(title: '', intro: '', sections: []),
      privacy: privacyRaw is Map
          ? LegalDocumentContent.fromMap(Map<String, dynamic>.from(privacyRaw))
          : const LegalDocumentContent(title: '', intro: '', sections: []),
      revision: rev is num ? rev.toInt() : 0,
    );
  }

  /// Valida conteúdo mínimo antes de publicar no Firestore.
  bool get isPublishable {
    if (lastUpdatedLabel.trim().isEmpty) return false;
    if (terms.intro.trim().isEmpty || terms.sections.isEmpty) return false;
    if (privacy.intro.trim().isEmpty || privacy.sections.isEmpty) return false;
    for (final s in [...terms.sections, ...privacy.sections]) {
      if (s.title.trim().isEmpty || s.body.trim().isEmpty) return false;
    }
    return true;
  }
}
