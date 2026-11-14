unit Atlas.IDE.Tests.Compare;

// Erwartet und erhalten vergleichen in der IDE (#1779, tests.compare):
// - Nach jedem gemeldeten Lauf (Haken OnReported des Läufers) merkt sich das
//   Modul je Test die Fehlschläge mit erwartetem und erhaltenem Wert
//   (TTestCaseResult.HasValues); ein späterer Erfolg oder ein Fehlschlag ohne
//   Werte löscht den Eintrag. Den Lauf reicht es danach an ANext weiter
//   (veraltete Ergebnisse, #1770), denn der Läufer hat einen Haken.
// - Befehl „Erwartet und erhalten vergleichen“ (Run): Fehlschlag des Tests
//   am Cursor (Testunit im oberen Editor, auch ein Fall eines [TestCase]),
//   sonst der zuletzt gemeldete; zeigt das Fenster Atlas.UI.Tests.Compare,
//   mit tests.compare.format JSON und XML eingerückt.
// - Ohne Fehlschlag mit Werten eine Zeile in der Meldungsansicht.
// - Knöpfe „Vergleichen“: an der Testmarke (CanCompare/Show mit der Auswahl
//   der Marke), im Befund-Hover (HasValuesAt/CompareAt, Zeile im oberen
//   Editor) und auf der Kachel „Testergebnisse“ (HasValues/CompareTest mit
//   dem vollen Namen); die beiden letzten über IAtlasTestValues des Moduls.
// - Vergleichsdateien (#1881, tests.approvalFiles): Ein Fehlschlag mit der
//   Meldung der Hilfs-Unit Atlas.Testing.Approval zählt wie einer mit Werten.
//   Das Fenster zeigt dann approved- und received-Datei; „Als neue Erwartung
//   übernehmen“ ersetzt die approved-Datei und vergisst den Fehlschlag, „Zum
//   Test“ springt zum Methodenkopf. Die Testmarke heißt dann „Abweichung ·
//   Vergleich“ bzw. „Neu · Vergleich“ (CaptionOf).

interface

uses
  System.Generics.Collections,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Debug,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Approval,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeTestCompare = class
  private
    FTests: TAtlasIdeTests;
    FNext: TAtlasTestsReportedProc;
    /// <summary>Fehlschläge mit Werten je Test (Schlüssel klein: Unit.Fixture.Methode[.Fall]).</summary>
    FFailures: TDictionary<string, TTestCaseResult>;
    /// <summary>Testprojekt je Schlüssel aus FFailures (für „Zum Test“).</summary>
    FProjects: TDictionary<string, string>;
    /// <summary>Testprojekt des zuletzt gemeldeten Laufs; '' ohne.</summary>
    FLastProject: string;
    /// <summary>Schlüssel des zuletzt gemeldeten Fehlschlags mit Werten; '' ohne.</summary>
    FLast: string;
    /// <summary>Fehlschlag des Tests an ALine (0-basiert) im oberen Editor; False ohne.</summary>
    function AtLine(ALine: Integer; out ACase: TTestCaseResult): Boolean;
    /// <summary>Fehlschlag mit Werten zu ASelection (bei einer [TestCase]-Methode ohne Fall der erste); False
    /// ohne.</summary>
    function Find(const ASelection: TAtlasTestSelection; out ACase: TTestCaseResult): Boolean;
    /// <summary>Fenster „Erwartet und erhalten“ für ACase; bei Vergleichsdateien mit Übernehmen und Sprung.
    /// </summary>
    procedure Open(const ACase: TTestCaseResult);
    /// <summary>Vergleichsdateien von ACase im Fenster; übernehmen bzw. zum Test springen.</summary>
    procedure OpenApproval(const ACase: TTestCaseResult; const AHit: TAtlasApprovalHit);
    procedure AcceptApproval(const AKey: string; const AHit: TAtlasApprovalHit);
    procedure GoToTest(const AKey: string; const ACase: TTestCaseResult);
    /// <summary>Lässt sich ACase vergleichen: Werte im Bericht oder Meldung der Vergleichsdateien (mit
    /// tests.approvalFiles)?</summary>
    class function Comparable(const ACase: TTestCaseResult): Boolean; static;
    /// <summary>Meldung der Vergleichsdateien in ACase (nur mit tests.approvalFiles).</summary>
    class function ApprovalOf(const ACase: TTestCaseResult; out AHit: TAtlasApprovalHit): Boolean; static;
  public
    /// <summary>ATests gehört dem Aufrufer und lebt länger; ANext bekommt jeden Lauf danach (nil = keiner).
    /// </summary>
    constructor Create(ATests: TAtlasIdeTests; const ANext: TAtlasTestsReportedProc);
    destructor Destroy; override;
    /// <summary>Fehlschläge mit Werten aus ARun merken (Haken OnReported).</summary>
    procedure Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
    /// <summary>Schlüssel eines Ergebnisses: Unit.Fixture.Methode[.Fall], klein.</summary>
    class function KeyOf(const AUnitName, AFixture, AMethod, ACaseName: string): string; static;
    /// <summary>Befehl „Erwartet und erhalten vergleichen“.</summary>
    procedure Run;
    /// <summary>Knopf der Testmarke: tests.compare an und ein Fehlschlag mit Werten zu ASelection.</summary>
    function CanCompare(const ASelection: TAtlasTestSelection): Boolean;
    procedure Show(const ASelection: TAtlasTestSelection);
    /// <summary>Befund-Hover: Test an ALine (0-basiert) der Testunit im oberen Editor.</summary>
    function HasValuesAt(ALine: Integer): Boolean;
    procedure CompareAt(ALine: Integer);
    /// <summary>Willkommensseite: Test AFullName (Unit.Fixture.Methode[.Fall]).</summary>
    function HasValues(const AFullName: string): Boolean;
    procedure CompareTest(const AFullName: string);
    /// <summary>Text der Testmarke zu ASelection: „Vergleichen“, bei Vergleichsdateien „Abweichung ·
    /// Vergleich“ bzw. „Neu · Vergleich“.</summary>
    function CaptionOf(const ASelection: TAtlasTestSelection): string;
    /// <summary>Befehl „Liegengebliebene .received-Dateien löschen“ (#1881): im Testprojekt des letzten Laufs,
    /// ohne Lauf im aktiven Projekt.</summary>
    procedure CleanApprovalFiles;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.ApprovalFiles,
  Atlas.UI.Tests.Compare,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeTestCompare }

constructor TAtlasIdeTestCompare.Create(ATests: TAtlasIdeTests; const ANext: TAtlasTestsReportedProc);
begin
  inherited Create;
  FTests := ATests;
  FNext := ANext;
  FFailures := TDictionary<string, TTestCaseResult>.Create;
  FProjects := TDictionary<string, string>.Create;
end;

destructor TAtlasIdeTestCompare.Destroy;
begin
  FNext := nil;
  FProjects.Free;
  FFailures.Free;
  inherited;
end;

class function TAtlasIdeTestCompare.KeyOf(const AUnitName, AFixture, AMethod, ACaseName: string): string;
begin
  Result := AnsiLowerCase(AUnitName + '.' + AFixture + '.' + AMethod);
  if ACaseName <> '' then
  begin
    Result := Result + '.' + AnsiLowerCase(ACaseName);
  end;
end;

procedure TAtlasIdeTestCompare.Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
var
  mCase: TTestCaseResult;
  mKey: string;
begin
  for mCase in ARun.Cases do
  begin
    mKey := KeyOf(mCase.UnitName, mCase.Fixture, mCase.Method, mCase.CaseName);
    if mCase.IsFailure and Comparable(mCase) then
    begin
      FFailures.AddOrSetValue(mKey, mCase);
      FProjects.AddOrSetValue(mKey, ATarget.Project);
      FLast := mKey;
    end
    else
    begin
      FFailures.Remove(mKey);
      FProjects.Remove(mKey);
    end;
  end;
  FLastProject := ATarget.Project;
  if not FFailures.ContainsKey(FLast) then
  begin
    FLast := '';
  end;
  if Assigned(FNext) then
  begin
    FNext(ATarget, ARun);
  end;
end;

function TAtlasIdeTestCompare.Find(const ASelection: TAtlasTestSelection; out ACase: TTestCaseResult): Boolean;
var
  mPrefix: string;
  mPair: TPair<string, TTestCaseResult>;
begin
  ACase := Default(TTestCaseResult);
  Result := (ASelection.Method <> '') and FFailures.TryGetValue(KeyOf(ASelection.UnitName, ASelection.Fixture,
    ASelection.Method, ASelection.CaseName), ACase);
  if Result or (ASelection.Method = '') or (ASelection.CaseName <> '') then
  begin
    Exit;
  end;
  // Methode mit [TestCase] ohne gewählten Fall: der erste Fall mit Fehlschlag.
  mPrefix := KeyOf(ASelection.UnitName, ASelection.Fixture, ASelection.Method, '') + '.';
  for mPair in FFailures do
  begin
    if mPair.Key.StartsWith(mPrefix) then
    begin
      ACase := mPair.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasIdeTestCompare.AtLine(ALine: Integer; out ACase: TTestCaseResult): Boolean;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mSelection: TAtlasTestSelection;
begin
  ACase := Default(TTestCaseResult);
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  Result := (FFailures.Count > 0) and (mView <> nil) and (mView.Buffer <> nil) and TAtlasTestDebug.SelectAt(
    TDUnitXSource.Scan(TTextLines.SplitLines(TAtlasEditorBuffer.Text(mView.Buffer))), ALine, mSelection) and
    Find(mSelection, ACase);
end;

class function TAtlasIdeTestCompare.ApprovalOf(const ACase: TTestCaseResult; out AHit: TAtlasApprovalHit): Boolean;
begin
  AHit := Default(TAtlasApprovalHit);
  Result := TAtlasIdeSettings.Current.TestsApprovalFiles and TAtlasTestApproval.Parse(ACase.Message, AHit);
end;

class function TAtlasIdeTestCompare.Comparable(const ACase: TTestCaseResult): Boolean;
var
  mHit: TAtlasApprovalHit;
begin
  Result := ACase.HasValues or ApprovalOf(ACase, mHit);
end;

procedure TAtlasIdeTestCompare.Open(const ACase: TTestCaseResult);
var
  mHit: TAtlasApprovalHit;
begin
  if ApprovalOf(ACase, mHit) then
  begin
    OpenApproval(ACase, mHit);
  end
  else
  begin
    TAtlasTestsCompareDialog.Execute(TAtlasTestRun.ShortName(ACase), ACase.Expected, ACase.Actual,
      TAtlasIdeSettings.Current.TestsCompareFormat);
  end;
end;

procedure TAtlasIdeTestCompare.OpenApproval(const ACase: TTestCaseResult; const AHit: TAtlasApprovalHit);
var
  mKey: string;
begin
  mKey := KeyOf(ACase.UnitName, ACase.Fixture, ACase.Method, ACase.CaseName);
  case TAtlasTestsCompareDialog.ExecuteApproval(TAtlasTestRun.ShortName(ACase),
    TAtlasTestApproval.ReadSide(AHit.Approved), TAtlasTestApproval.ReadSide(AHit.Received),
    TAtlasIdeSettings.Current.TestsCompareFormat) of
    TAtlasTestsCompareChoice.Close:
      ;
    TAtlasTestsCompareChoice.Accept:
      AcceptApproval(mKey, AHit);
    TAtlasTestsCompareChoice.GoToTest:
      GoToTest(mKey, ACase);
  end;
end;

procedure TAtlasIdeTestCompare.AcceptApproval(const AKey: string; const AHit: TAtlasApprovalHit);
begin
  case TAtlasTestApproval.Accept(AHit) of
    TAtlasApprovalAccept.Done:
      begin
        // Die Erwartung stimmt jetzt; der nächste Lauf zeigt, ob der Test grün ist.
        FFailures.Remove(AKey);
        FProjects.Remove(AKey);
        FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsApprovalAccepted,
          [ExtractFileName(AHit.Received), AHit.Approved]));
      end;
    TAtlasApprovalAccept.Missing:
      FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsApprovalMissing, [AHit.Received]));
    TAtlasApprovalAccept.Failed:
      FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsApprovalFailed, [AHit.Received, AHit.Approved]));
  end;
end;

procedure TAtlasIdeTestCompare.GoToTest(const AKey: string; const ACase: TTestCaseResult);
var
  mProject, mFileName: string;
  mLine: Integer;
begin
  if not FProjects.TryGetValue(AKey, mProject) or
    not TAtlasIdeTestDebugger.LocateByName(mProject, ACase.FullName, mFileName, mLine) then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsSlowestNotFound, [TAtlasTestRun.ShortName(ACase)]));
    Exit;
  end;
  // LocateByName zählt ab 1, der Editor ab 0.
  TAtlasIdeResults.Open(mFileName, Max(mLine - 1, 0), 0);
end;

function TAtlasIdeTestCompare.CaptionOf(const ASelection: TAtlasTestSelection): string;
var
  mCase: TTestCaseResult;
  mHit: TAtlasApprovalHit;
begin
  Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensCompare);
  if Find(ASelection, mCase) and ApprovalOf(mCase, mHit) then
  begin
    if mHit.Kind = TAtlasApprovalKind.Added then
    begin
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensApprovalNew);
    end
    else
    begin
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLensApproval);
    end;
  end;
end;

procedure TAtlasIdeTestCompare.Run;
var
  mEditors: IOTAEditorServices;
  mLine: Integer;
  mCase: TTestCaseResult;
begin
  if not TAtlasIdeSettings.Current.TestsCompare then
  begin
    Exit;
  end;
  mLine := -1;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) and (mEditors.TopView <> nil) then
  begin
    mLine := mEditors.TopView.CursorPos.Line - 1;
  end;
  if (not AtLine(mLine, mCase) and not FFailures.TryGetValue(FLast, mCase)) or not Comparable(mCase) then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCompareNone));
    Exit;
  end;
  Open(mCase);
end;

function TAtlasIdeTestCompare.CanCompare(const ASelection: TAtlasTestSelection): Boolean;
var
  mCase: TTestCaseResult;
begin
  // Comparable: Vergleichsdateien können inzwischen ausgeschaltet sein.
  Result := TAtlasIdeSettings.Current.TestsCompare and Find(ASelection, mCase) and Comparable(mCase);
end;

procedure TAtlasIdeTestCompare.Show(const ASelection: TAtlasTestSelection);
var
  mCase: TTestCaseResult;
begin
  if CanCompare(ASelection) and Find(ASelection, mCase) then
  begin
    Open(mCase);
  end;
end;

function TAtlasIdeTestCompare.HasValuesAt(ALine: Integer): Boolean;
var
  mCase: TTestCaseResult;
begin
  Result := TAtlasIdeSettings.Current.TestsCompare and AtLine(ALine, mCase) and Comparable(mCase);
end;

procedure TAtlasIdeTestCompare.CompareAt(ALine: Integer);
var
  mCase: TTestCaseResult;
begin
  if TAtlasIdeSettings.Current.TestsCompare and AtLine(ALine, mCase) and Comparable(mCase) then
  begin
    Open(mCase);
  end;
end;

function TAtlasIdeTestCompare.HasValues(const AFullName: string): Boolean;
var
  mCase: TTestCaseResult;
begin
  Result := TAtlasIdeSettings.Current.TestsCompare and FFailures.TryGetValue(AnsiLowerCase(AFullName), mCase) and
    Comparable(mCase);
end;

procedure TAtlasIdeTestCompare.CompareTest(const AFullName: string);
var
  mCase: TTestCaseResult;
begin
  // Schlüssel wie KeyOf: der volle Name ist Unit.Fixture.Methode[.Fall].
  if TAtlasIdeSettings.Current.TestsCompare and FFailures.TryGetValue(AnsiLowerCase(AFullName), mCase) and
    Comparable(mCase) then
  begin
    Open(mCase);
  end;
end;

procedure TAtlasIdeTestCompare.CleanApprovalFiles;
begin
  TAtlasIdeApprovalFiles.Clean(FTests, FLastProject);
end;

end.
