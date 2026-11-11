unit Atlas.IDE.Contracts.Help;

// Vertrag zwischen Base und Modulen (#1886, ADR 0017 Regel 6): „Hilfe zum Element“. Ein Modul, das Hilfe
// zeigen kann (Atlas.IDE.Help), stellt über seinen Scope eine IAtlasHelpProvider bereit. Base meldet nur die
// Kennung des Elements unter dem Fokus: die Regel eines Befunds, den Schlüssel einer Einstellung oder die Kennung
// eines Atlas-Fensters (Identifier des Dockfensters). Ohne laufenden Anbieter bleibt F1 bei der IDE. Nur Typen
// und Interfaces, kein Code.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Art des Elements: Regel eines Befunds, Einstellung (x-key) oder Atlas-Fenster.</summary>
  TAtlasHelpKind = (Rule, Setting, Window);
{$SCOPEDENUMS OFF}

  /// <summary>Element, zu dem Hilfe gewünscht ist. Id: Regel-ID, Schlüssel bzw. Kennung des Fensters.</summary>
  TAtlasHelpTopic = record
    Kind: TAtlasHelpKind;
    Id: string;
  end;

  /// <summary>Zeigt Hilfe zu einem Element. Aufrufe im Hauptthread der IDE.</summary>
  IAtlasHelpProvider = interface
    ['{07357BFF-2263-42DA-8CEE-EA0618F3AB4C}']
    /// <summary>Kennt der Anbieter eine Seite zu ATopic?</summary>
    function HasHelp(const ATopic: TAtlasHelpTopic): Boolean;
    /// <summary>Seite zu ATopic öffnen; False, wenn der Anbieter keine kennt.</summary>
    function ShowHelp(const ATopic: TAtlasHelpTopic): Boolean;
  end;

implementation

end.
