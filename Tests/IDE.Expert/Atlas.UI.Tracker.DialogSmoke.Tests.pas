unit Atlas.UI.Tracker.DialogSmoke.Tests;

// Rauchtest der Dialoge von Atlas.IDE.Tracker: Jeder Dialog entsteht mit kleinster Eingabe, bekommt Fenster für
// sich und alle Steuerelemente, durchläuft DoShow wie beim Zeigen und wird freigegeben (TAtlasDialogSmoke).
// Dialoge mit eigenen Tests stehen dort; Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog gebaut wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerDialogSmokeTests = class
  public
    [Test]
    procedure PathSuggestions;
    [Test]
    procedure OpenTimes;
    [Test]
    procedure IssueImage;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.Core.Tracker.PathSuggestions,
  Atlas.Core.Tracker.TimeLog,
  Atlas.UI.Tracker.IssueBoxes,
  Atlas.UI.Tracker.SuggestDialog,
  Atlas.UI.Tracker.TimeList,
  Atlas.Tests.DialogSmoke;

{ TAtlasTrackerDialogSmokeTests }

procedure TAtlasTrackerDialogSmokeTests.PathSuggestions;
var
  mDialog: TAtlasTrackerSuggestDialog;
begin
  mDialog := TAtlasTrackerSuggestDialog.CreateDialog(nil, 'Projekt');
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    mDialog.Fill(TArray<TAtlasTrackerPathSuggestion>.Create(TAtlasTrackerPathSuggestion.Create('C:\Projekt', 'git',
      TAtlasTrackerPathReason.Project, 'Projekt.groupproj')));
    Assert.AreEqual(1, mDialog.List.Items.Count);
    Assert.IsTrue(mDialog.ApplyButton.Enabled);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerDialogSmokeTests.OpenTimes;
var
  mItem: TAtlasTimeOpen;
  mDialog: TAtlasTrackerTimeListDialog;
begin
  mItem := Default(TAtlasTimeOpen);
  mItem.Issue := TAtlasTimeIssue.Create('github', 'https://github.com/a/b', '', '#12');
  mItem.Seconds := 1800;
  mDialog := TAtlasTrackerTimeListDialog.CreateDialog(nil, TArray<TAtlasTimeOpen>.Create(mItem));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(1, mDialog.List.Items.Count, 'Zeiten nach DoShow');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerDialogSmokeTests.IssueImage;
var
  mImage: TBitmap;
  mDialog: TAtlasIssueImageWindow;
begin
  mImage := TBitmap.Create;
  try
    mImage.SetSize(40, 30);
    mDialog := TAtlasIssueImageWindow.CreateFor(nil, mImage, 'Bildschirmfoto');
    try
      Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    finally
      mDialog.Free;
    end;
  finally
    mImage.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerDialogSmokeTests);

end.
