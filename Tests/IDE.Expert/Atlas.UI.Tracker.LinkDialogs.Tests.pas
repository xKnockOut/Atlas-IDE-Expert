unit Atlas.UI.Tracker.LinkDialogs.Tests;

// Dialoge zu Abhängigkeiten und Unteraufgaben (#1279): „Anlegen“ erst mit
// Titel, „Verknüpfen“ erst mit gültiger fremder Kennung (auch als Adresse),
// Art der Verknüpfung und Text der Rückfrage beim Beginnen.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasLinkDialogsTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SubtaskNeedsTitle;
    [Test]
    procedure LinkNeedsOtherKey;
    [Test]
    procedure LinkKindAndGitHubKeys;
    [Test]
    procedure BlockedPromptText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Tracker.LinkDialogs;

function Blocker(const AKey: string): TAtlasTrackerLink;
begin
  Result := Default(TAtlasTrackerLink);
  Result.Key := AKey;
  Result.Kind := TAtlasTrackerLinkKind.DependsOn;
  Result.StateKnown := True;
end;

{ TAtlasLinkDialogsTests }

procedure TAtlasLinkDialogsTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasLinkDialogsTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasLinkDialogsTests.SubtaskNeedsTitle;
var
  mDialog: TAtlasSubtaskDialog;
begin
  mDialog := TAtlasSubtaskDialog.CreateDialog(nil, 'ATL-130', 'ATL');
  try
    Assert.AreEqual('Unteraufgabe zu ATL-130 anlegen', mDialog.Caption);
    Assert.AreEqual('Projekt: ATL', mDialog.ProjectLabel.Caption);
    Assert.IsFalse(mDialog.OkButton.Enabled, 'ohne Titel');
    mDialog.TitleEdit.Text := '   ';
    Assert.IsFalse(mDialog.OkButton.Enabled, 'nur Leerzeichen');
    mDialog.TitleEdit.Text := '  Baum zeigen ';
    Assert.IsTrue(mDialog.OkButton.Enabled);
    Assert.AreEqual('Baum zeigen', mDialog.IssueTitle);
    mDialog.DescriptionMemo.Text := 'Erste Zeile'#13#10'- Punkt'#13#10;
    Assert.AreEqual('Erste Zeile'#13#10'- Punkt', mDialog.Description, 'ohne Leerzeilen am Ende');
    Assert.IsTrue(mDialog.OkButton.Left + mDialog.OkButton.Width <= mDialog.CancelButton.Left,
      '„Anlegen“ links von „Abbrechen“');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasLinkDialogsTests.LinkNeedsOtherKey;
var
  mDialog: TAtlasIssueLinkDialog;
begin
  mDialog := TAtlasIssueLinkDialog.CreateDialog(nil, 'ATL-130', TAtlasTrackerTarget.YouTrack);
  try
    Assert.AreEqual('ATL-130 verknüpfen', mDialog.Caption);
    Assert.IsFalse(mDialog.OkButton.Enabled);
    mDialog.OtherEdit.Text := 'kein Schlüssel';
    Assert.IsFalse(mDialog.OkButton.Enabled);
    mDialog.OtherEdit.Text := 'atl-130';
    Assert.IsFalse(mDialog.OkButton.Enabled, 'nicht mit sich selbst');
    Assert.AreEqual('', mDialog.OtherKey);
    mDialog.OtherEdit.Text := ' ATL-129 ';
    Assert.IsTrue(mDialog.OkButton.Enabled);
    Assert.AreEqual('ATL-129', mDialog.OtherKey);
    mDialog.OtherEdit.Text := 'https://beispiel.youtrack.cloud/issue/ATL-128/';
    Assert.AreEqual('ATL-128', mDialog.OtherKey, 'Adresse');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasLinkDialogsTests.LinkKindAndGitHubKeys;
var
  mDialog: TAtlasIssueLinkDialog;
begin
  mDialog := TAtlasIssueLinkDialog.CreateDialog(nil, '#753', TAtlasTrackerTarget.GitHub);
  try
    Assert.AreEqual('#753 hängt ab von …', mDialog.DependsOnButton.Caption);
    Assert.AreEqual('#753 blockiert …', mDialog.BlocksButton.Caption);
    Assert.IsTrue(mDialog.Kind = TAtlasTrackerLinkKind.DependsOn, 'Vorgabe');
    mDialog.BlocksButton.Checked := True;
    Assert.IsTrue(mDialog.Kind = TAtlasTrackerLinkKind.Blocks);
    mDialog.OtherEdit.Text := '760';
    Assert.AreEqual('#760', mDialog.OtherKey);
    mDialog.OtherEdit.Text := '#753';
    Assert.AreEqual('', mDialog.OtherKey);
    mDialog.OtherEdit.Text := 'https://github.com/beispiel/atlas/issues/761';
    Assert.AreEqual('#761', mDialog.OtherKey);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasLinkDialogsTests.BlockedPromptText;
begin
  Assert.AreEqual('', TAtlasBlockedPrompt.Text(nil));
  Assert.AreEqual('ATL-129 blockiert dieses Issue und ist noch offen.',
    TAtlasBlockedPrompt.Text(TArray<TAtlasTrackerLink>.Create(Blocker('ATL-129'))));
  Assert.AreEqual('ATL-129 und 2 weitere blockieren dieses Issue und sind noch offen.',
    TAtlasBlockedPrompt.Text(TArray<TAtlasTrackerLink>.Create(Blocker('ATL-129'), Blocker('ATL-7'),
    Blocker('ATL-8'))));
  Assert.IsTrue(TAtlasBlockedPrompt.Ask(nil) = TAtlasBlockedChoice.Cancel, 'ohne Blocker keine Rückfrage');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkDialogsTests);

end.
