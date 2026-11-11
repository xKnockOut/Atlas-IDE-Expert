unit Atlas.Core.Search.Results;

// Ergebnisse der Atlas-Suche für die Suchleiste und das Meldungsfenster
// (#878), ohne VCL und Open Tools API:
// - IndexAt: welcher Treffer gerade markiert ist bzw. den Cursor enthält (für
//   den Zähler „n von m“ der Leiste).
// - TypingTarget: Treffer, den die Suche beim Tippen markiert; ohne Treffer
//   keiner, auch wenn ein kürzerer Suchtext vorher etwas gefunden hatte.
// - Entries: je Treffer eine Zeile für den Reiter „Atlas-Suche“ im Fenster
//   Meldungen: 1-basierte Zeile, 1-basierte Editorspalte (Tabs aufgelöst) und
//   Zeilentext ohne Einzug; höchstens cMaxEntries.
// - RoutineName: kurzer Name einer Routine aus ihrer Kopfzeile für die
//   Kopfzeile der Liste („Methode TFoo.Bar“).
// - FollowSelection: F3 mit einzeiliger Markierung sucht nach dem markierten
//   Text, wenn er nicht der letzte Suchtext ist (etwa ein Bezeichner außerhalb
//   jeder Methode).
// - StartQuery: Suche beim Öffnen der Leiste. Vorgabe ist immer die Unit;
//   Methode nur über „In Methode suchen“ oder gezielt in der Bereichsliste,
//   eine mehrzeilige Markierung schlägt „Auswahl“ vor.

interface

uses
  System.SysUtils,
  Atlas.Core.Search.Matching;

type
  TAtlasSearchEntry = record
    /// <summary>Zeile, 1-basiert.</summary>
    Line: Integer;
    /// <summary>Editorspalte, 1-basiert, Tabs aufgelöst.</summary>
    Column: Integer;
    Text: string;
  end;

  TAtlasSearchResults = class
  public const
    cMaxEntries = 1000;
  public
    /// <summary>Index des Treffers, der an APos beginnt; sonst des ersten, der APos enthält (Start &lt; APos
    /// &lt;= Ende); -1 ohne.</summary>
    class function IndexAt(const AHits: TArray<TAtlasSearchHit>; const APos: TAtlasSearchPos): Integer; static;
    /// <summary>Treffer, den die Suche beim Tippen markiert: der erste (AFromFirstHit, search.fromFirstHit) oder
    /// der nächste ab AOrigin, der Stelle beim Öffnen der Leiste. -1 ohne Treffer: Dann bleibt nichts markiert und
    /// der Cursor geht zurück an AOrigin. Die Markierung eines kürzeren Suchtexts („acMem“ beim Tippen von
    /// „acmemmo“) ist kein Treffer des neuen.</summary>
    class function TypingTarget(const AHits: TArray<TAtlasSearchHit>; const AOrigin: TAtlasSearchPos;
      AFromFirstHit: Boolean): Integer; static;
    /// <summary>Zeilen für das Meldungsfenster, höchstens cMaxEntries.</summary>
    class function Entries(const ALines: TArray<string>; const AHits: TArray<TAtlasSearchHit>;
      ATabWidth: Integer): TArray<TAtlasSearchEntry>; static;
    /// <summary>„TFoo.Bar“ aus „class function TFoo.Bar(const A: Integer): Boolean;“; ohne Namen die Zeile.
    /// </summary>
    class function RoutineName(const ACaption: string): string; static;
    /// <summary>Suche für F3 mit einzeiliger Markierung ASelected: Ist ein anderer Text markiert als zuletzt
    /// gesucht, wird er der Suchtext (Bereich Auswahl wird Unit, Bezeichner-Modus nur für einen Bezeichner, Regex
    /// aus);
    /// sonst bleibt ALast. AChanged: Suchtext gewechselt.</summary>
    class function FollowSelection(const ALast: TAtlasSearchQuery; const ASelected: string;
      out AChanged: Boolean): TAtlasSearchQuery; static;
    /// <summary>Suche beim Öffnen der Leiste: Text AProposal, Optionen der letzten Suche ALast; Bereich Unit,
    /// bei mehrzeiliger Markierung Auswahl, mit AInMethod Methode (innerste Routine).</summary>
    class function StartQuery(const ALast: TAtlasSearchQuery; const AProposal: string;
      AMultiLineSelection, AInMethod: Boolean): TAtlasSearchQuery; static;
  end;

implementation

uses
  Atlas.Text.Chars,
  Atlas.Core.Editor.Pairs;

class function TAtlasSearchResults.IndexAt(const AHits: TArray<TAtlasSearchHit>;
  const APos: TAtlasSearchPos): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AHits) do
  begin
    if TAtlasSearchPos.Compare(AHits[mIndex].StartPos, APos) = 0 then
    begin
      Exit(mIndex);
    end;
  end;
  for mIndex := 0 to High(AHits) do
  begin
    if (TAtlasSearchPos.Compare(AHits[mIndex].StartPos, APos) < 0) and
      (TAtlasSearchPos.Compare(APos, AHits[mIndex].StopPos) <= 0) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class function TAtlasSearchResults.TypingTarget(const AHits: TArray<TAtlasSearchHit>; const AOrigin: TAtlasSearchPos;
  AFromFirstHit: Boolean): Integer;
var
  mWrapped: Boolean;
begin
  Result := -1;
  if Length(AHits) = 0 then
  begin
    Exit;
  end;
  Result := 0;
  if not AFromFirstHit then
  begin
    Result := TAtlasTextSearch.Next(AHits, AOrigin, False, mWrapped);
  end;
end;

class function TAtlasSearchResults.Entries(const ALines: TArray<string>; const AHits: TArray<TAtlasSearchHit>;
  ATabWidth: Integer): TArray<TAtlasSearchEntry>;
var
  mCount, mIndex: Integer;
  mLineText: string;
begin
  Result := nil;
  mCount := Length(AHits);
  if mCount > cMaxEntries then
  begin
    mCount := cMaxEntries;
  end;
  SetLength(Result, mCount);
  for mIndex := 0 to mCount - 1 do
  begin
    mLineText := '';
    if (AHits[mIndex].Line >= 0) and (AHits[mIndex].Line <= High(ALines)) then
    begin
      mLineText := ALines[AHits[mIndex].Line];
    end;
    Result[mIndex].Line := AHits[mIndex].Line + 1;
    Result[mIndex].Column := TAtlasPairs.ColumnOf(mLineText, AHits[mIndex].Character, ATabWidth);
    Result[mIndex].Text := TAtlasTextSearch.HitText(ALines, AHits[mIndex]);
  end;
end;

class function TAtlasSearchResults.RoutineName(const ACaption: string): string;
var
  mText: string;
  mStart, mStop: Integer;
begin
  mText := Trim(ACaption);
  // Schlüsselwörter vorn überspringen: class, procedure, function, constructor, destructor, operator.
  mStart := 1;
  repeat
    while (mStart <= Length(mText)) and (mText[mStart] = ' ') do
    begin
      Inc(mStart);
    end;
    mStop := mStart;
    while (mStop <= Length(mText)) and TTextChars.IsIdentChar(mText[mStop]) do
    begin
      Inc(mStop);
    end;
    if not TAtlasTextSearch.IsReserved(Copy(mText, mStart, mStop - mStart)) then
    begin
      Break;
    end;
    mStart := mStop;
  until mStart > Length(mText);
  // Name mit Punkten und Typparametern bis zur Parameterliste bzw. zum Ergebnistyp.
  mStop := mStart;
  while (mStop <= Length(mText)) and not CharInSet(mText[mStop], ['(', ':', ';', ' ']) do
  begin
    Inc(mStop);
  end;
  Result := Copy(mText, mStart, mStop - mStart);
  if Result = '' then
  begin
    Result := mText;
  end;
end;

class function TAtlasSearchResults.FollowSelection(const ALast: TAtlasSearchQuery; const ASelected: string;
  out AChanged: Boolean): TAtlasSearchQuery;
var
  mSame, mIdentifier: Boolean;
  mIndex: Integer;
begin
  Result := ALast;
  AChanged := False;
  if (ASelected = '') or (Pos(#10, ASelected) > 0) or (Pos(#13, ASelected) > 0) then
  begin
    Exit;
  end;
  // Steht die Markierung auf einem Treffer der letzten Suche, geht F3 einfach weiter.
  if ALast.Options.CaseSensitive and not ALast.Options.Identifier then
  begin
    mSame := ALast.Text = ASelected;
  end
  else
  begin
    mSame := SameText(ALast.Text, ASelected);
  end;
  if mSame then
  begin
    Exit;
  end;
  AChanged := True;
  Result.Text := ASelected;
  if Result.Scope = TAtlasSearchScope.Selection then
  begin
    Result.Scope := TAtlasSearchScope.UnitFile;
  end;
  Result.Area := TAtlasSearchArea.Create(0, 0, 0, 0);
  // Bezeichner-Modus findet nur Bezeichner; für „Foo.Bar“ oder „:=“ gilt die Textsuche.
  mIdentifier := TTextChars.IsIdentStart(ASelected[1]);
  for mIndex := 2 to Length(ASelected) do
  begin
    if not TTextChars.IsIdentChar(ASelected[mIndex]) then
    begin
      mIdentifier := False;
    end;
  end;
  if not mIdentifier then
  begin
    Result.Options.Identifier := False;
  end;
  // Die Markierung ist Text, kein Ausdruck (#893).
  Result.Options.Regex := False;
end;

class function TAtlasSearchResults.StartQuery(const ALast: TAtlasSearchQuery; const AProposal: string;
  AMultiLineSelection, AInMethod: Boolean): TAtlasSearchQuery;
begin
  // Nur Optionen übernehmen: Ein früher gewählter Bereich Methode gilt nicht für die nächste Suche.
  Result := Default(TAtlasSearchQuery);
  Result.Text := AProposal;
  Result.Options := ALast.Options;
  Result.Scope := TAtlasSearchScope.UnitFile;
  if AMultiLineSelection then
  begin
    Result.Scope := TAtlasSearchScope.Selection;
  end;
  if AInMethod then
  begin
    Result.Scope := TAtlasSearchScope.Method;
  end;
end;

end.
