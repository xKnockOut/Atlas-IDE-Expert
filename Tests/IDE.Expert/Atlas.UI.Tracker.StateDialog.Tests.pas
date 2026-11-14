unit Atlas.UI.Tracker.StateDialog.Tests;

// Tests des Dialogs „Mit Kommentar …“ am Statusfeld (#2124): Auswahl mit
// „Zustand behalten“ vorn, Vorwahl, gewählter Eintrag und Kommentar ohne
// Leerraum außen; größer ziehen gibt dem Kommentar die Höhe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerStateDialogTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeepStateComesFirst;
    [Test]
    procedure EntryAndComment;
    [Test]
    procedure GrowsWithWindow;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.StateDialog;

procedure TAtlasTrackerStateDialogTests.Setup;
begin
  FSaved := Ord(TAtlasStrings.Language);
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasTrackerStateDialogTests.TearDown;
begin
  TAtlasStrings.Language := TAtlasLanguage(FSaved);
end;

procedure TAtlasTrackerStateDialogTests.KeepStateComesFirst;
var
  mDialog: TAtlasTrackerStateDialog;
begin
  mDialog := TAtlasTrackerStateDialog.CreateDialog(nil, 'ATL-2052',
    TArray<string>.Create('Zur Prüfung geben', 'Pausieren'), -1);
  try
    Assert.AreEqual('ATL-2052: Zustand ändern', mDialog.Caption);
    Assert.AreEqual(0, mDialog.ChoiceBox.Choice, 'Zustand behalten vorgewählt');
    Assert.AreEqual(-1, mDialog.Entry);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerStateDialogTests.EntryAndComment;
var
  mDialog: TAtlasTrackerStateDialog;
begin
  mDialog := TAtlasTrackerStateDialog.CreateDialog(nil, 'ATL-2052',
    TArray<string>.Create('Zur Prüfung geben', 'Pausieren'), 1);
  try
    Assert.AreEqual(1, mDialog.Entry, 'Vorwahl');
    mDialog.ChoiceBox.Choice := 1;
    Assert.AreEqual(0, mDialog.Entry);
    mDialog.Editor.SetText('  Bitte prüfen'#10);
    Assert.AreEqual('Bitte prüfen', mDialog.Comment);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerStateDialogTests.GrowsWithWindow;
const
  cMore = 120;
var
  mDialog: TAtlasTrackerStateDialog;
  mEditorHeight, mSendTop: Integer;
begin
  mDialog := TAtlasTrackerStateDialog.CreateDialog(nil, 'ATL-1', nil, -1);
  try
    Assert.AreEqual<TFormBorderStyle>(bsSizeable, mDialog.BorderStyle);
    mEditorHeight := mDialog.Editor.Height;
    mSendTop := mDialog.SendButton.Parent.Top;
    mDialog.Height := mDialog.Height + mDialog.ScaleValue(cMore);
    Assert.AreEqual(mEditorHeight + mDialog.ScaleValue(cMore), mDialog.Editor.Height, 'Kommentar höher');
    Assert.AreEqual(mSendTop + mDialog.ScaleValue(cMore), mDialog.SendButton.Parent.Top, 'Knöpfe bleiben unten');
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerStateDialogTests);

end.
