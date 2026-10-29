unit Atlas.Debug.Attributes;

// Attribute für die eigene Wertdarstellung beim Debuggen mit Atlas (#854).
// Diese Unit ins eigene Projekt kopieren (oder ihren Ordner in den Suchpfad
// aufnehmen) und über den Typ schreiben:
//
//   uses Atlas.Debug.Attributes;
//
//   type
//     [AtlasDebugDisplay('{Name}, {Ort} (Nr {Nr})')]
//     [AtlasDebugChildren('Name, Ort, Saldo')]
//     TKunde = class
//       ...
//
// Atlas liest die Attribute aus dem Quelltext; zur Laufzeit tun sie nichts.
// Ohne Abhängigkeit im Code geht es auch mit einem Kommentar direkt über dem
// Typ: // atlas-debug: '{Name}, {Ort}' und // atlas-debug-children: Name, Ort.
// Nur System, übersetzt mit Delphi 12 und neuer.

interface

type
  /// <summary>Vorlage für die Darstellung im Debugger: {Feld}, {Eigenschaft}, {Liste.Count}, {Betrag:0.00}.
  /// </summary>
  AtlasDebugDisplayAttribute = class(TCustomAttribute)
  private
    FTemplate: string;
  public
    constructor Create(const ATemplate: string);
    property Template: string read FTemplate;
  end;

  /// <summary>Unterelemente beim Aufklappen im Atlas-Ansichtsfenster, kommagetrennt.</summary>
  AtlasDebugChildrenAttribute = class(TCustomAttribute)
  private
    FNames: string;
  public
    constructor Create(const ANames: string);
    property Names: string read FNames;
  end;

implementation

constructor AtlasDebugDisplayAttribute.Create(const ATemplate: string);
begin
  inherited Create;
  FTemplate := ATemplate;
end;

constructor AtlasDebugChildrenAttribute.Create(const ANames: string);
begin
  inherited Create;
  FNames := ANames;
end;

end.
