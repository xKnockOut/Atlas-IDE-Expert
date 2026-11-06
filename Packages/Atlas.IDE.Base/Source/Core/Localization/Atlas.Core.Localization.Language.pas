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
    /// <summary>Kennung der aktuellen Sprache für den Server (#1458): "de" oder "en" (initialize.locale,
    /// --locale).</summary>
    class function Code: string; static;
  end;

  /// <summary>Woher die Sprache der IDE stammt (#446, Protokollzeile beim Laden).</summary>
  TAtlasIdeLanguageSource = (Resources, Registry, Windows, Fallback);

  /// <summary>Erkannte Sprache der IDE samt Quelle und gelesenem Wert.</summary>
  TAtlasIdeLanguage = record
    Language: TAtlasLanguage;
    Source: TAtlasIdeLanguageSource;
    /// <summary>Gelesener Wert der Quelle (Endung der Ressourcen, Eintrag der Registry); sonst ''.</summary>
    Value: string;
    /// <summary>Sprache aus dem, was die IDE zeigt (#446): Endung der geladenen Ressourcen-DLLs der IDE
    /// (coreide370.de), sonst Eintrag für bds.exe unter Software\Embarcadero\Locales (BDSSetLang, Installer),
    /// sonst die Anzeigesprache von Windows (AWindowsGerman), sonst Englisch. Eine erkannte Sprache außer
    /// Deutsch gilt als Englisch und entscheidet ebenso; leere Angaben überspringt die Wahl.</summary>
    class function Decide(const AResourceCodes: TArray<string>; const ARegistered: string;
      AWindowsGerman: Boolean): TAtlasIdeLanguage; static;
    /// <summary>Kurzbeschreibung für atlas.log, etwa „de (Ressourcen: DE)“.</summary>
    function Describe: string;
  end;

implementation

uses
  System.SysUtils;

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

class function TAtlasTextLanguage.Code: string;
begin
  if FCurrent = TAtlasLanguage.English then
  begin
    Result := 'en';
  end
  else
  begin
    Result := 'de';
  end;
end;

/// <summary>Sprachteil einer Kennung in Großbuchstaben: „de-DE“ → „DE“, „DEU“ bleibt „DEU“.</summary>
function PrimaryCode(const ACode: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 1 to Length(ACode) do
  begin
    if not CharInSet(ACode[mIndex], ['A'..'Z', 'a'..'z']) then
    begin
      Break;
    end;
    Result := Result + UpCase(ACode[mIndex]);
  end;
end;

/// <summary>Sprache zu ACode; False bei leerer Kennung.</summary>
function TryLanguageOf(const ACode: string; out ALanguage: TAtlasLanguage): Boolean;
var
  mPrimary: string;
begin
  mPrimary := PrimaryCode(Trim(ACode));
  Result := mPrimary <> '';
  ALanguage := TAtlasLanguage.English;
  if (mPrimary = 'DE') or (mPrimary = 'DEU') then
  begin
    ALanguage := TAtlasLanguage.German;
  end;
end;

{ TAtlasIdeLanguage }

class function TAtlasIdeLanguage.Decide(const AResourceCodes: TArray<string>; const ARegistered: string;
  AWindowsGerman: Boolean): TAtlasIdeLanguage;
var
  mCode: string;
begin
  Result := Default(TAtlasIdeLanguage);
  for mCode in AResourceCodes do
  begin
    if TryLanguageOf(mCode, Result.Language) then
    begin
      Result.Source := TAtlasIdeLanguageSource.Resources;
      Result.Value := Trim(mCode);
      Exit;
    end;
  end;
  if TryLanguageOf(ARegistered, Result.Language) then
  begin
    Result.Source := TAtlasIdeLanguageSource.Registry;
    Result.Value := Trim(ARegistered);
    Exit;
  end;
  Result.Source := TAtlasIdeLanguageSource.Fallback;
  Result.Language := TAtlasLanguage.English;
  if AWindowsGerman then
  begin
    Result.Source := TAtlasIdeLanguageSource.Windows;
    Result.Language := TAtlasLanguage.German;
  end;
end;

function TAtlasIdeLanguage.Describe: string;
const
  cLanguages: array[TAtlasLanguage] of string = ('de', 'en');
  cSources: array[TAtlasIdeLanguageSource] of string = ('Ressourcen', 'Registry Locales', 'Windows',
    'Vorgabe');
begin
  Result := cLanguages[Language] + ' (' + cSources[Source];
  if Value <> '' then
  begin
    Result := Result + ': ' + Value;
  end;
  Result := Result + ')';
end;

initialization
  // Wie Atlas.UI.Strings: Deutsch, bis die IDE-Schicht die Sprache der IDE setzt (Tests sehen die bisherigen
  // Texte).
  TAtlasTextLanguage.Current := TAtlasLanguage.German;

end.
