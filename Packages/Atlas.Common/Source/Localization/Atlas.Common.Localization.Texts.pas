unit Atlas.Common.Localization.Texts;

// Sprache der Texte, die der Server erzeugt (#1458): Befunde, Code-Aktionen,
// Hover, Vorschauen und Meldungen an den Benutzer. Wie Atlas.UI.Strings im
// Plugin (#446) eine Tabelle statt resourcestring, ohne Ressourcen-DLL.
//
// Jede umgestellte Unit hält ihre Texte in einer eigenen Tabelle neben dem
// Code, der sie benutzt (Kohäsion), als typisierte Konstante
//   cTexts: array[TXyzText] of TAtlasText = ((De: '…'; En: '…'), …);
// und meldet sie im initialization-Teil an (TAtlasTextTables.Add). Der Test
// Atlas.Common.Localization.Texts.Tests prüft alle angemeldeten Tabellen: Ein
// fehlender oder leerer Eintrag und abweichende Platzhalter (%s, %d, %0:s …)
// zwischen Deutsch und Englisch sind Übersetzungsfehler. Ein fehlender
// Tabelleneintrag scheitert schon beim Übersetzen (Größe des Arrays).
//
// Die Sprache wählt der Host einmal beim Start bzw. bei initialize
// (TAtlasLocale.Resolve: Einstellung language, sonst die Sprache des Clients,
// sonst Englisch) und bei geänderter Einstellung neu. Sie gilt für den ganzen
// Prozess: Ein Server bedient genau einen Client. Bis ein Host sie setzt,
// gilt Deutsch, damit Bibliotheksnutzer (Tests) die bisherigen Texte sehen.
// Bezeichner, Signaturen und XMLDoc-Inhalte werden nie übersetzt.

interface

{$SCOPEDENUMS ON}

type
  /// <summary>Sprache der Servertexte. Eigener Name, weil das Testprojekt auch TAtlasLanguage aus
  /// Atlas.UI.Strings sieht.</summary>
  TTextLanguage = (German, English);

  /// <summary>Ein Text in beiden Sprachen; Eintrag einer Texttabelle.</summary>
  TAtlasText = record
    De: string;
    En: string;
    /// <summary>Text in der aktuellen Sprache (TAtlasLocale.Language).</summary>
    function Text: string;
    /// <summary>Text in ALanguage.</summary>
    function TextIn(ALanguage: TTextLanguage): string;
    /// <summary>Text der aktuellen Sprache mit Platzhaltern wie Format.</summary>
    function Fmt(const AArgs: array of const): string;
  end;

  /// <summary>Aktuelle Sprache und ihre Kennungen ("de", "en", "de-DE" …).</summary>
  TAtlasLocale = record
  private class var
    FLanguage: TTextLanguage;
  public
    class function Language: TTextLanguage; static;
    /// <summary>Setzt die Sprache für alle folgenden Texte des Prozesses.</summary>
    class procedure Use(ALanguage: TTextLanguage); static;
    /// <summary>"de", "DE", "de-DE", "de_AT" → Deutsch; "en", "en-US" … → Englisch; sonst False.</summary>
    class function TryParse(const ACode: string; out ALanguage: TTextLanguage): Boolean; static;
    /// <summary>Kurzkennung "de" bzw. "en".</summary>
    class function Code(ALanguage: TTextLanguage): string; static;
    /// <summary>Einstellung language (ASetting, '' = nicht gesetzt), sonst die Sprache des Clients (AClient, z. B.
    /// initializationOptions.locale oder initialize.locale), sonst Englisch.</summary>
    class function Resolve(const ASetting, AClient: string): TTextLanguage; static;
  end;

  /// <summary>Eine angemeldete Texttabelle.</summary>
  TAtlasTextTable = record
    /// <summary>Name der Unit, die die Tabelle hält.</summary>
    Name: string;
    Texts: TArray<TAtlasText>;
  end;

  /// <summary>Verzeichnis aller Texttabellen für die Prüfung auf Übersetzungsfehler. Angemeldet wird nur im
  /// initialization-Teil (ein Thread), gelesen danach.</summary>
  TAtlasTextTables = record
  private class var
    FTables: TArray<TAtlasTextTable>;
  public
    class procedure Add(const AName: string; const ATexts: array of TAtlasText); static;
    class function Tables: TArray<TAtlasTextTable>; static;
    /// <summary>Platzhalter von Format in AFormat als vergleichbarer Text, z. B. "0:s 1:d" (nach Argument
    /// geordnet, doppelte einmal); '' ohne Platzhalter.</summary>
    class function Placeholders(const AFormat: string): string; static;
    /// <summary>Übersetzungsfehler in ATable: leere Einträge und abweichende Platzhalter, je einer als Text mit
    /// Tabelle und Position; leer ohne Fehler.</summary>
    class function Problems(const ATable: TAtlasTextTable): TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

{ TAtlasText }

function TAtlasText.Text: string;
begin
  Result := TextIn(TAtlasLocale.Language);
end;

function TAtlasText.TextIn(ALanguage: TTextLanguage): string;
begin
  if ALanguage = TTextLanguage.English then
    Result := En
  else
    Result := De;
end;

function TAtlasText.Fmt(const AArgs: array of const): string;
begin
  Result := Format(Text, AArgs);
end;

{ TAtlasLocale }

class function TAtlasLocale.Language: TTextLanguage;
begin
  Result := FLanguage;
end;

class procedure TAtlasLocale.Use(ALanguage: TTextLanguage);
begin
  FLanguage := ALanguage;
end;

class function TAtlasLocale.TryParse(const ACode: string; out ALanguage: TTextLanguage): Boolean;
var
  mPrimary: string;
  mEnd: Integer;
begin
  mPrimary := LowerCase(Trim(ACode));
  mEnd := Pos('-', mPrimary);
  if mEnd = 0 then
    mEnd := Pos('_', mPrimary);
  if mEnd > 0 then
    mPrimary := Copy(mPrimary, 1, mEnd - 1);
  Result := True;
  ALanguage := TTextLanguage.English;
  if mPrimary = 'de' then
    ALanguage := TTextLanguage.German
  else if mPrimary <> 'en' then
    Result := False;
end;

class function TAtlasLocale.Code(ALanguage: TTextLanguage): string;
begin
  if ALanguage = TTextLanguage.German then
    Result := 'de'
  else
    Result := 'en';
end;

class function TAtlasLocale.Resolve(const ASetting, AClient: string): TTextLanguage;
begin
  if TryParse(ASetting, Result) then
    Exit;
  if TryParse(AClient, Result) then
    Exit;
  Result := TTextLanguage.English;
end;

{ TAtlasTextTables }

class procedure TAtlasTextTables.Add(const AName: string; const ATexts: array of TAtlasText);
var
  mTable: TAtlasTextTable;
  mIndex: Integer;
begin
  mTable.Name := AName;
  SetLength(mTable.Texts, Length(ATexts));
  for mIndex := 0 to High(ATexts) do
    mTable.Texts[mIndex] := ATexts[mIndex];
  FTables := FTables + [mTable];
end;

class function TAtlasTextTables.Tables: TArray<TAtlasTextTable>;
begin
  Result := FTables;
end;

class function TAtlasTextTables.Placeholders(const AFormat: string): string;
var
  mFound: TList<string>;
  mIndex, mArgument, mStart: Integer;
  mItem: string;
begin
  mFound := TList<string>.Create;
  try
    mIndex := 1;
    mArgument := 0;
    while mIndex <= Length(AFormat) do
    begin
      if AFormat[mIndex] <> '%' then
      begin
        Inc(mIndex);
        Continue;
      end;
      Inc(mIndex);
      if (mIndex <= Length(AFormat)) and (AFormat[mIndex] = '%') then
      begin
        Inc(mIndex);
        Continue;
      end;
      // Index "n:" setzt das Argument, sonst zählt Format weiter.
      mStart := mIndex;
      while (mIndex <= Length(AFormat)) and CharInSet(AFormat[mIndex], ['0'..'9']) do
        Inc(mIndex);
      if (mIndex <= Length(AFormat)) and (mIndex > mStart) and (AFormat[mIndex] = ':') then
      begin
        mArgument := StrToInt(Copy(AFormat, mStart, mIndex - mStart));
        Inc(mIndex);
      end
      else
        mIndex := mStart;
      // Breite und Genauigkeit überspringen.
      while (mIndex <= Length(AFormat)) and CharInSet(AFormat[mIndex], ['-', '.', '0'..'9']) do
        Inc(mIndex);
      if mIndex > Length(AFormat) then
        Break;
      mItem := Format('%d:%s', [mArgument, LowerCase(AFormat[mIndex])]);
      if not mFound.Contains(mItem) then
        mFound.Add(mItem);
      Inc(mArgument);
      Inc(mIndex);
    end;
    mFound.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareStr(A, B);
      end));
    Result := string.Join(' ', mFound.ToArray);
  finally
    mFound.Free;
  end;
end;

class function TAtlasTextTables.Problems(const ATable: TAtlasTextTable): TArray<string>;
var
  mIndex: Integer;
  mText: TAtlasText;
begin
  Result := nil;
  for mIndex := 0 to High(ATable.Texts) do
  begin
    mText := ATable.Texts[mIndex];
    if (Trim(mText.De) = '') or (Trim(mText.En) = '') then
      // Für Entwickler im Test, nicht für Benutzer.
      Result := Result + [Format('%s, Eintrag %d: Text fehlt (De "%s", En "%s")', // german-ok
        [ATable.Name, mIndex, mText.De, mText.En])]
    else if Placeholders(mText.De) <> Placeholders(mText.En) then
      Result := Result + [Format('%s, Eintrag %d: Platzhalter "%s" gegen "%s" (%s)', // german-ok
        [ATable.Name, mIndex, Placeholders(mText.De), Placeholders(mText.En), mText.De])];
  end;
end;

end.
