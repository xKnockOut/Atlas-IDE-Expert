unit Atlas.Common.Lsp.LeakSetup.Tests;

// Befehl atlas.server.leakSetup (#1880): Stand als JSON, Plan mit
// WorkspaceEdit und Symbolen, Fehler ohne URI, ohne Projekt und bei
// unbekanntem Speichermanager.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Leaks.Setup,
  Atlas.Common.Lsp.LeakSetup;

type
  [TestFixture]
  TLspLeakSetupTests = class
  private
    FSetup: TLspLeakSetup;
    FInput: TLeakSetupInput;
    FLoaded: Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StateAsJson;
    [Test]
    procedure PlanAsWorkspaceEdit;
    [Test]
    procedure MissingUriInvalidParams;
    [Test]
    procedure NoProjectInvalidParams;
    [Test]
    procedure UnknownManagerInvalidParams;
    [Test]
    procedure ManagerNames;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris;

const
  cBreak = #13#10;
  cMain = 'C:\P\App.dpr';
  cText = 'program App;' + cBreak + 'uses' + cBreak + '  SysUtils;' + cBreak + 'begin' + cBreak + 'end.';

procedure TLspLeakSetupTests.Setup;
begin
  FLoaded := True;
  FInput := Default(TLeakSetupInput);
  FInput.ProjectFile := 'C:\P\App.dproj';
  FInput.MainSource := cMain;
  FInput.MainText := cText;
  FInput.Platform := 'Win64';
  FSetup := TLspLeakSetup.Create(
    function(const AUri: string; out AInput: TLeakSetupInput; out AReason: string): Boolean
    begin
      AInput := FInput;
      AReason := 'kein Projekt';
      Result := FLoaded;
    end, nil);
end;

procedure TLspLeakSetupTests.TearDown;
begin
  FreeAndNil(FSetup);
  FInput := Default(TLeakSetupInput);
end;

function Arguments(const AWish: string): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(TDocumentUris.FromPath(cMain));
  if AWish <> '' then
  begin
    Result.AddElement(TJSONObject.ParseJSONValue(AWish));
  end;
end;

procedure TLspLeakSetupTests.StateAsJson;
var
  mArguments: TJSONArray;
  mResult: TJSONValue;
  mObject: TJSONObject;
begin
  mArguments := Arguments('');
  try
    mResult := FSetup.Execute(mArguments);
    try
      mObject := mResult as TJSONObject;
      Assert.AreEqual(cMain, mObject.GetValue('mainSource').Value);
      Assert.AreEqual('Win64', mObject.GetValue('platform').Value);
      Assert.IsTrue(mObject.GetValue('fastmm4') is TJSONNull);
      Assert.AreEqual('none', TJSONObject(mObject.GetValue('uses')).GetValue('manager').Value);
      Assert.AreEqual('0', TJSONObject(mObject.GetValue('report')).GetValue('line').Value);
      Assert.AreEqual('FastMM_FullDebugMode64.dll', TJSONObject(mObject.GetValue('dll')).GetValue('name').Value);
      Assert.IsTrue(mObject.GetValue('hasMainBlock') is TJSONTrue);
      Assert.IsNull(mObject.GetValue('plan'));
    finally
      mResult.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

procedure TLspLeakSetupTests.PlanAsWorkspaceEdit;
var
  mArguments: TJSONArray;
  mResult: TJSONValue;
  mPlan, mChanges: TJSONObject;
  mEdits: TJSONArray;
begin
  mArguments := Arguments('{"manager": "fastmm5", "fileReport": true}');
  try
    mResult := FSetup.Execute(mArguments);
    try
      mPlan := TJSONObject((mResult as TJSONObject).GetValue('plan'));
      Assert.AreEqual('fastmm5', mPlan.GetValue('manager').Value);
      Assert.IsTrue(mPlan.GetValue('empty') is TJSONFalse);
      Assert.AreEqual('FastMM_FullDebugMode', TJSONArray(mPlan.GetValue('defines')).Items[0].Value);
      mChanges := TJSONObject(TJSONObject(mPlan.GetValue('edit')).GetValue('changes'));
      mEdits := TJSONArray(mChanges.GetValue(TDocumentUris.FromPath(cMain)));
      // Hauptblock (Zeile 4), dann uses (Zeile 2): von hinten nach vorn.
      Assert.AreEqual(2, Integer(mEdits.Count));
      Assert.AreEqual('4', TJSONObject(TJSONObject(TJSONObject(mEdits.Items[0]).GetValue('range')).GetValue('start'))
        .GetValue('line').Value);
      Assert.IsTrue(Pos('FastMM5,', TJSONObject(mEdits.Items[1]).GetValue('newText').Value) > 0);
    finally
      mResult.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

procedure TLspLeakSetupTests.MissingUriInvalidParams;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    Assert.WillRaise(
      procedure
      begin
        FSetup.Execute(mArguments).Free;
      end, EJsonRpcError);
  finally
    mArguments.Free;
  end;
end;

procedure TLspLeakSetupTests.NoProjectInvalidParams;
var
  mArguments: TJSONArray;
begin
  FLoaded := False;
  mArguments := Arguments('');
  try
    Assert.WillRaise(
      procedure
      begin
        FSetup.Execute(mArguments).Free;
      end, EJsonRpcError);
  finally
    mArguments.Free;
  end;
end;

procedure TLspLeakSetupTests.UnknownManagerInvalidParams;
var
  mArguments: TJSONArray;
begin
  mArguments := Arguments('{"manager": "madexcept"}');
  try
    Assert.WillRaise(
      procedure
      begin
        FSetup.Execute(mArguments).Free;
      end, EJsonRpcError);
  finally
    mArguments.Free;
  end;
end;

procedure TLspLeakSetupTests.ManagerNames;
var
  mManager: TLeakManager;
begin
  Assert.IsTrue(TLspLeakSetup.ManagerOf('FastMM4', mManager));
  Assert.IsTrue(mManager = TLeakManager.FastMM4);
  Assert.IsTrue(TLspLeakSetup.ManagerOf('none', mManager));
  Assert.IsTrue(mManager = TLeakManager.None);
  Assert.IsFalse(TLspLeakSetup.ManagerOf('', mManager));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspLeakSetupTests);

end.
