unit Atlas.UI.Foundation.DialogSmoke.Tests;

// Rauchtest der Dialoge von Atlas.IDE.Base: Jeder Dialog entsteht mit kleinster Eingabe, bekommt Fenster für sich
// und alle Steuerelemente, durchläuft DoShow wie beim Zeigen und wird freigegeben (TAtlasDialogSmoke). Dialoge
// mit eigenen Tests stehen dort; Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog gebaut wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBaseDialogSmokeTests = class
  public
    [Test]
    procedure ActionChoices;
    [Test]
    procedure ChangeSignature;
    [Test]
    procedure GenerateChoice;
    [Test]
    procedure ExtractMembers;
    [Test]
    procedure SettingsProfile;
    [Test]
    procedure LearnedSuggestions;
  end;

implementation

uses
  Atlas.Core.Editor.ChangeSignature,
  Atlas.Core.Editor.ClassExtraction,
  Atlas.UI.Editor.ActionChoices,
  Atlas.UI.Editor.ChangeSignature,
  Atlas.UI.Editor.ExtractMembers,
  Atlas.UI.Editor.LearnedSuggestions,
  Atlas.UI.Generate.Choice,
  Atlas.UI.Settings.Transfer,
  Atlas.Tests.DialogSmoke;

{ TAtlasBaseDialogSmokeTests }

procedure TAtlasBaseDialogSmokeTests.ActionChoices;
var
  mDialog: TAtlasActionChoicesDialog;
begin
  mDialog := TAtlasActionChoicesDialog.CreateChoices(nil, 'Aktion', 'Hinweis', TArray<string>.Create('Teil A',
    'Teil B'));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    mDialog.Fill;
    Assert.AreEqual(2, mDialog.List.Items.Count);
    Assert.AreEqual(2, Integer(Length(mDialog.Chosen)));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBaseDialogSmokeTests.ChangeSignature;
var
  mModel: TAtlasSignatureModel;
  mDialog: TAtlasChangeSignatureDialog;
begin
  mModel := TAtlasSignatureModel.Create(nil);
  try
    mDialog := TAtlasChangeSignatureDialog.CreateDialog(nil, mModel);
    try
      Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    finally
      mDialog.Free;
    end;
  finally
    mModel.Free;
  end;
end;

procedure TAtlasBaseDialogSmokeTests.GenerateChoice;
var
  mDialog: TAtlasChoiceDialog;
begin
  mDialog := TAtlasChoiceDialog.CreateDialog(nil, 'Vorlage', 'Vorlage wählen', TArray<string>.Create('Klasse',
    'Record'));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBaseDialogSmokeTests.ExtractMembers;
var
  mModel: TAtlasClassExtractionModel;
  mDialog: TAtlasExtractMembersDialog;
begin
  mModel := TAtlasClassExtractionModel.Create(nil);
  try
    mDialog := TAtlasExtractMembersDialog.CreateDialog(nil, mModel, 'Interface herausziehen');
    try
      Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    finally
      mDialog.Free;
    end;
  finally
    mModel.Free;
  end;
end;

procedure TAtlasBaseDialogSmokeTests.SettingsProfile;
var
  mDialog: TAtlasProfileDialog;
begin
  mDialog := TAtlasProfileDialog.CreateDialog(nil, TArray<string>.Create('Standard'),
    TArray<string>.Create('Alle Regeln'));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(1, mDialog.List.Items.Count, 'Profile nach DoShow');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasBaseDialogSmokeTests.LearnedSuggestions;
var
  mItem: TAtlasLearnedListItem;
  mDialog: TAtlasLearnedListWindow;
begin
  mItem := Default(TAtlasLearnedListItem);
  mItem.Pattern.Trigger := 'try';
  mItem.Pattern.Text := 'finally';
  mItem.On_ := True;
  mDialog := TAtlasLearnedListWindow.CreateList(nil, TArray<TAtlasLearnedListItem>.Create(mItem),
    Default(TAtlasLearnedListEvents));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBaseDialogSmokeTests);

end.
