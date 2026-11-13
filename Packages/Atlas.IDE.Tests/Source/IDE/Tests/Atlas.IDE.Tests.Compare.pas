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

interface

uses
  System.Generics.Collections,
  Atlas.Text.TestResults,
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
    /// <summary>Fehlschlag des Tests am Cursor; False ohne.</summary>
    function AtCursor(out ACase: TTestCaseResult): Boolean;
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
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Debug,
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

function TAtlasIdeTestCompare.AtCursor(out ACase: TTestCaseResult): Boolean;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mSelection: TAtlasTestSelection;
  mPrefix: string;
  mPair: TPair<string, TTestCaseResult>;
begin
  ACase := Default(TTestCaseResult);
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView = nil) or (mView.Buffer = nil) or not TAtlasTestDebug.SelectAt(
    TDUnitXSource.Scan(TTextLines.SplitLines(TAtlasEditorBuffer.Text(mView.Buffer))), mView.CursorPos.Line - 1,
    mSelection) or (mSelection.Method = '') then
  begin
    Exit(False);
  end;
  if FFailures.TryGetValue(KeyOf(mSelection.UnitName, mSelection.Fixture, mSelection.Method, mSelection.CaseName),
    ACase) then
  begin
    Exit(True);
  end;
  // Methode mit [TestCase] am Cursor: der erste Fall mit Fehlschlag.
  mPrefix := KeyOf(mSelection.UnitName, mSelection.Fixture, mSelection.Method, '') + '.';
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

procedure TAtlasIdeTestCompare.Run;
var
  mCase: TTestCaseResult;
begin
  if not TAtlasIdeSettings.Current.TestsCompare then
  begin
    Exit;
  end;
  if not AtCursor(mCase) and not FFailures.TryGetValue(FLast, mCase) then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCompareNone));
    Exit;
  end;
  TAtlasTestsCompareDialog.Execute(TAtlasTestRun.ShortName(mCase), mCase.Expected, mCase.Actual,
    TAtlasIdeSettings.Current.TestsCompareFormat);
end;

end.
