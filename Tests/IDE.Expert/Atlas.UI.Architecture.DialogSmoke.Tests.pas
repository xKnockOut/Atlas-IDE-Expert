unit Atlas.UI.Architecture.DialogSmoke.Tests;

// Rauchtest der Dialoge von Atlas.IDE.Analysis: Jeder Dialog entsteht mit kleinster Eingabe, bekommt Fenster für
// sich und alle Steuerelemente, durchläuft DoShow wie beim Zeigen und wird freigegeben (TAtlasDialogSmoke).
// Dialoge mit eigenen Tests stehen dort; Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog gebaut wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasAnalysisDialogSmokeTests = class
  public
    [Test]
    procedure RoleUnit;
  end;

implementation

uses
  Atlas.Core.Architecture.RoleUnit,
  Atlas.UI.Architecture.RoleUnitDialog,
  Atlas.Tests.DialogSmoke;

{ TAtlasAnalysisDialogSmokeTests }

procedure TAtlasAnalysisDialogSmokeTests.RoleUnit;
var
  mInput: TAtlasRoleUnitInput;
  mDialog: TAtlasRoleUnitDialog;
begin
  mInput := Default(TAtlasRoleUnitInput);
  mInput.Prefix := 'Atlas';
  mInput.Feature := 'Demo';
  mInput.Role := TAtlasArchitectureRole.Adapters;
  mInput.Thing := 'Datei';
  mDialog := TAtlasRoleUnitDialog.CreateDialog(nil, TArray<string>.Create('Atlas'));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    mDialog.Input := mInput;
    Assert.AreEqual('Demo', mDialog.Input.Feature);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAnalysisDialogSmokeTests);

end.
