unit Argus.Common.Rules.GoldenCorpus;

// Messung der Regelqualität (#152). Der Golden-Korpus sind Quelltexte mit
// Markierungen am Zeilenende:
//   // ERWARTET: regel-a, regel-b   diese Treffer müssen auf der Zeile kommen
//   // KEIN-TREFFER: regel-a        dieser Treffer darf hier nicht kommen
// Compare gleicht die Markierungen mit den Treffern ab. Regel-IDs, die weder
// eine Regel noch geplant sind, gelten als Fehler. Dazu Fehlalarmquoten aus
// den manuellen Bewertungen (bewertungen.csv) und die Laufzeit je Regel.

interface

uses
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract;

const
  ExpectedMarker = 'ERWARTET:';
  NoFindingMarker = 'KEIN-TREFFER:';

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

  TGoldenCorpus = class
  public
    /// <summary>Alle Markierungen in AText.</summary>
    class function Markers(const AText: string): TArray<TGoldenMarker>; static;
    /// <summary>Geplante Regel-IDs aus einer Liste "regel-id  # Bemerkung"; leere Zeilen und # werden übersprungen.</summary>
    class function PlannedIds(const AText: string): TArray<string>; static;
    /// <summary>Gleicht die Markierungen von AFileName mit AFindings ab.</summary>
    class function Compare(const AFileName: string; const AMarkers: TArray<TGoldenMarker>;
      const AFindings: TArray<TRuleFinding>; const AKnownIds, APlannedIds: TArray<string>): TGoldenResult; static;
    /// <summary>Quoten je Regel aus einer CSV "Regel-ID,Datei,Zeile,Bewertung,Datum" mit Kopfzeile;
    /// Bewertung ist "richtig" oder "falsch". Nach Regel-ID sortiert.</summary>
    class function Rates(const ACsv: string): TArray<TRuleRate>; static;
    /// <summary>Laufzeit jeder Regel allein über alle ATexts.</summary>
    class function TimeRules(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ATexts: TArray<string>): TArray<TRuleTiming>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Diagnostics,
  Argus.Common.Rules.Checker;

function SplitLines(const AText: string): TArray<string>;
begin
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]).Split([#10]);
end;

/// <summary>Regel-IDs bestehen aus Kleinbuchstaben, Ziffern und Bindestrichen.</summary>
function IsRuleId(const AId: string): Boolean;
var
  Index: Integer;
begin
  Result := AId <> '';
  for Index := 1 to Length(AId) do
    if not CharInSet(AId[Index], ['a'..'z', '0'..'9', '-']) then
      Exit(False);
end;

function Contains(const AValues: TArray<string>; const AValue: string): Boolean;
var
  Value: string;
begin
  for Value in AValues do
    if SameText(Value, AValue) then
      Exit(True);
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
    Result := 0
  else
    Result := Wrong / (Correct + Wrong);
end;

{ TGoldenCorpus }

class function TGoldenCorpus.Markers(const AText: string): TArray<TGoldenMarker>;

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
      Exit;
    Ids := Copy(ALine, Start + Length(AMarker) + 3, MaxInt).Split([',']);
    // Erklärende Kommentare wie "// ERWARTET: <regel>" sind keine Markierung.
    for Id in Ids do
      if not IsRuleId(Trim(Id)) then
        Exit;
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
  Lines := SplitLines(AText);
  for Index := 0 to High(Lines) do
  begin
    ReadMarkers(Lines[Index], Index, ExpectedMarker, True, Result);
    ReadMarkers(Lines[Index], Index, NoFindingMarker, False, Result);
  end;
end;

class function TGoldenCorpus.PlannedIds(const AText: string): TArray<string>;
var
  Line, Id: string;
begin
  Result := nil;
  for Line in SplitLines(AText) do
  begin
    Id := Line;
    if Pos('#', Id) > 0 then
      Id := Copy(Id, 1, Pos('#', Id) - 1);
    Id := Trim(Id);
    if Id <> '' then
      Result := Result + [Id];
  end;
end;

class function TGoldenCorpus.Compare(const AFileName: string; const AMarkers: TArray<TGoldenMarker>;
  const AFindings: TArray<TRuleFinding>; const AKnownIds, APlannedIds: TArray<string>): TGoldenResult;
var
  Marker: TGoldenMarker;
  Finding: TRuleFinding;
  Found: Boolean;
  Place: string;
begin
  Result := Default(TGoldenResult);
  for Marker in AMarkers do
  begin
    Place := Format('%s(%d): %s', [AFileName, Marker.Line + 1, Marker.RuleId]);
    if not Contains(AKnownIds, Marker.RuleId) then
    begin
      if Contains(APlannedIds, Marker.RuleId) then
        Result.Skipped := Result.Skipped + [Place + ' ist geplant und wird übersprungen']
      else
        Result.Unknown := Result.Unknown + [Place + ' ist keine bekannte Regel'];
      Continue;
    end;
    Found := False;
    for Finding in AFindings do
      if SameText(Finding.RuleId, Marker.RuleId) and (Finding.Range.StartPos.Line = Marker.Line) then
      begin
        Found := True;
        Break;
      end;
    if Marker.Expected and not Found then
      Result.Missing := Result.Missing + [Place + ' erwartet, aber nicht gemeldet']
    else if not Marker.Expected and Found then
      Result.FalseAlarms := Result.FalseAlarms + [Place + ' gemeldet, obwohl KEIN-TREFFER']
  end;
end;

class function TGoldenCorpus.Rates(const ACsv: string): TArray<TRuleRate>;
var
  Lines, Columns: TArray<string>;
  Index, Rate, Swap: Integer;
  Verdict: string;
  Temp: TRuleRate;
begin
  Result := nil;
  Lines := SplitLines(ACsv);
  // Zeile 0 ist die Kopfzeile.
  for Index := 1 to High(Lines) do
  begin
    Columns := Lines[Index].Split([',']);
    if Length(Columns) < 4 then
      Continue;
    Rate := -1;
    for Swap := 0 to High(Result) do
      if SameText(Result[Swap].RuleId, Trim(Columns[0])) then
        Rate := Swap;
    if Rate < 0 then
    begin
      Temp := Default(TRuleRate);
      Temp.RuleId := Trim(Columns[0]);
      Result := Result + [Temp];
      Rate := High(Result);
    end;
    Verdict := LowerCase(Trim(Columns[3]));
    if Verdict = 'richtig' then
      Inc(Result[Rate].Correct)
    else if Verdict = 'falsch' then
      Inc(Result[Rate].Wrong)
    else
      raise EArgumentException.CreateFmt('Zeile %d: Bewertung "%s" ist weder richtig noch falsch',
        [Index + 1, Columns[3]]);
  end;
  // Wenige Regeln: einfaches Einfügesortieren.
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
      TFileChecker.CheckText([Rule], ASettings, '', Text);
    Timing.RuleId := Rule.Descriptor.Id;
    Timing.Milliseconds := Watch.Elapsed.TotalMilliseconds;
    Result := Result + [Timing];
  end;
end;

end.
