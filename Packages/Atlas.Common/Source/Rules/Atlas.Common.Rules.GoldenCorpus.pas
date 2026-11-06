unit Atlas.Common.Rules.GoldenCorpus;

// Messung der Regelqualität (#152). Der Golden-Korpus sind Quelltexte mit
// Markierungen am Zeilenende:
//   // ERWARTET: regel-a, regel-b   diese Treffer müssen auf der Zeile kommen
//   // KEIN-TREFFER: regel-a        dieser Treffer darf hier nicht kommen
//   // ERWARTET-INDEX: regel-a      Treffer, der den Symbolindex braucht (#1112):
//                                    erwartet nur beim Lauf mit Index
// Compare gleicht die Markierungen mit den Treffern ab. Regel-IDs, die weder
// eine Regel noch geplant sind, gelten als Fehler; jede geplante ID nennt das
// offene Issue, das sie umsetzt (#94). Dazu Fehlalarmquoten aus
// den manuellen Bewertungen (bewertungen.csv) und die Laufzeit je Regel.
//
// Trefferquote über Mutationen (mutationen.txt): Jede Zeile
//   regel-id | Datei | Suchtext | Ersatz
// baut in eine fehlerfreie Datei des Korpus gezielt einen Fehler ein. Der
// Suchtext muss genau einmal vorkommen; \n, \uXXXX, \| und \\ sind
// Escapes. Die Regel muss danach mehr Treffer melden als vorher.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract;

const
  ExpectedMarker = 'ERWARTET:';
  NoFindingMarker = 'KEIN-TREFFER:';
  IndexMarker = 'ERWARTET-INDEX:';

type
  /// <summary>Eine Markierung: Regel und Zeile (0-basiert).</summary>
  TGoldenMarker = record
    Line: Integer;
    RuleId: string;
    /// <summary>True für ERWARTET, False für KEIN-TREFFER.</summary>
    Expected: Boolean;
  end;

  /// <summary>Ergebnis des Abgleichs einer Datei; jede Liste enthält lesbare Meldungen.</summary>
  TGoldenResult = record
    /// <summary>Erwartete Treffer, die fehlen.</summary>
    Missing: TArray<string>;
    /// <summary>Treffer auf einer KEIN-TREFFER-Zeile.</summary>
    FalseAlarms: TArray<string>;
    /// <summary>Markierungen mit unbekannter, nicht geplanter Regel-ID.</summary>
    Unknown: TArray<string>;
    /// <summary>Markierungen geplanter Regeln, die übersprungen wurden.</summary>
    Skipped: TArray<string>;
    /// <summary>Kein Fehlen, kein Fehlalarm, keine unbekannte ID.</summary>
    function Passed: Boolean;
  end;

  /// <summary>Fehlalarmquote einer Regel aus den Bewertungen.</summary>
  TRuleRate = record
    RuleId: string;
    Correct: Integer;
    Wrong: Integer;
    /// <summary>Anteil falscher Treffer zwischen 0 und 1; 0 ohne Bewertungen.</summary>
    function FalseAlarmRate: Double;
  end;

  /// <summary>Gesamtlaufzeit einer Regel über alle Dateien.</summary>
  TRuleTiming = record
    RuleId: string;
    Milliseconds: Double;
  end;

  /// <summary>Ein gezielt eingebauter Fehler: Suchtext in Datei durch Ersatz ersetzen.</summary>
  TRuleMutation = record
    RuleId: string;
    FileName: string;
    Search: string;
    Replacement: string;
    /// <summary>Zeile in der Mutationsliste, ab 1.</summary>
    Line: Integer;
  end;

  /// <summary>Trefferquote einer Regel über ihre Mutationen.</summary>
  TRuleHitRate = record
    RuleId: string;
    Mutations: Integer;
    Found: Integer;
    /// <summary>Anteil gefundener Mutationen zwischen 0 und 1; 0 ohne Mutationen.</summary>
    function HitRate: Double;
  end;

  TGoldenCorpus = class
  public
    /// <summary>Alle Markierungen in AText für den Lauf ohne Index.</summary>
    class function Markers(const AText: string): TArray<TGoldenMarker>; overload; static;
    /// <summary>Wie oben; mit AWithIndex zählt ERWARTET-INDEX wie ERWARTET (#1112).</summary>
    class function Markers(const AText: string; AWithIndex: Boolean): TArray<TGoldenMarker>; overload; static;
    /// <summary>Geplante Regel-IDs aus einer Liste "regel-id  # Bemerkung"; leere Zeilen und # werden übersprungen.</summary>
    class function PlannedIds(const AText: string): TArray<string>; static;
    /// <summary>Geplante Regel-IDs, deren Bemerkung kein Issue (#Nummer) nennt.</summary>
    class function PlannedWithoutIssue(const AText: string): TArray<string>; static;
    /// <summary>Gleicht die Markierungen von AFileName mit AFindings ab.</summary>
    class function Compare(const AFileName: string; const AMarkers: TArray<TGoldenMarker>;
      const AFindings: TArray<TRuleFinding>; const AKnownIds, APlannedIds: TArray<string>): TGoldenResult; static;
    /// <summary>Quoten je Regel aus einer CSV "Regel-ID,Datei,Zeile,Bewertung,Datum" mit Kopfzeile;
    /// Bewertung ist "richtig" oder "falsch". Nach Regel-ID sortiert.</summary>
    class function Rates(const ACsv: string): TArray<TRuleRate>; static;
    /// <summary>Mutationen aus einer Liste "regel-id | Datei | Suchtext | Ersatz"; leere Zeilen und # werden
    /// übersprungen. AErrors: Zeilen, die nicht vier Teile haben.</summary>
    class function Mutations(const AText: string; out AErrors: TArray<string>): TArray<TRuleMutation>; static;
    /// <summary>AText mit eingebautem Fehler; False, wenn der Suchtext nicht genau einmal vorkommt.
    /// \n im Ersatz wird zum Zeilenumbruch von AText.</summary>
    class function Mutate(const AText: string; const AMutation: TRuleMutation; out AMutated: string): Boolean; static;
    /// <summary>Meldet ARuleId nach der Mutation mehr Treffer als vorher?</summary>
    class function Detected(const ABefore, AAfter: TArray<TRuleFinding>; const ARuleId: string): Boolean; static;
    /// <summary>Trefferquote je Regel; AFound[i] gehört zu AMutations[i]. Nach Regel-ID sortiert.</summary>
    class function HitRates(const AMutations: TArray<TRuleMutation>;
      const AFound: TArray<Boolean>): TArray<TRuleHitRate>; static;
    /// <summary>Laufzeit jeder Regel allein über alle ATexts.</summary>
    class function TimeRules(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ATexts: TArray<string>): TArray<TRuleTiming>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Diagnostics,
  Atlas.Common.Rules.Checker,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TGoldenCorpusText = (Planned, UnknownRule, Missing, FalseAlarm, BadVerdict, BadLine);

const
  cTexts: array[TGoldenCorpusText] of TAtlasText = (
    (De: ' ist geplant und wird übersprungen'; En: ' is planned and skipped'),
    (De: ' ist keine bekannte Regel'; En: ' is not a known rule'),
    (De: ' erwartet, aber nicht gemeldet'; En: ' expected but not reported'),
    (De: ' gemeldet, obwohl KEIN-TREFFER'; En: ' reported although KEIN-TREFFER'),
    (De: 'Zeile %d: Bewertung "%s" ist weder richtig noch falsch';
     En: 'Line %d: verdict "%s" is neither right nor wrong'),
    (De: 'Zeile %d: erwartet "regel-id | Datei | Suchtext | Ersatz"';
     En: 'Line %d: expected "rule-id | file | search text | replacement"'));

{$SCOPEDENUMS OFF}

/// <summary>Regel-IDs bestehen aus Kleinbuchstaben, Ziffern und Bindestrichen.</summary>
function IsRuleId(const AId: string): Boolean;
var
  Index: Integer;
begin
  Result := AId <> '';
  for Index := 1 to Length(AId) do
  begin
    if not CharInSet(AId[Index], ['a'..'z', '0'..'9', '-']) then
    begin
      Exit(False);
    end;
  end;
end;

function Contains(const AValues: TArray<string>; const AValue: string): Boolean;
var
  Value: string;
begin
  for Value in AValues do
  begin
    if SameText(Value, AValue) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TGoldenResult }

function TGoldenResult.Passed: Boolean;
begin
  Result := (Length(Missing) = 0) and (Length(FalseAlarms) = 0) and (Length(Unknown) = 0);
end;

{ TRuleRate }

function TRuleRate.FalseAlarmRate: Double;
begin
  if Correct + Wrong = 0 then
  begin
    Result := 0;
  end
  else
  begin
    Result := Wrong / (Correct + Wrong);
  end;
end;

{ TRuleHitRate }

function TRuleHitRate.HitRate: Double;
begin
  if Mutations = 0 then
  begin
    Result := 0;
  end
  else
  begin
    Result := Found / Mutations;
  end;
end;

{ TGoldenCorpus }

class function TGoldenCorpus.Markers(const AText: string): TArray<TGoldenMarker>;
begin
  Result := Markers(AText, False);
end;

class function TGoldenCorpus.Markers(const AText: string; AWithIndex: Boolean): TArray<TGoldenMarker>;

  procedure ReadMarkers(const ALine: string; ALineIndex: Integer; const AMarker: string; AExpected: Boolean;
    var AMarkers: TArray<TGoldenMarker>);
  var
    Start: Integer;
    Id: string;
    Ids: TArray<string>;
    Marker: TGoldenMarker;
  begin
    Start := Pos('// ' + AMarker, ALine);
    if Start = 0 then
    begin
      Exit;
    end;
    Ids := Copy(ALine, Start + Length(AMarker) + 3, MaxInt).Split([',']);
    // Erklärende Kommentare wie "// ERWARTET: <regel>" sind keine Markierung.
    for Id in Ids do
    begin
      if not IsRuleId(Trim(Id)) then
      begin
        Exit;
      end;
    end;
    for Id in Ids do
    begin
      Marker.Line := ALineIndex;
      Marker.RuleId := Trim(Id);
      Marker.Expected := AExpected;
      AMarkers := AMarkers + [Marker];
    end;
  end;

var
  Lines: TArray<string>;
  Index: Integer;
begin
  Result := nil;
  Lines := TTextLines.SplitLines(AText);
  for Index := 0 to High(Lines) do
  begin
    ReadMarkers(Lines[Index], Index, ExpectedMarker, True, Result);
    ReadMarkers(Lines[Index], Index, NoFindingMarker, False, Result);
    if AWithIndex then
    begin
      ReadMarkers(Lines[Index], Index, IndexMarker, True, Result);
    end;
  end;
end;

class function TGoldenCorpus.PlannedIds(const AText: string): TArray<string>;
var
  Line, Id: string;
begin
  Result := nil;
  for Line in TTextLines.SplitLines(AText) do
  begin
    Id := Line;
    if Pos('#', Id) > 0 then
    begin
      Id := Copy(Id, 1, Pos('#', Id) - 1);
    end;
    Id := Trim(Id);
    if Id <> '' then
    begin
      Result := Result + [Id];
    end;
  end;
end;

class function TGoldenCorpus.PlannedWithoutIssue(const AText: string): TArray<string>;
var
  Line, Id, Note: string;
  Index: Integer;
  HasIssue: Boolean;
begin
  Result := nil;
  for Line in TTextLines.SplitLines(AText) do
  begin
    Id := Line;
    Note := '';
    if Pos('#', Id) > 0 then
    begin
      Note := Copy(Id, Pos('#', Id) + 1, MaxInt);
      Id := Copy(Id, 1, Pos('#', Id) - 1);
    end;
    Id := Trim(Id);
    if Id = '' then
    begin
      Continue;
    end;
    // Gesucht ist "#" mit mindestens einer Ziffer dahinter, z. B. "# #56".
    HasIssue := False;
    for Index := 1 to Length(Note) - 1 do
    begin
      if (Note[Index] = '#') and CharInSet(Note[Index + 1], ['0'..'9']) then
      begin
        HasIssue := True;
      end;
    end;
    if not HasIssue then
    begin
      Result := Result + [Id];
    end;
  end;
end;

/// <summary>Meldet AFindings die Regel ARuleId in ALine?</summary>
function Reported(const AFindings: TArray<TRuleFinding>; const ARuleId: string; ALine: Integer): Boolean;
var
  mFinding: TRuleFinding;
begin
  for mFinding in AFindings do
  begin
    if SameText(mFinding.RuleId, ARuleId) and (mFinding.Range.StartPos.Line = ALine) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TGoldenCorpus.Compare(const AFileName: string; const AMarkers: TArray<TGoldenMarker>;
  const AFindings: TArray<TRuleFinding>; const AKnownIds, APlannedIds: TArray<string>): TGoldenResult;
var
  mMarker: TGoldenMarker;
  mFound: Boolean;
  mPlace: string;
begin
  Result := Default(TGoldenResult);
  for mMarker in AMarkers do
  begin
    mPlace := Format('%s(%d): %s', [AFileName, mMarker.Line + 1, mMarker.RuleId]);
    if not Contains(AKnownIds, mMarker.RuleId) and Contains(APlannedIds, mMarker.RuleId) then
    begin
      Result.Skipped := Result.Skipped + [mPlace + cTexts[TGoldenCorpusText.Planned].Text];
      Continue;
    end;
    if not Contains(AKnownIds, mMarker.RuleId) then
    begin
      Result.Unknown := Result.Unknown + [mPlace + cTexts[TGoldenCorpusText.UnknownRule].Text];
      Continue;
    end;
    mFound := Reported(AFindings, mMarker.RuleId, mMarker.Line);
    if mMarker.Expected and not mFound then
    begin
      Result.Missing := Result.Missing + [mPlace + cTexts[TGoldenCorpusText.Missing].Text];
    end
    else if not mMarker.Expected and mFound then
    begin
      Result.FalseAlarms := Result.FalseAlarms + [mPlace + cTexts[TGoldenCorpusText.FalseAlarm].Text];
    end;
  end;
end;

/// <summary>Index der Quote von ARuleId in ARates; legt sie an, wenn es sie noch nicht gibt.</summary>
function RateIndex(var ARates: TArray<TRuleRate>; const ARuleId: string): Integer;
var
  mIndex: Integer;
  mRate: TRuleRate;
begin
  for mIndex := 0 to High(ARates) do
  begin
    if SameText(ARates[mIndex].RuleId, ARuleId) then
    begin
      Exit(mIndex);
    end;
  end;
  mRate := Default(TRuleRate);
  mRate.RuleId := ARuleId;
  ARates := ARates + [mRate];
  Result := High(ARates);
end;

/// <summary>Nach Regelkennung sortiert; wenige Regeln: einfaches Einfügesortieren (stabil).</summary>
procedure SortRates(var ARates: TArray<TRuleRate>);
var
  mIndex, mSwap: Integer;
  mTemp: TRuleRate;
begin
  for mIndex := 1 to High(ARates) do
  begin
    mTemp := ARates[mIndex];
    mSwap := mIndex - 1;
    while (mSwap >= 0) and (CompareText(ARates[mSwap].RuleId, mTemp.RuleId) > 0) do
    begin
      ARates[mSwap + 1] := ARates[mSwap];
      Dec(mSwap);
    end;
    ARates[mSwap + 1] := mTemp;
  end;
end;

class function TGoldenCorpus.Rates(const ACsv: string): TArray<TRuleRate>;
var
  mLines, mColumns: TArray<string>;
  mIndex, mRate: Integer;
  mVerdict: string;
begin
  Result := nil;
  mLines := TTextLines.SplitLines(ACsv);
  // Zeile 0 ist die Kopfzeile.
  for mIndex := 1 to High(mLines) do
  begin
    mColumns := mLines[mIndex].Split([',']);
    if Length(mColumns) < 4 then
    begin
      Continue;
    end;
    mRate := RateIndex(Result, Trim(mColumns[0]));
    mVerdict := LowerCase(Trim(mColumns[3]));
    if mVerdict = 'richtig' then
    begin
      Inc(Result[mRate].Correct);
    end
    else if mVerdict = 'falsch' then
    begin
      Inc(Result[mRate].Wrong);
    end
    else
    begin
      raise EArgumentException.CreateFmt(cTexts[TGoldenCorpusText.BadVerdict].Text,
        [mIndex + 1, mColumns[3]]);
    end;
  end;
  SortRates(Result);
end;

/// <summary>Teile einer Mutationszeile an " | ", \| bleibt im Teil.</summary>
function SplitParts(const ALine: string): TArray<string>;
var
  Index: Integer;
  Part: string;
begin
  Result := nil;
  Part := '';
  Index := 1;
  while Index <= Length(ALine) do
  begin
    if (ALine[Index] = '\') and (Index < Length(ALine)) then
    begin
      // Escapes bleiben für Unescape stehen.
      Part := Part + ALine[Index] + ALine[Index + 1];
      Inc(Index, 2);
      Continue;
    end;
    if ALine[Index] = '|' then
    begin
      Result := Result + [Trim(Part)];
      Part := '';
    end
    else
    begin
      Part := Part + ALine[Index];
    end;
    Inc(Index);
  end;
  Result := Result + [Trim(Part)];
end;

/// <summary>\n, \uXXXX, \| und \\ auflösen; ALineBreak für \n.</summary>
function Unescape(const AText, ALineBreak: string): string;
var
  Index, Code: Integer;
begin
  Result := '';
  Index := 1;
  while Index <= Length(AText) do
  begin
    if (AText[Index] = '\') and (Index < Length(AText)) then
    begin
      case AText[Index + 1] of
        'n':
          begin
            Result := Result + ALineBreak;
            Inc(Index, 2);
            Continue;
          end;
        'u':
          if TryStrToInt('$' + Copy(AText, Index + 2, 4), Code) then
          begin
            Result := Result + Char(Code);
            Inc(Index, 6);
            Continue;
          end;
        '|', '\':
          begin
            Result := Result + AText[Index + 1];
            Inc(Index, 2);
            Continue;
          end;
      end;
    end;
    Result := Result + AText[Index];
    Inc(Index);
  end;
end;

class function TGoldenCorpus.Mutations(const AText: string; out AErrors: TArray<string>): TArray<TRuleMutation>;
var
  Lines, Parts: TArray<string>;
  Index: Integer;
  Line: string;
  Mutation: TRuleMutation;
begin
  Result := nil;
  AErrors := nil;
  Lines := TTextLines.SplitLines(AText);
  for Index := 0 to High(Lines) do
  begin
    Line := Trim(Lines[Index]);
    if (Line = '') or StartsStr('#', Line) then
    begin
      Continue;
    end;
    Parts := SplitParts(Line);
    if (Length(Parts) <> 4) or (Parts[0] = '') or (Parts[1] = '') or (Parts[2] = '') then
    begin
      AErrors := AErrors + [cTexts[TGoldenCorpusText.BadLine].Fmt([Index + 1])];
      Continue;
    end;
    Mutation.RuleId := Parts[0];
    Mutation.FileName := Parts[1];
    Mutation.Search := Parts[2];
    Mutation.Replacement := Parts[3];
    Mutation.Line := Index + 1;
    Result := Result + [Mutation];
  end;
end;

class function TGoldenCorpus.Mutate(const AText: string; const AMutation: TRuleMutation;
  out AMutated: string): Boolean;
var
  LineBreak, Search: string;
  First: Integer;
begin
  AMutated := AText;
  LineBreak := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    LineBreak := #13#10;
  end;
  Search := Unescape(AMutation.Search, LineBreak);
  First := Pos(Search, AText);
  Result := (First > 0) and (Pos(Search, AText, First + 1) = 0);
  if Result then
  begin
    AMutated := Copy(AText, 1, First - 1) + Unescape(AMutation.Replacement, LineBreak) +
      Copy(AText, First + Length(Search), MaxInt);
  end;
end;

class function TGoldenCorpus.Detected(const ABefore, AAfter: TArray<TRuleFinding>; const ARuleId: string): Boolean;

  function CountOf(const AFindings: TArray<TRuleFinding>): Integer;
  var
    Finding: TRuleFinding;
  begin
    Result := 0;
    for Finding in AFindings do
    begin
      if SameText(Finding.RuleId, ARuleId) then
      begin
        Inc(Result);
      end;
    end;
  end;

begin
  Result := CountOf(AAfter) > CountOf(ABefore);
end;

class function TGoldenCorpus.HitRates(const AMutations: TArray<TRuleMutation>;
  const AFound: TArray<Boolean>): TArray<TRuleHitRate>;
var
  Index, Rate, Swap: Integer;
  Temp: TRuleHitRate;
begin
  Result := nil;
  for Index := 0 to High(AMutations) do
  begin
    Rate := -1;
    for Swap := 0 to High(Result) do
    begin
      if SameText(Result[Swap].RuleId, AMutations[Index].RuleId) then
      begin
        Rate := Swap;
      end;
    end;
    if Rate < 0 then
    begin
      Temp := Default(TRuleHitRate);
      Temp.RuleId := AMutations[Index].RuleId;
      Result := Result + [Temp];
      Rate := High(Result);
    end;
    Inc(Result[Rate].Mutations);
    if (Index <= High(AFound)) and AFound[Index] then
    begin
      Inc(Result[Rate].Found);
    end;
  end;
  for Index := 1 to High(Result) do
  begin
    Temp := Result[Index];
    Swap := Index - 1;
    while (Swap >= 0) and (CompareText(Result[Swap].RuleId, Temp.RuleId) > 0) do
    begin
      Result[Swap + 1] := Result[Swap];
      Dec(Swap);
    end;
    Result[Swap + 1] := Temp;
  end;
end;

class function TGoldenCorpus.TimeRules(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ATexts: TArray<string>): TArray<TRuleTiming>;
var
  Rule: IRule;
  Text: string;
  Watch: TStopwatch;
  Timing: TRuleTiming;
begin
  Result := nil;
  for Rule in ARules do
  begin
    Watch := TStopwatch.StartNew;
    for Text in ATexts do
    begin
      TFileChecker.CheckText([Rule], ASettings, '', Text);
    end;
    Timing.RuleId := Rule.Descriptor.Id;
    Timing.Milliseconds := Watch.Elapsed.TotalMilliseconds;
    Result := Result + [Timing];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.GoldenCorpus', cTexts);

end.
