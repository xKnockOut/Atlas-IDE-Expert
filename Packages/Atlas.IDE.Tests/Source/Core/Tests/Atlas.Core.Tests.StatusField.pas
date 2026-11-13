unit Atlas.Core.Tests.StatusField;

// Teststand als Feld der Atlas-Statusleiste (#1777), ohne VCL und Open Tools
// API:
// - Text: „Tests 41/42“ (bestanden/gelaufen ohne übersprungene) für das
//   Testprojekt der aktuellen Datei; während eines Laufs „Tests laufen …“,
//   vor dem ersten Lauf der Sitzung „Tests –“. Ohne Testprojekt kein Feld.
// - Ampel: rot mit Fehlschlägen, gelb während eines Laufs oder mit veralteten
//   Ergebnissen, grün, wenn alles bestand; ohne Lauf neutral.
// - Tooltip: Projekt, letzter Lauf (Uhrzeit, Dauer), Zahl der übersprungenen
//   und veralteten Tests, was ein Klick tut (fehlgeschlagene erneut bzw. alle
//   ausführen) und der Hinweis auf das Rechtsklick-Menü.

interface

uses
  Atlas.Core.Status.Contract,
  Atlas.Text.TestResults;

type
  /// <summary>Stand, aus dem das Feld entsteht.</summary>
  TAtlasTestStatusInput = record
    /// <summary>Name des Testprojekts; '' = keins (kein Feld).</summary>
    Project: string;
    /// <summary>Ein Lauf ist im Gange.</summary>
    Busy: Boolean;
    /// <summary>Ergebnisse dieser Sitzung (leer = noch kein Lauf).</summary>
    Cases: TArray<TTestCaseResult>;
    /// <summary>Ende des letzten Laufs; 0 = unbekannt.</summary>
    LastRun: TDateTime;
    /// <summary>Dauer des letzten Laufs; 0 = unbekannt.</summary>
    DurationMs: Int64;
    /// <summary>Tests, deren Ergebnis veraltet ist (#1770); -1 = unbekannt.</summary>
    Stale: Integer;
  end;

  /// <summary>Texte des Felds (Platzhalter wie Format).</summary>
  TAtlasTestStatusTexts = record
    /// <summary>%d bestanden, %d gelaufen.</summary>
    Field: string;
    Running: string;
    NotRun: string;
    /// <summary>%s Name des Testprojekts.</summary>
    Project: string;
    /// <summary>%s Uhrzeit, %s Dauer.</summary>
    LastRun: string;
    NoRunYet: string;
    /// <summary>%d bestanden, %d fehlgeschlagen, %d übersprungen.</summary>
    Counts: string;
    /// <summary>%d veraltet.</summary>
    Stale: string;
    ClickFailed: string;
    ClickAll: string;
    Context: string;
    DecimalSeparator: Char;
  end;

  TAtlasTestStatus = record
    Visible: Boolean;
    Text: string;
    Hint: string;
    State: TAtlasStatusState;
    Passed: Integer;
    Failed: Integer;
    Skipped: Integer;
    /// <summary>Ein Klick führt die fehlgeschlagenen erneut aus (sonst alle).</summary>
    RerunFailed: Boolean;
  end;

  TAtlasTestStatusField = class
  public
    /// <summary>Bestanden, fehlgeschlagen (auch Fehler) und übersprungen in ACases.</summary>
    class procedure Count(const ACases: TArray<TTestCaseResult>; out APassed, AFailed, ASkipped: Integer); static;
    /// <summary>Ampel zu den Zahlen; ohne Ergebnisse neutral.</summary>
    class function StateOf(ABusy: Boolean; APassed, AFailed, AStale: Integer): TAtlasStatusState; static;
    /// <summary>Feld aus AInput; ohne Projekt nicht sichtbar.</summary>
    class function Build(const AInput: TAtlasTestStatusInput; const ATexts: TAtlasTestStatusTexts): TAtlasTestStatus;
      static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasTestStatusField }

class procedure TAtlasTestStatusField.Count(const ACases: TArray<TTestCaseResult>; out APassed, AFailed,
  ASkipped: Integer);
var
  mCase: TTestCaseResult;
begin
  APassed := 0;
  AFailed := 0;
  ASkipped := 0;
  for mCase in ACases do
  begin
    case mCase.Outcome of
      TTestOutcome.Passed:
        Inc(APassed);
      TTestOutcome.Skipped:
        Inc(ASkipped);
    else
      Inc(AFailed);
    end;
  end;
end;

class function TAtlasTestStatusField.StateOf(ABusy: Boolean; APassed, AFailed, AStale: Integer): TAtlasStatusState;
begin
  if ABusy then
  begin
    Exit(TAtlasStatusState.Yellow);
  end;
  if AFailed > 0 then
  begin
    Exit(TAtlasStatusState.Red);
  end;
  if APassed = 0 then
  begin
    Exit(TAtlasStatusState.Neutral);
  end;
  if AStale > 0 then
  begin
    Exit(TAtlasStatusState.Yellow);
  end;
  Result := TAtlasStatusState.Green;
end;

/// <summary>Zeile „Letzter Lauf“ bzw. „noch kein Lauf“.</summary>
function RunLine(const AInput: TAtlasTestStatusInput; const ATexts: TAtlasTestStatusTexts): string;
var
  mTime: string;
  mHour, mMinute, mSecond, mMilli: Word;
begin
  if Length(AInput.Cases) = 0 then
  begin
    Exit(ATexts.NoRunYet);
  end;
  mTime := '–';
  if AInput.LastRun > 0 then
  begin
    DecodeTime(AInput.LastRun, mHour, mMinute, mSecond, mMilli);
    mTime := Format('%.2d:%.2d', [mHour, mMinute]);
  end;
  Result := Format(ATexts.LastRun, [mTime, TTestResults.DurationText(AInput.DurationMs, ATexts.DecimalSeparator)]);
end;

class function TAtlasTestStatusField.Build(const AInput: TAtlasTestStatusInput;
  const ATexts: TAtlasTestStatusTexts): TAtlasTestStatus;
var
  mLines: TArray<string>;
begin
  Result := Default(TAtlasTestStatus);
  if AInput.Project = '' then
  begin
    Exit;
  end;
  Result.Visible := True;
  Count(AInput.Cases, Result.Passed, Result.Failed, Result.Skipped);
  Result.State := StateOf(AInput.Busy, Result.Passed, Result.Failed, AInput.Stale);
  Result.RerunFailed := Result.Failed > 0;
  if AInput.Busy then
  begin
    Result.Text := ATexts.Running;
  end
  else if Length(AInput.Cases) = 0 then
  begin
    Result.Text := ATexts.NotRun;
  end
  else
  begin
    Result.Text := Format(ATexts.Field, [Result.Passed, Result.Passed + Result.Failed]);
  end;
  mLines := TArray<string>.Create(Format(ATexts.Project, [AInput.Project]), RunLine(AInput, ATexts));
  if Length(AInput.Cases) > 0 then
  begin
    mLines := mLines + [Format(ATexts.Counts, [Result.Passed, Result.Failed, Result.Skipped])];
  end;
  if AInput.Stale > 0 then
  begin
    mLines := mLines + [Format(ATexts.Stale, [AInput.Stale])];
  end;
  if Result.RerunFailed then
  begin
    mLines := mLines + [ATexts.ClickFailed];
  end
  else
  begin
    mLines := mLines + [ATexts.ClickAll];
  end;
  mLines := mLines + [ATexts.Context];
  Result.Hint := string.Join(sLineBreak, mLines);
end;

end.
