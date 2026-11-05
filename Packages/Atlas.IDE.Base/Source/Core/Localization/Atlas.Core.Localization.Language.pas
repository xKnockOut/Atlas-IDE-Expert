unit Atlas.Core.Localization.Language;

// Sprache der Plugin-Texte (#446, #1458) für alle Schichten. Die IDE-Schicht
// setzt sie beim Laden nach der Sprache der IDE (TAtlasStrings.Language ist
// nur ein anderer Zugang dazu). Core darf Atlas.UI.Strings nicht verwenden
// (Architektur, #406); seine Units halten ihre Benutzertexte deshalb neben dem
// Code in eigenen Tabellen
//   cTexts: array[TAtlasLanguage, TXyzText] of string = ((…deutsch…), (…englisch…));
// und lesen sie mit cTexts[TAtlasTextLanguage.Current, Id]. Jede Tabelle meldet
// sich im initialization-Teil an (TAtlasTextLanguage.AddTable); der Test prüft
// alle: kein leerer Text, gleiche Platzhalter in beiden Sprachen.
// Bezeichner, Signaturen, XMLDoc-Inhalte und Protokollzeilen werden nie übersetzt.

interface

{$SCOPEDENUMS ON}

type
  TAtlasLanguage = (German, English);

  /// <summary>Eine angemeldete Texttabelle: beide Sprachen in derselben Reihenfolge.</summary>
  TAtlasTextTableEntry = record
    /// <summary>Name der Unit, die die Tabelle hält.</summary>
    Name: string;
    German: TArray<string>;
    English: TArray<string>;
  end;

  /// <summary>Aktuelle Sprache der Plugin-Texte und Verzeichnis der Texttabellen. Gesetzt wird nur im
  /// Hauptthread beim Laden, gelesen von überall.</summary>
  TAtlasTextLanguage = class
  private class var
    FCurrent: TAtlasLanguage;
    FTables: TArray<TAtlasTextTableEntry>;
  public
    class property Current: TAtlasLanguage read FCurrent write FCurrent;
    /// <summary>True bei englischer Oberfläche.</summary>
    class function IsEnglish: Boolean; static;
    /// <summary>Meldet eine Tabelle an (nur im initialization-Teil).</summary>
    class procedure AddTable(const AName: string; const AGerman, AEnglish: array of string); static;
    class function Tables: TArray<TAtlasTextTableEntry>; static;
  end;

implementation

function Copied(const ATexts: array of string): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ATexts));
  for mIndex := 0 to High(ATexts) do
  begin
    Result[mIndex] := ATexts[mIndex];
  end;
end;

{ TAtlasTextLanguage }

class function TAtlasTextLanguage.IsEnglish: Boolean;
begin
  Result := FCurrent = TAtlasLanguage.English;
end;

class procedure TAtlasTextLanguage.AddTable(const AName: string; const AGerman, AEnglish: array of string);
var
  mTable: TAtlasTextTableEntry;
begin
  mTable.Name := AName;
  mTable.German := Copied(AGerman);
  mTable.English := Copied(AEnglish);
  FTables := FTables + [mTable];
end;

class function TAtlasTextLanguage.Tables: TArray<TAtlasTextTableEntry>;
begin
  Result := FTables;
end;

initialization
  // Wie Atlas.UI.Strings: Deutsch, bis die IDE-Schicht die Sprache der IDE setzt (Tests sehen die bisherigen
  // Texte).
  TAtlasTextLanguage.Current := TAtlasLanguage.German;

end.
