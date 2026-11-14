unit Atlas.UI.Settings.Page.Dialog.Tests;

// Tests der Dialoge der Einstellungsdateien ohne das Modul Prüfregeln; mit Regel-Editor in
// Atlas.UI.Rules.SettingsDialog.Tests (#1755).

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Regeldialog der Einstellungen.</summary>
  [TestFixture]
  TAtlasSettingsPageDialogTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure DialogShowsOriginAndResetsToGlobal;
    /// <summary>Ohne das Modul Prüfregeln (#1755): "rules" als JSON-Text, keine Knoten je Gruppe, kein Regel-Editor.
    /// </summary>
    [Test]
    procedure DialogWithoutRulesModuleShowsJson;
    [Test]
    procedure DialogValidatesBeforeSaving;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Settings.ProjectDialog,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Validation,
  Vcl.Controls,
  Vcl.StdCtrls,
  Atlas.UI.Settings.Page.TestSupport;

procedure TAtlasSettingsPageDialogTests.WarmUp;
begin
  WarmUpSettingsPage;
end;
procedure TAtlasSettingsPageDialogTests.DialogShowsOriginAndResetsToGlobal;
var
  mModel: TAtlasSettingsModel;
  mDialog: TAtlasProjectSettingsDialog;
begin
  mModel := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{"language": "en"}',
    '{"language": "de", "encoding": "windows-1252"}', False);
  try
    mDialog := TAtlasProjectSettingsDialog.CreateDialog(nil, mModel, 'C:\P\atlas.json');
    try
      Assert.IsTrue(mDialog.SelectPage('Allgemein'));
      Assert.IsTrue(Pos('Projekt', mDialog.StateText('language')) > 0);
      Assert.IsTrue(Pos('windows-1252', mDialog.StateText('encoding')) > 0, 'global geerbt');
      mModel.Reset(mModel.IndexOf('language'));
      Assert.AreEqual('{}', mModel.ResultText);
    finally
      mDialog.Free;
    end;
  finally
    mModel.Free;
  end;
end;
/// <summary>Ein TMemo unter AParent, dessen Text ATerm enthält.</summary>
function HasMemoWith(AParent: TWinControl; const ATerm: string): Boolean;
var
  mIndex: Integer;
  mControl: TControl;
begin
  Result := False;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    mControl := AParent.Controls[mIndex];
    if (mControl is TMemo) and (Pos(ATerm, TMemo(mControl).Lines.Text) > 0) then
    begin
      Exit(True);
    end;
    if (mControl is TWinControl) and HasMemoWith(TWinControl(mControl), ATerm) then
    begin
      Exit(True);
    end;
  end;
end;
procedure TAtlasSettingsPageDialogTests.DialogWithoutRulesModuleShowsJson;
var
  mModel: TAtlasSettingsModel;
  mDialog: TAtlasProjectSettingsDialog;
begin
  mModel := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson),
    '{"rules": {"no-with": "error"}}', '', False);
  try
    mDialog := TAtlasProjectSettingsDialog.CreateDialog(nil, mModel, 'C:\P\atlas.json');
    try
      mDialog.HandleNeeded;
      Assert.IsNull(mDialog.GroupNode('threads'), 'ohne Modul keine Knoten je Gruppe');
      Assert.IsTrue(mDialog.SelectPage(mModel.Fields[mModel.IndexOf('rules')].Page));
      Assert.IsTrue(HasMemoWith(mDialog, 'no-with'), '"rules" als JSON-Text');
      Assert.IsFalse(mDialog.SelectRule('no-with'));
    finally
      mDialog.Free;
    end;
  finally
    mModel.Free;
  end;
end;
procedure TAtlasSettingsPageDialogTests.DialogValidatesBeforeSaving;
var
  mModel: TAtlasSettingsModel;
  mDialog: TAtlasProjectSettingsDialog;
  mChecked: Integer;
begin
  mModel := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', True);
  try
    mDialog := TAtlasProjectSettingsDialog.CreateDialog(nil, mModel, 'C:\Users\X\settings.json');
    try
      mChecked := 0;
      mDialog.OnValidate :=
        function(const AText: string; out AChecked: Boolean): TArray<TAtlasSettingIssue>
        begin
          Inc(mChecked);
          AChecked := True;
          Result := nil;
        end;
      // Unverändert: nichts zu prüfen.
      Assert.IsTrue(mDialog.Validate);
      Assert.AreEqual(0, mChecked);
      mModel.SetValue(mModel.IndexOf('memoryBudgetMb'), '256');
      Assert.IsTrue(mDialog.Validate);
      Assert.AreEqual(1, mChecked);
      mDialog.ServerChecks := False;
      Assert.IsTrue(mDialog.HintLabel.Visible, 'Hinweis: nur Syntax');
      // Eine Zeile Hinweis: Nach dem Anpassen an die Breite bleibt kein hoher leerer Streifen.
      mDialog.HandleNeeded;
      mDialog.Width := mDialog.Width + 10;
      Assert.IsTrue(mDialog.HintLabel.Height < 60, 'Hinweis ohne leeren Streifen');
    finally
      mDialog.Free;
    end;
  finally
    mModel.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageDialogTests);

end.
