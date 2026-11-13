unit Atlas.IDE.Tests.BoundaryCases;

// Grenzfälle als Testfälle in der IDE (#2173, tests.boundaryCases):
// - Befehl „Grenzfälle vorschlagen …“ (Kontextmenü des Editors außerhalb von Testunits, Befehlspalette): Atlas
//   fragt den Server nach den Grenzfällen der Routine am Cursor (atlas.server.boundaryCases [uri, zeile,
//   höchstens], nebenläufig) und zeigt sie im Fenster Atlas.UI.Tests.BoundaryCases.
// - Übernehmen: atlas.server.boundaryTests schreibt die gewählten Fälle als [TestCase] an die Testmethode
//   Test<Routine>Cases der Testunit (vorhanden: neue Zeilen, sonst neue Methode); TAtlasIdeWorkspaceEdit legt
//   das Edit in den Puffer (ein Rückgängig-Schritt).
// - Heutiges Ergebnis übernehmen: wie Übernehmen, offene Erwartungen bekommen einen Platzhalter und die Zeile
//   „// heutiges Verhalten, nicht geprüft“ darüber. Dann baut Atlas das Testprojekt, führt die Fälle aus und
//   trägt im nächsten gemeldeten Lauf (Haken Remember vor den übrigen Haken von OnReported) die erhaltenen Werte
//   über die TestCase-Tabelle (atlas.server.testCases, #1879) ein, wieder ein Rückgängig-Schritt.
// Antworten des Servers erreichen das Objekt nur, solange das Modul es hält (Scope von RunServerCommandAsync).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Text.TestResults,
  Atlas.Core.Tests.CaseTable,
  Atlas.Core.Tests.BoundaryCases,
  Atlas.Core.Tests.Run,
  Atlas.IDE.Tests.Runner;

type
  TAtlasIdeBoundaryCases = class
  public const
    cTimeoutMs = 15000;
  private type
    /// <summary>Wartet auf den Lauf für „Heutiges Ergebnis übernehmen“.</summary>
    TToday = record
      Active: Boolean;
      TestFile: string;
      Method: string;
      Open: TArray<Boolean>;
    end;
  private
    FScope: IAtlasModuleScope;
    FTests: TAtlasIdeTests;
    FNext: TAtlasTestsReportedProc;
    FShowing: Boolean;
    FUri: string;
    FLine: Integer;
    FToday: TToday;
    function Ask(const ACommand, AArgumentsJson: string; const ADone: TProc<string>): Boolean;
    class function TodayLock: string; static;
    procedure Show(const ASuggestion: TAtlasBoundarySuggestion);
    procedure Apply(const ACases: TArray<TAtlasBoundaryCase>; AToday: Boolean);
    procedure Applied(const AJson: string; const ACases: TArray<TAtlasBoundaryCase>; AToday: Boolean);
    function WriteEdit(const AEditJson: string): Boolean;
    procedure StartToday(const AApplied: TAtlasBoundaryApplied; const AOpen: TArray<Boolean>);
    procedure FillToday(const AToday: TToday; const ARun: TTestRunResult);
    procedure TodayTable(const AToday: TToday; const ARun: TTestRunResult; const ATable: TAtlasTestCaseTable);
  public
    /// <summary>AScope und ATests gehören dem Modul und leben länger; ANext ist der bisherige Haken OnReported.
    /// </summary>
    constructor Create(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests; const ANext: TAtlasTestsReportedProc);
    /// <summary>Einstellungen tests.boundaryCases und tests.run.</summary>
    class function Wanted: Boolean; static;
    /// <summary>Grenzfälle der Routine am Cursor des oberen Editors.</summary>
    procedure OpenAtCursor;
    /// <summary>Grenzfälle der Routine an ALine (0-basiert) der Datei AFileName.</summary>
    procedure OpenAt(const AFileName: string; ALine: Integer);
    /// <summary>Haken OnReported: heutiges Ergebnis eintragen, dann an ANext weiter.</summary>
    procedure Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
  end;

implementation

uses
  System.UITypes,
  System.JSON,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Uris,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Tests.Projects,
  Atlas.UI.Tests.BoundaryCases,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeBoundaryCases }

constructor TAtlasIdeBoundaryCases.Create(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests;
  const ANext: TAtlasTestsReportedProc);
begin
  inherited Create;
  FScope := AScope;
  FTests := ATests;
  FNext := ANext;
end;

class function TAtlasIdeBoundaryCases.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and TAtlasIdeSettings.Current.TestsBoundaryCases;
end;

function TAtlasIdeBoundaryCases.Ask(const ACommand, AArgumentsJson: string; const ADone: TProc<string>): Boolean;
begin
  Result := (TAtlasIdeHost.ActiveSession <> nil) and TAtlasIdeHost.RunServerCommandAsync(FScope,
    TAtlasFeature.Build, ACommand, AArgumentsJson, cTimeoutMs, ADone);
end;

procedure TAtlasIdeBoundaryCases.OpenAtCursor;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView = nil) or (mView.Buffer = nil) then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryNone));
    Exit;
  end;
  OpenAt(mView.Buffer.FileName, mView.CursorPos.Line - 1);
end;

procedure TAtlasIdeBoundaryCases.OpenAt(const AFileName: string; ALine: Integer);
var
  mSelf: TAtlasIdeBoundaryCases;
begin
  if not Wanted or FShowing then
  begin
    Exit;
  end;
  FUri := TLspUris.FromPath(AFileName);
  FLine := ALine;
  mSelf := Self;
  if not Ask(TAtlasBoundaryCases.cCommand,
    TAtlasBoundaryCases.RequestJson(FUri, ALine, TAtlasIdeSettings.Current.TestsBoundaryMax),
    procedure(AAnswer: string)
    var
      mSuggestion: TAtlasBoundarySuggestion;
    begin
      if not TAtlasBoundaryCases.Parse(AAnswer, mSuggestion) or (mSuggestion.Cases = nil) then
      begin
        mSelf.FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryNone));
        Exit;
      end;
      mSelf.Show(mSuggestion);
    end) then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryNoServer));
  end;
end;

class function TAtlasIdeBoundaryCases.TodayLock: string;
begin
  Result := '';
  if TAtlasIdeTestProjects.TestProjects('') = nil then
  begin
    Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryNoTestProject);
  end;
end;

procedure TAtlasIdeBoundaryCases.Show(const ASuggestion: TAtlasBoundarySuggestion);
var
  mDialog: TAtlasTestsBoundaryDialog;
  mResult: Integer;
  mCases: TArray<TAtlasBoundaryCase>;
begin
  if FShowing then
  begin
    Exit;
  end;
  FShowing := True;
  try
    mDialog := TAtlasTestsBoundaryDialog.CreateDialog(nil, ASuggestion, TodayLock);
    try
      mResult := mDialog.ShowModal;
      mCases := mDialog.Cases;
    finally
      mDialog.Free;
    end;
  finally
    FShowing := False;
  end;
  if (mResult = mrOk) or (mResult = mrYes) then
  begin
    Apply(mCases, mResult = mrYes);
  end;
end;

procedure TAtlasIdeBoundaryCases.Apply(const ACases: TArray<TAtlasBoundaryCase>; AToday: Boolean);
var
  mSelf: TAtlasIdeBoundaryCases;
  mCases: TArray<TAtlasBoundaryCase>;
  mToday: Boolean;
  mOptions: TAtlasBoundaryApply;
begin
  if AToday and FTests.Busy then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBusy));
    Exit;
  end;
  mSelf := Self;
  mCases := ACases;
  mToday := AToday;
  mOptions := Default(TAtlasBoundaryApply);
  mOptions.Placeholders := AToday;
  if AToday then
  begin
    mOptions.Comment := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryTodayComment);
  end;
  if not Ask(TAtlasBoundaryCases.cApplyCommand, TAtlasBoundaryCases.ApplyJson(FUri, FLine, ACases, mOptions),
    procedure(AAnswer: string)
    begin
      mSelf.Applied(AAnswer, mCases, mToday);
    end) then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryNoServer));
  end;
end;

function TAtlasIdeBoundaryCases.WriteEdit(const AEditJson: string): Boolean;
var
  mEdit: TLspWorkspaceEdit;
  mValue: TJSONValue;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  mValue := TJSONObject.ParseJSONValue(AEditJson);
  try
    mEdit := TLspWorkspaceEdit.FromJson(mValue);
  finally
    mValue.Free;
  end;
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(mEdit, TAtlasUnopenedPolicy.OpenInEditor,
    TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryEditAction));
  Result := mOutcome.Error = '';
  if not Result then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryRefused, [mOutcome.Error]));
  end;
end;

procedure TAtlasIdeBoundaryCases.Applied(const AJson: string; const ACases: TArray<TAtlasBoundaryCase>;
  AToday: Boolean);
var
  mApplied: TAtlasBoundaryApplied;
begin
  if not TAtlasBoundaryCases.ParseApplied(AJson, mApplied) then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBoundaryNoServer));
    Exit;
  end;
  if mApplied.EditJson = '' then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryRefused, [mApplied.Reason]));
    Exit;
  end;
  if not WriteEdit(mApplied.EditJson) then
  begin
    Exit;
  end;
  FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryWritten,
    [Length(ACases), ExtractFileName(TLspUris.ToPath(mApplied.Uri))]));
  if AToday then
  begin
    StartToday(mApplied, TAtlasBoundaryCases.OpenCases(ACases));
  end;
end;

/// <summary>Fixture und Test der Methode AMethod in der Testunit AFileName (Text im Editor).</summary>
function FindMethod(const AFileName, AMethod: string; out AUnit: TDUnitXUnit;
  out AFixtureIndex, ATestIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  AUnit := TDUnitXSource.Scan(TTextLines.SplitLines(TAtlasIdeWorkspaceEdit.CurrentText(AFileName)));
  for mIndex := 0 to High(AUnit.Fixtures) do
  begin
    if AUnit.Find(AUnit.Fixtures[mIndex].Name, AMethod, AFixtureIndex, ATestIndex) then
    begin
      Exit(True);
    end;
  end;
  AFixtureIndex := -1;
  ATestIndex := -1;
  Result := False;
end;

procedure TAtlasIdeBoundaryCases.StartToday(const AApplied: TAtlasBoundaryApplied; const AOpen: TArray<Boolean>);
var
  mUnit: TDUnitXUnit;
  mFixture, mTest: Integer;
begin
  FToday := Default(TToday);
  FToday.TestFile := TLspUris.ToPath(AApplied.Uri);
  FToday.Method := AApplied.Method;
  FToday.Open := AOpen;
  if not FindMethod(FToday.TestFile, FToday.Method, mUnit, mFixture, mTest) then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryTodayMissing, [FToday.Method]));
    Exit;
  end;
  FToday.Active := True;
  FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryTodayRunning,
    [ExtractFileName(FToday.TestFile)]));
  FTests.RunTests(FToday.TestFile, TDUnitXCommandLine.RunNames(mUnit, mFixture, mTest, -1), True);
end;

procedure TAtlasIdeBoundaryCases.Remember(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
var
  mToday: TToday;
begin
  if FToday.Active then
  begin
    // Der nächste gemeldete Lauf ist der eigene (der Läufer startet keinen zweiten, solange einer läuft).
    mToday := FToday;
    FToday := Default(TToday);
    FillToday(mToday, ARun);
  end;
  if Assigned(FNext) then
  begin
    FNext(ATarget, ARun);
  end;
end;

procedure TAtlasIdeBoundaryCases.FillToday(const AToday: TToday; const ARun: TTestRunResult);
var
  mSelf: TAtlasIdeBoundaryCases;
  mToday: TToday;
  mRun: TTestRunResult;
  mUnit: TDUnitXUnit;
  mFixture, mTest: Integer;
begin
  if not FindMethod(AToday.TestFile, AToday.Method, mUnit, mFixture, mTest) then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryTodayMissing, [AToday.Method]));
    Exit;
  end;
  mSelf := Self;
  mToday := AToday;
  mRun := ARun;
  Ask(TAtlasTestCaseTables.cCommand, TAtlasTestCaseTables.RequestJson(TLspUris.FromPath(AToday.TestFile),
    mUnit.Fixtures[mFixture].Tests[mTest].Line),
    procedure(AAnswer: string)
    var
      mTable: TAtlasTestCaseTable;
    begin
      if TAtlasTestCaseTables.Parse(AAnswer, mTable) then
      begin
        mSelf.TodayTable(mToday, mRun, mTable);
      end;
    end);
end;

procedure TAtlasIdeBoundaryCases.TodayTable(const AToday: TToday; const ARun: TTestRunResult;
  const ATable: TAtlasTestCaseTable);
var
  mSelf: TAtlasIdeBoundaryCases;
  mRows: TArray<TAtlasTestCaseRow>;
  mFilled, mCount: Integer;
begin
  mRows := TAtlasBoundaryCases.TodayRows(ATable, AToday.Open, ARun, mFilled);
  if mFilled = 0 then
  begin
    FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryTodayMissing, [AToday.Method]));
    Exit;
  end;
  mSelf := Self;
  mCount := Length(AToday.Open);
  Ask(TAtlasTestCaseTables.cCommand, TAtlasTestCaseTables.ProposalJson(ATable.Uri, ATable.MethodLine, mRows),
    procedure(AAnswer: string)
    var
      mProposal: TAtlasTestCaseProposal;
    begin
      if not TAtlasTestCaseTables.ParseProposal(AAnswer, mProposal) or (mProposal.EditJson = '') then
      begin
        mSelf.FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryRefused, [mProposal.Reason]));
      end
      else if mSelf.WriteEdit(mProposal.EditJson) then
      begin
        mSelf.FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBoundaryTodayDone, [mFilled, mCount]));
      end;
    end);
end;

end.
