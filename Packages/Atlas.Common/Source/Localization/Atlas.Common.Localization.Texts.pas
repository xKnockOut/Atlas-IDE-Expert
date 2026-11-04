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
  begin
    Result := En;
  end
  else
  begin
    Result := De;
  end;
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
  begin
    mEnd := Pos('_', mPrimary);
  end;
  if mEnd > 0 then
  begin
    mPrimary := Copy(mPrimary, 1, mEnd - 1);
  end;
  Result := True;
  ALanguage := TTextLanguage.English;
  if mPrimary = 'de' then
  begin
    ALanguage := TTextLanguage.German;
  end
  else if mPrimary <> 'en' then
  begin
    Result := False;
  end;
end;

class function TAtlasLocale.Code(ALanguage: TTextLanguage): string;
begin
  if ALanguage = TTextLanguage.German then
  begin
    Result := 'de';
  end
  else
  begin
    Result := 'en';
  end;
end;

class function TAtlasLocale.Resolve(const ASetting, AClient: string): TTextLanguage;
begin
  if TryParse(ASetting, Result) then
  begin
    Exit;
  end;
  if TryParse(AClient, Result) then
  begin
    Exit;
  end;
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
  begin
    mTable.Texts[mIndex] := ATexts[mIndex];
  end;
  FTables := FTables + [mTable];
end;

class function TAtlasTextTables.Tables: TArray<TAtlasTextTable>;
begin
  Result := FTables;
end;

// Erste Stelle ab AIndex, deren Zeichen nicht in AChars liegt.
function SkipChars(const AText: string; AIndex: Integer; const AChars: TSysCharSet): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and CharInSet(AText[Result], AChars) do
  begin
    Inc(Result);
  end;
end;

// Liest den Platzhalter, der an AIndex (hinter dem %) beginnt, als "n:typ" nach AItem und setzt AIndex hinter den
// Typbuchstaben. Ein Index "n:" setzt das Argument, sonst zählt Format weiter. False am Textende.
function ReadPlaceholder(const AFormat: string; var AIndex, AArgument: Integer; out AItem: string): Boolean;
var
  mStart: Integer;
begin
  AItem := '';
  mStart := AIndex;
  AIndex := SkipChars(AFormat, AIndex, ['0'..'9']);
  if (AIndex <= Length(AFormat)) and (AIndex > mStart) and (AFormat[AIndex] = ':') then
  begin
    AArgument := StrToInt(Copy(AFormat, mStart, AIndex - mStart));
    Inc(AIndex);
  end
  else
  begin
    AIndex := mStart;
  end;
  // Breite und Genauigkeit überspringen.
  AIndex := SkipChars(AFormat, AIndex, ['-', '.', '0'..'9']);
  Result := AIndex <= Length(AFormat);
  if Result then
  begin
    AItem := Format('%d:%s', [AArgument, LowerCase(AFormat[AIndex])]);
    Inc(AArgument);
    Inc(AIndex);
  end;
end;

class function TAtlasTextTables.Placeholders(const AFormat: string): string;
var
  mFound: TList<string>;
  mIndex, mArgument: Integer;
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
      if not ReadPlaceholder(AFormat, mIndex, mArgument, mItem) then
      begin
        Break;
      end;
      if not mFound.Contains(mItem) then
      begin
        mFound.Add(mItem);
      end;
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
    begin
      // Für Entwickler im Test, nicht für Benutzer.
      Result := Result + [Format('%s, Eintrag %d: Text fehlt (De "%s", En "%s")', // german-ok
        [ATable.Name, mIndex, mText.De, mText.En])];
    end
    else if Placeholders(mText.De) <> Placeholders(mText.En) then
    begin
      Result := Result + [Format('%s, Eintrag %d: Platzhalter "%s" gegen "%s" (%s)', // german-ok
        [ATable.Name, mIndex, Placeholders(mText.De), Placeholders(mText.En), mText.De])];
    end;
  end;
end;

end.
