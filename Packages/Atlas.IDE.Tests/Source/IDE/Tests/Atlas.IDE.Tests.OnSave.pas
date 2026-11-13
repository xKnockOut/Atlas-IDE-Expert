unit Atlas.IDE.Tests.OnSave;

// Betroffene Tests nach dem Speichern im Hintergrund (#1775, tests.onSave):
// - Base meldet jede gespeicherte Datei (IAtlasFollowsSaves); Units,
//   Formulare und Include-Dateien kommen in die Warteschlange
//   (Atlas.Core.Tests.OnSave).
// - Ein Lauf: Der Server ermittelt die betroffenen Tests nur der
//   gespeicherten Dateien seit dem letzten Commit (Tiefe tests.affectedDepth,
//   Atlas.IDE.Tests.Affected.Determine); dann laufen sie über den Testläufer
//   im Hintergrund (RunQuiet, gebaut wie mit „Vor den Tests bauen“).
// - Kein Fenster springt auf: Fortschritt und Ergebnis stehen in der Zeile
//   atlas.tests.onSave des Atlas-Statusfelds; ein Klick zeigt die Ausgabe des
//   letzten Laufs in der Meldungsansicht. Marken der Code Lens und Atlas-
//   Probleme folgen dem Lauf wie nach „Tests ausführen“.
// - Speichern während eines Laufs: höchstens ein Folgelauf mit allen bis dahin
//   gespeicherten Dateien. Nicht während einer Debug-Sitzung, eines Builds
//   oder eines anderen Testlaufs; mehr als tests.onSave.max Tests oder alle
//   nötig: kein Lauf, Hinweis im Statusfeld. Im abgesicherten Start läuft das
//   Modul nicht (MinLevel Normal).

interface

uses
  System.SysUtils,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Registry,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Tests.OnSave,
  Atlas.IDE.Tests.Output,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeTestsOnSave = class
  public const
    cStatusId = 'atlas.tests.onSave';
    cStatusOrder = 45;
  private
    FTests: TAtlasIdeTests;
    FOutput: TAtlasIdeTestsOutput;
    FQueue: TAtlasTestsOnSaveQueue;
    FLine: TAtlasStatusLine;
    FLineRef: IAtlasStatusItem;
    /// <summary>Tests des laufenden Laufs (für „3/3 bestanden“).</summary>
    FCount: Integer;
    procedure Kick;
    procedure Resolved(const AFiles: TArray<string>; const AFound: TAtlasAffectedTests; const AError: string);
    procedure Ended(const AEnd: TAtlasTestsQuietEnd);
    procedure Done;
    procedure Show(const AText: string; AState: TAtlasStatusState; const ASummary: string);
    function Situation: TAtlasOnSaveSituation;
  public
    /// <summary>ATests und AOutput gehören dem Aufrufer und leben länger; setzt AOutput.OnQuietEnded.</summary>
    constructor Create(ATests: TAtlasIdeTests; AOutput: TAtlasIdeTestsOutput);
    destructor Destroy; override;
    /// <summary>Eine Datei wurde gespeichert (Hauptthread).</summary>
    procedure FileSaved(const AFileName: string);
    /// <summary>Einstellungen übernommen: Ist tests.onSave aus, verschwinden Warteschlange und Statuszeile.</summary>
    procedure ApplySettings;
    /// <summary>Klick auf die Statuszeile: Ausgabe des letzten Laufs in der Meldungsansicht.</summary>
    procedure ShowResults;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Affected;

/// <summary>Läuft eine Debug-Sitzung?</summary>
function Debugging: Boolean;
var
  mDebugger: IOTADebuggerServices;
begin
  Result := Supports(BorlandIDEServices, IOTADebuggerServices, mDebugger) and (mDebugger.ProcessCount > 0);
end;

/// <summary>Läuft ein Build des Benutzers oder auf Auftrag?</summary>
function Building: Boolean;
begin
  Result := (TAtlasIdeHost.CompileEvents <> nil) and TAtlasIdeHost.CompileEvents.Compiling;
end;

/// <summary>Kurzer Name der ersten Datei für Meldungen.</summary>
function FirstName(const AFiles: TArray<string>): string;
begin
  Result := '';
  if Length(AFiles) > 0 then
  begin
    Result := ExtractFileName(AFiles[0]);
  end;
end;

{ TAtlasIdeTestsOnSave }

constructor TAtlasIdeTestsOnSave.Create(ATests: TAtlasIdeTests; AOutput: TAtlasIdeTestsOutput);
begin
  inherited Create;
  FTests := ATests;
  FOutput := AOutput;
  FQueue := TAtlasTestsOnSaveQueue.Create;
  FOutput.OnQuietEnded := Ended;
end;

destructor TAtlasIdeTestsOnSave.Destroy;
begin
  FOutput.OnQuietEnded := nil;
  if FLine <> nil then
  begin
    FLine.Detach;
    TAtlasStatusRegistry.Default.Remove(cStatusId);
  end;
  FLineRef := nil;
  FQueue.Free;
  inherited Destroy;
end;

function TAtlasIdeTestsOnSave.Situation: TAtlasOnSaveSituation;
begin
  Result := Default(TAtlasOnSaveSituation);
  Result.Debugging := Debugging;
  Result.Building := Building;
  Result.TestsBusy := FTests.Busy;
end;

procedure TAtlasIdeTestsOnSave.Show(const AText: string; AState: TAtlasStatusState; const ASummary: string);
begin
  if FLine = nil then
  begin
    FLine := TAtlasStatusLine.Create(TAtlasStatusRegistry.Default, cStatusId, cStatusOrder, ShowResults);
    FLineRef := FLine;
    TAtlasStatusRegistry.Default.Add(FLineRef);
  end;
  FLine.Update(AText, AState, ASummary);
end;

procedure TAtlasIdeTestsOnSave.FileSaved(const AFileName: string);
begin
  if not TAtlasIdeSettings.Current.TestsOnSave or not TAtlasTestsOnSave.Counts(AFileName) then
  begin
    Exit;
  end;
  if FQueue.Add(AFileName) then
  begin
    Kick;
  end;
end;

procedure TAtlasIdeTestsOnSave.Kick;
var
  mFiles: TArray<string>;
  mBlock: TAtlasOnSaveBlock;
  mText: TAtlasTestsTextId;
begin
  mFiles := FQueue.Take;
  mBlock := TAtlasTestsOnSave.Block(TAtlasIdeSettings.Current, Situation);
  if mBlock <> TAtlasOnSaveBlock.None then
  begin
    // Kein Folgelauf für gesperrte Speicherungen: Das nächste Speichern versucht es neu.
    FQueue.Clear;
    FQueue.Finish;
    case mBlock of
      TAtlasOnSaveBlock.Debugging:
        mText := TAtlasTestsTextId.TestsOnSaveDebugging;
      TAtlasOnSaveBlock.Building:
        mText := TAtlasTestsTextId.TestsOnSaveBuilding;
      TAtlasOnSaveBlock.TestsBusy:
        mText := TAtlasTestsTextId.TestsOnSaveBusy;
    else
      Exit;
    end;
    Show(TAtlasTestsStrings.Text(mText), TAtlasStatusState.Neutral, '');
    Exit;
  end;
  Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveFinding, [FirstName(mFiles)]), TAtlasStatusState.Yellow,
    TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveSummaryRunning));
  if not TAtlasIdeAffectedTests.Determine(mFiles,
    procedure(const AFound: TAtlasAffectedTests; const AError: string)
    begin
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        begin
          Resolved(mFiles, AFound, AError);
        end);
    end) then
  begin
    Show(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveNoServer), TAtlasStatusState.Neutral, '');
    Done;
  end;
end;

procedure TAtlasIdeTestsOnSave.Resolved(const AFiles: TArray<string>; const AFound: TAtlasAffectedTests;
  const AError: string);
var
  mReason: string;
begin
  // Inzwischen ausgeschaltet: still beenden.
  if not TAtlasIdeSettings.Current.TestsOnSave then
  begin
    Done;
    Exit;
  end;
  if AError <> '' then
  begin
    Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveNotFound, [AError]), TAtlasStatusState.Yellow,
      TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveSummarySkipped));
    Done;
    Exit;
  end;
  FCount := Length(AFound.Tests);
  case TAtlasTestsOnSave.Verdict(FCount, AFound.All, TAtlasIdeSettings.Current.TestsOnSaveMax) of
    TAtlasOnSaveVerdict.NoTests:
      Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveNone, [FirstName(AFiles)]), TAtlasStatusState.Green,
        '');
    TAtlasOnSaveVerdict.TooMany:
      Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveTooMany, [FCount,
        TAtlasIdeSettings.Current.TestsOnSaveMax]), TAtlasStatusState.Yellow,
        TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveSummarySkipped));
    TAtlasOnSaveVerdict.AllNeeded:
      Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveAll, [AFound.AllReason]), TAtlasStatusState.Yellow,
        TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveSummarySkipped));
  else
    // Erst die Zeile, dann der Lauf: Bricht er sofort ab, meldet Ended das Ende schon während RunQuiet.
    Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveRunning, [FCount]), TAtlasStatusState.Yellow,
      TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveSummaryRunning));
    // Der Server meldet nur Tests aus Testprogrammen: Eine Datei genügt, um das Testprojekt zu finden.
    if FTests.RunQuiet(AFound.Tests[0].FileName, AFound.Run, mReason) then
    begin
      Exit;
    end;
    Show(mReason, TAtlasStatusState.Yellow, TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveSummarySkipped));
  end;
  Done;
end;

procedure TAtlasIdeTestsOnSave.Ended(const AEnd: TAtlasTestsQuietEnd);
begin
  if not AEnd.Reported then
  begin
    Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveEnded, [AEnd.Text]), TAtlasStatusState.Red,
      TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveSummarySkipped));
  end
  else if AEnd.Failed > 0 then
  begin
    Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveFailed, [AEnd.Failed, AEnd.Total]),
      TAtlasStatusState.Red, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveSummaryFailed, [AEnd.Failed]));
  end
  else
  begin
    Show(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSavePassed, [AEnd.Passed, AEnd.Total]),
      TAtlasStatusState.Green, '');
  end;
  Done;
end;

procedure TAtlasIdeTestsOnSave.Done;
begin
  if FQueue.Active and FQueue.Finish then
  begin
    Kick;
  end;
end;

procedure TAtlasIdeTestsOnSave.ApplySettings;
begin
  if TAtlasIdeSettings.Current.TestsOnSave then
  begin
    Exit;
  end;
  FQueue.Clear;
  if FLine <> nil then
  begin
    FLine.Detach;
    TAtlasStatusRegistry.Default.Remove(cStatusId);
    FLine := nil;
    FLineRef := nil;
  end;
end;

procedure TAtlasIdeTestsOnSave.ShowResults;
begin
  if not FOutput.ShowLast then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsOnSaveNoResults));
  end;
end;

end.
