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

interface

uses
  System.Generics.Collections,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.Debug,
  Atlas.Core.Tests.Run,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeTestCompare = class
  private
    FTests: TAtlasIdeTests;
    FNext: TAtlasTestsReportedProc;
    /// <summary>Fehlschläge mit Werten je Test (Schlüssel klein: Unit.Fixture.Methode[.Fall]).</summary>
    FFailures: TDictionary<string, TTestCaseResult>;
    /// <summary>Schlüssel des zuletzt gemeldeten Fehlschlags mit Werten; '' ohne.</summary>
    FLast: string;
    /// <summary>Fehlschlag des Tests an ALine (0-basiert) im oberen Editor; False ohne.</summary>
    function AtLine(ALine: Integer; out ACase: TTestCaseResult): Boolean;
    /// <summary>Fehlschlag mit Werten zu ASelection (bei einer [TestCase]-Methode ohne Fall der erste); False
    /// ohne.</summary>
    function Find(const ASelection: TAtlasTestSelection; out ACase: TTestCaseResult): Boolean;
    /// <summary>Fenster „Erwartet und erhalten“ für ACase.</summary>
    class procedure Open(const ACase: TTestCaseResult); static;
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
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Tests.Compare,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeTestCompare }

constructor TAtlasIdeTestCompare.Create(ATests: TAtlasIdeTests; const ANext: TAtlasTestsReportedProc);
begin
  inherited Create;
  FTests := ATests;
  FNext := ANext;
  FFailures := TDictionary<string, TTestCaseResult>.Create;
end;

destructor TAtlasIdeTestCompare.Destroy;
begin
  FNext := nil;
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
    if mCase.IsFailure and mCase.HasValues then
    begin
      FFailures.AddOrSetValue(mKey, mCase);
      FLast := mKey;
    end
    else
    begin
      FFailures.Remove(mKey);
    end;
  end;
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

class procedure TAtlasIdeTestCompare.Open(const ACase: TTestCaseResult);
begin
  TAtlasTestsCompareDialog.Execute(TAtlasTestRun.ShortName(ACase), ACase.Expected, ACase.Actual,
    TAtlasIdeSettings.Current.TestsCompareFormat);
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
  if not AtLine(mLine, mCase) and not FFailures.TryGetValue(FLast, mCase) then
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
  Result := TAtlasIdeSettings.Current.TestsCompare and Find(ASelection, mCase);
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
  Result := TAtlasIdeSettings.Current.TestsCompare and AtLine(ALine, mCase);
end;

procedure TAtlasIdeTestCompare.CompareAt(ALine: Integer);
var
  mCase: TTestCaseResult;
begin
  if TAtlasIdeSettings.Current.TestsCompare and AtLine(ALine, mCase) then
  begin
    Open(mCase);
  end;
end;

function TAtlasIdeTestCompare.HasValues(const AFullName: string): Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestsCompare and FFailures.ContainsKey(AnsiLowerCase(AFullName));
end;

procedure TAtlasIdeTestCompare.CompareTest(const AFullName: string);
var
  mCase: TTestCaseResult;
begin
  // Schlüssel wie KeyOf: der volle Name ist Unit.Fixture.Methode[.Fall].
  if TAtlasIdeSettings.Current.TestsCompare and FFailures.TryGetValue(AnsiLowerCase(AFullName), mCase) then
  begin
    Open(mCase);
  end;
end;

end.
