unit Atlas.IDE.Tests.CaseTable;

// TestCase-Tabelle in der IDE (#1879, tests.testCaseTable):
// - Öffnen: Befehl „TestCase-Tabelle bearbeiten …“ (Cursor an Attributen oder Deklaration einer Testmethode mit
//   [TestCase]) bzw. Klick auf „Tabelle“ an der Marke der Testlinse. Atlas fragt den Server
//   (atlas.server.testCases [uri, zeile], nebenläufig, startet ihn bei Bedarf) und zeigt die Antwort im Fenster
//   Atlas.UI.Tests.CaseTable.
// - Prüfen beim Tippen und Übernehmen: dieselbe Anfrage mit den Zeilen des Fensters; der Server antwortet mit
//   Fehlern je Zelle und einem WorkspaceEdit, das TAtlasIdeWorkspaceEdit in den Puffer schreibt (ein
//   Rückgängig-Schritt). Danach schließt das Fenster.
// - Letzter Lauf und Ausführen: Fälle über Atlas.Text.DUnitX im Puffer (gleiche Reihenfolge wie die Zeilen des
//   Servers), Stand über TAtlasIdeTests.TallyOf, Lauf über TAtlasIdeTestDebugger (Run bzw. nach dem Schließen
//   Debug), wie die Marke „Fall ausführen“ der Testlinse.
// Antworten des Servers erreichen das Fenster nur, solange es offen ist; das Modul hält es in FDialog.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.CaseTable,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Debug,
  Atlas.UI.Tests.CaseTable;

type
  TAtlasIdeTestCaseTable = class
  public const
    cTimeoutMs = 15000;
  private
    FScope: IAtlasModuleScope;
    FTests: TAtlasIdeTests;
    FDebugger: TAtlasIdeTestDebugger;
    FDialog: TAtlasTestsCaseTableDialog;
    FFileName: string;
    FLine: Integer;
    FUri: string;
    /// <summary>Fälle im Puffer beim Öffnen, für Letzter Lauf und Ausführen.</summary>
    FFound: TDUnitXUnit;
    FFixtureIndex: Integer;
    FTestIndex: Integer;
    function Ask(const AArgumentsJson: string; const ADone: TProc<string>): Boolean;
    procedure Show(const ATable: TAtlasTestCaseTable);
    procedure Check(const ARows: TArray<TAtlasTestCaseRow>; AGeneration: Integer);
    procedure Apply(const ARows: TArray<TAtlasTestCaseRow>; AGeneration: Integer);
    procedure Applied(const AJson: string; AGeneration: Integer);
    function LastRun(AFrom: Integer): string;
    procedure RunCase(AFrom: Integer; ADebug: Boolean);
    function Hooks: TAtlasTestsCaseTableDialog.THooks;
  public
    /// <summary>AScope, ATests und ADebugger gehören dem Modul und leben länger.</summary>
    constructor Create(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests; ADebugger: TAtlasIdeTestDebugger);
    /// <summary>Einstellungen tests.testCaseTable und tests.run.</summary>
    class function Wanted: Boolean; static;
    /// <summary>Tabelle der Testmethode an ALine (0-basiert) der Datei AFileName.</summary>
    procedure OpenAt(const AFileName: string; ALine: Integer);
    /// <summary>Tabelle der Testmethode am Cursor des oberen Editors.</summary>
    procedure OpenAtCursor;
  end;

implementation

uses
  System.UITypes,
  System.JSON,
  ToolsAPI,
  Atlas.Text.Lines,
  Atlas.Text.TestResults,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Uris,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Debug,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.UI.Tests.Strings;

{ TAtlasIdeTestCaseTable }

constructor TAtlasIdeTestCaseTable.Create(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests;
  ADebugger: TAtlasIdeTestDebugger);
begin
  inherited Create;
  FScope := AScope;
  FTests := ATests;
  FDebugger := ADebugger;
end;

class function TAtlasIdeTestCaseTable.Wanted: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and TAtlasIdeSettings.Current.TestsCaseTable;
end;

function TAtlasIdeTestCaseTable.Ask(const AArgumentsJson: string; const ADone: TProc<string>): Boolean;
begin
  Result := (TAtlasIdeHost.ActiveSession <> nil) and TAtlasIdeHost.RunServerCommandAsync(FScope,
    TAtlasFeature.Build, TAtlasTestCaseTables.cCommand, AArgumentsJson, cTimeoutMs, ADone);
end;

procedure TAtlasIdeTestCaseTable.OpenAtCursor;
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
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableNone));
    Exit;
  end;
  OpenAt(mView.Buffer.FileName, mView.CursorPos.Line - 1);
end;

procedure TAtlasIdeTestCaseTable.OpenAt(const AFileName: string; ALine: Integer);
var
  mSelf: TAtlasIdeTestCaseTable;
begin
  if not Wanted or (FDialog <> nil) then
  begin
    Exit;
  end;
  FFileName := AFileName;
  FLine := ALine;
  FUri := TLspUris.FromPath(AFileName);
  mSelf := Self;
  if not Ask(TAtlasTestCaseTables.RequestJson(FUri, ALine),
    procedure(AAnswer: string)
    var
      mTable: TAtlasTestCaseTable;
    begin
      if not TAtlasTestCaseTables.Parse(AAnswer, mTable) then
      begin
        mSelf.FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableNone));
        Exit;
      end;
      mSelf.Show(mTable);
    end) then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableNoServer));
  end;
end;

function TAtlasIdeTestCaseTable.Hooks: TAtlasTestsCaseTableDialog.THooks;
var
  mSelf: TAtlasIdeTestCaseTable;
begin
  mSelf := Self;
  Result := Default(TAtlasTestsCaseTableDialog.THooks);
  Result.Check :=
    procedure(const ARows: TArray<TAtlasTestCaseRow>; AGeneration: Integer)
    begin
      mSelf.Check(ARows, AGeneration);
    end;
  Result.Apply :=
    procedure(const ARows: TArray<TAtlasTestCaseRow>; AGeneration: Integer)
    begin
      mSelf.Apply(ARows, AGeneration);
    end;
  Result.Run :=
    procedure(AFrom: Integer)
    begin
      mSelf.RunCase(AFrom, False);
    end;
  Result.LastRun :=
    function(AFrom: Integer): string
    begin
      Result := mSelf.LastRun(AFrom);
    end;
  Result.Version :=
    function: Integer
    begin
      Result := mSelf.FTests.Version;
    end;
end;

procedure TAtlasIdeTestCaseTable.Show(const ATable: TAtlasTestCaseTable);
var
  mResult: Integer;
  mDebugRow: Integer;
begin
  if FDialog <> nil then
  begin
    Exit;
  end;
  FFound := TDUnitXSource.Scan(TTextLines.SplitLines(TAtlasIdeWorkspaceEdit.CurrentText(FFileName)));
  if not FFound.Find(ATable.Fixture, ATable.Method, FFixtureIndex, FTestIndex) then
  begin
    FTestIndex := -1;
  end;
  FDialog := TAtlasTestsCaseTableDialog.CreateDialog(nil, ATable, Hooks);
  try
    mResult := FDialog.ShowModal;
    mDebugRow := FDialog.DebugRow;
  finally
    FreeAndNil(FDialog);
  end;
  if (mResult = mrRetry) and (mDebugRow >= 0) then
  begin
    RunCase(mDebugRow, True);
  end;
end;

procedure TAtlasIdeTestCaseTable.Check(const ARows: TArray<TAtlasTestCaseRow>; AGeneration: Integer);
var
  mSelf: TAtlasIdeTestCaseTable;
  mGeneration: Integer;
begin
  mSelf := Self;
  mGeneration := AGeneration;
  Ask(TAtlasTestCaseTables.ProposalJson(FUri, FLine, ARows),
    procedure(AAnswer: string)
    var
      mProposal: TAtlasTestCaseProposal;
    begin
      if (mSelf.FDialog <> nil) and TAtlasTestCaseTables.ParseProposal(AAnswer, mProposal) then
      begin
        mSelf.FDialog.ShowProblems(mGeneration, mProposal);
      end;
    end);
end;

procedure TAtlasIdeTestCaseTable.Apply(const ARows: TArray<TAtlasTestCaseRow>; AGeneration: Integer);
var
  mSelf: TAtlasIdeTestCaseTable;
  mGeneration: Integer;
begin
  mSelf := Self;
  mGeneration := AGeneration;
  if not Ask(TAtlasTestCaseTables.ProposalJson(FUri, FLine, ARows),
    procedure(AAnswer: string)
    begin
      mSelf.Applied(AAnswer, mGeneration);
    end) and (FDialog <> nil) then
  begin
    FDialog.ShowRefused(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableNoServer));
  end;
end;

procedure TAtlasIdeTestCaseTable.Applied(const AJson: string; AGeneration: Integer);
var
  mProposal: TAtlasTestCaseProposal;
  mEdit: TLspWorkspaceEdit;
  mValue: TJSONValue;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if FDialog = nil then
  begin
    Exit;
  end;
  if not TAtlasTestCaseTables.ParseProposal(AJson, mProposal) then
  begin
    FDialog.ShowRefused(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableNoServer));
    Exit;
  end;
  FDialog.ShowProblems(AGeneration, mProposal);
  if mProposal.EditJson = '' then
  begin
    FDialog.ShowRefused(mProposal.Reason);
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(mProposal.EditJson);
  try
    mEdit := TLspWorkspaceEdit.FromJson(mValue);
  finally
    mValue.Free;
  end;
  mOutcome := TAtlasIdeWorkspaceEdit.Apply(mEdit, TAtlasUnopenedPolicy.OpenInEditor,
    TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableEditAction));
  if mOutcome.Error <> '' then
  begin
    FDialog.ShowRefused(mOutcome.Error);
    Exit;
  end;
  FTests.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsCaseTableWritten, [Length(mProposal.Problems)]));
  FDialog.Applied;
end;

function TAtlasIdeTestCaseTable.LastRun(AFrom: Integer): string;
var
  mTally: TAtlasTestTally;
begin
  Result := '';
  if (FTestIndex < 0) or (AFrom < 0) or (AFrom > High(FFound.Fixtures[FFixtureIndex].Tests[FTestIndex].Cases)) then
  begin
    Exit;
  end;
  mTally := FTests.TallyOf(FFound.UnitName, FFound.Fixtures[FFixtureIndex].Name,
    TAtlasTestRun.Expected(FFound, FFixtureIndex, FTestIndex, AFrom), nil);
  case mTally.Status of
    TAtlasTestStatus.Passed:
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTablePassed);
    TAtlasTestStatus.Failed:
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableFailed);
    TAtlasTestStatus.Unknown, TAtlasTestStatus.Partial:
      Result := '';
  end;
  if (Result <> '') and (mTally.DurationMs > 0) then
  begin
    Result := Result + ' · ' + TTestResults.DurationText(mTally.DurationMs, FormatSettings.DecimalSeparator);
  end;
end;

procedure TAtlasIdeTestCaseTable.RunCase(AFrom: Integer; ADebug: Boolean);
var
  mSelection: TAtlasTestSelection;
begin
  if (FTestIndex < 0) or (AFrom < 0) or (AFrom > High(FFound.Fixtures[FFixtureIndex].Tests[FTestIndex].Cases)) then
  begin
    FTests.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsCaseTableChanged));
    Exit;
  end;
  mSelection := TAtlasTestDebug.Selection(FFound, FFixtureIndex, FTestIndex, AFrom);
  if ADebug then
  begin
    FDebugger.Debug(FFileName, mSelection);
  end
  else
  begin
    FDebugger.Run(FFileName, mSelection);
  end;
end;

end.
