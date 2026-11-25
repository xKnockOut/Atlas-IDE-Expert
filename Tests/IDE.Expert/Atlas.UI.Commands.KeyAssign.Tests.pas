unit Atlas.UI.Commands.KeyAssign.Tests;

// Dialog „Tastenkürzel für …“ (#2938): Der Tastendruck im Feld wird zur Taste
// (Strg oder Alt nötig, F-Tasten auch allein), der Hinweis nennt freie oder
// belegte Tasten, „Entfernen“ setzt die Taste auf keine.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasKeyAssignDialogTests = class
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BuildsWithAllControls;
    [Test]
    procedure PressShowsKeyAndHolders;
    [Test]
    procedure RemoveClearsKey;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Atlas.Plugin.Localization.Strings,
  Atlas.Tests.DialogSmoke,
  Atlas.UI.Commands.KeyAssign;

const
  cCtrlD = $4044;
  cCtrlAltM = $C04D;

var
  Language: TAtlasLanguage;

/// <summary>Strg+Alt+M gehört „Gliederung (IDE)“, alles andere ist frei.</summary>
function Holders: TFunc<Word, string>;
begin
  Result :=
    function(AKey: Word): string
    begin
      Result := '';
      if AKey = cCtrlAltM then
      begin
        Result := 'Gliederung (IDE)';
      end;
    end;
end;

{ TAtlasKeyAssignDialogTests }

procedure TAtlasKeyAssignDialogTests.Setup;
begin
  Language := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasKeyAssignDialogTests.TearDown;
begin
  TAtlasStrings.Language := Language;
end;

procedure TAtlasKeyAssignDialogTests.BuildsWithAllControls;
var
  mDialog: TAtlasKeyAssignDialog;
begin
  mDialog := TAtlasKeyAssignDialog.CreateFor(nil, 'Methode suchen', 0, nil);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual('Tastenkürzel für „Methode suchen“', mDialog.Caption);
    Assert.AreEqual('(keine)', mDialog.KeyEdit.Text);
    Assert.IsFalse(mDialog.RemoveButton.Enabled, 'ohne Taste nichts zu entfernen');
    Assert.IsTrue(mDialog.OkButton.Default);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasKeyAssignDialogTests.PressShowsKeyAndHolders;
var
  mDialog: TAtlasKeyAssignDialog;
begin
  mDialog := TAtlasKeyAssignDialog.CreateFor(nil, 'Methode suchen', 0, Holders());
  try
    Assert.IsFalse(mDialog.Press(Ord('D'), []), 'Buchstabe allein');
    Assert.AreEqual(0, Integer(mDialog.Key));
    Assert.IsTrue(mDialog.Press(Ord('D'), [ssCtrl]));
    Assert.AreEqual(cCtrlD, Integer(mDialog.Key));
    Assert.AreEqual('Die Taste ist frei.', mDialog.Note.Caption);
    Assert.IsTrue(mDialog.RemoveButton.Enabled);
    Assert.IsTrue(mDialog.Press(Ord('M'), [ssCtrl, ssAlt]));
    Assert.AreEqual(cCtrlAltM, Integer(mDialog.Key));
    Assert.Contains(mDialog.Note.Caption, 'Gliederung (IDE)');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasKeyAssignDialogTests.RemoveClearsKey;
var
  mDialog: TAtlasKeyAssignDialog;
begin
  mDialog := TAtlasKeyAssignDialog.CreateFor(nil, 'Methode suchen', cCtrlD, Holders());
  try
    Assert.AreEqual(cCtrlD, Integer(mDialog.Key));
    mDialog.RemoveButton.Click;
    Assert.AreEqual(0, Integer(mDialog.Key));
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasKeyAssignDialogTests);

end.
