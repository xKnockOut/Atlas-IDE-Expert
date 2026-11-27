unit Atlas.UI.Rules.DialogSmoke.Tests;

// Rauchtest der Dialoge von Atlas.IDE.Rules: Jeder Dialog entsteht mit kleinster Eingabe, bekommt Fenster für
// sich und alle Steuerelemente, durchläuft DoShow wie beim Zeigen und wird freigegeben (TAtlasDialogSmoke).
// Dialoge mit eigenen Tests stehen dort; Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog gebaut wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
  TAtlasRulesDialogSmokeTests = class
  public
    [Test]
    procedure BulkFix;
  end;

implementation

uses
  Atlas.Core.Problems.BulkFix,
  Atlas.UI.Rules.BulkFix, // Unit heißt seit dem Modul Rules so (F2613)
  Atlas.Tests.DialogSmoke;

{ TAtlasRulesDialogSmokeTests }

procedure TAtlasRulesDialogSmokeTests.BulkFix;
var
  mPreview: TAtlasBulkFixPreview;
  mDialog: TAtlasBulkFixDialog;
begin
  mPreview := TAtlasBulkFixPreview.Create('unused-uses', nil);
  try
    mDialog := TAtlasBulkFixDialog.CreateDialog(nil, mPreview);
    try
      Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
      Assert.AreEqual(0, mDialog.FileList.Items.Count);
    finally
      mDialog.Free;
    end;
  finally
    mPreview.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRulesDialogSmokeTests);

end.
