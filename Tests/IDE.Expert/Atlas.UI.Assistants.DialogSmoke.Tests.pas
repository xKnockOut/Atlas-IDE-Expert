unit Atlas.UI.Assistants.DialogSmoke.Tests;

// Rauchtest der Dialoge von Atlas.IDE.Assistants: Jeder Dialog entsteht mit kleinster Eingabe, bekommt Fenster für
// sich und alle Steuerelemente, durchläuft DoShow wie beim Zeigen und wird freigegeben (TAtlasDialogSmoke).
// Dialoge mit eigenen Tests stehen dort; Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog gebaut wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAssistantsDialogSmokeTests = class
  public
    [Test]
    procedure LinkDiffView;
  end;

implementation

uses
  Atlas.UI.Assistants.LinkDiffView,
  Atlas.Tests.DialogSmoke;

{ TAtlasAssistantsDialogSmokeTests }

procedure TAtlasAssistantsDialogSmokeTests.LinkDiffView;
var
  mView: TAtlasLinkDiffView;
begin
  mView := TAtlasLinkDiffView.CreateView(nil, 1, 'Demo.pas', TArray<string>.Create('-alt', '+neu'));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mView) > 1);
    Assert.AreEqual(2, mView.Lines.Lines.Count);
    Assert.IsFalse(mView.Decided);
  finally
    mView.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAssistantsDialogSmokeTests);

end.
