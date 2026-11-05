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
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
begin
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{"language": "en"}',
    '{"language": "de", "encoding": "windows-1252"}', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\P\atlas.json');
    try
      Assert.IsTrue(Dialog.SelectPage('Allgemein'));
      Assert.IsTrue(Pos('Projekt', Dialog.StateText('language')) > 0);
      Assert.IsTrue(Pos('windows-1252', Dialog.StateText('encoding')) > 0, 'global geerbt');
      Model.Reset(Model.IndexOf('language'));
      Assert.AreEqual('{}', Model.ResultText);
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
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
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
begin
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson),
    '{"rules": {"no-with": "error"}}', '', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\P\atlas.json');
    try
      Dialog.HandleNeeded;
      Assert.IsNull(Dialog.GroupNode('threads'), 'ohne Modul keine Knoten je Gruppe');
      Assert.IsTrue(Dialog.SelectPage(Model.Fields[Model.IndexOf('rules')].Page));
      Assert.IsTrue(HasMemoWith(Dialog, 'no-with'), '"rules" als JSON-Text');
      Assert.IsFalse(Dialog.SelectRule('no-with'));
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
  end;
end;
procedure TAtlasSettingsPageDialogTests.DialogValidatesBeforeSaving;
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Checked: Integer;
begin
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', True);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Users\X\settings.json');
    try
      Checked := 0;
      Dialog.OnValidate :=
        function(const AText: string; out AChecked: Boolean): TArray<TAtlasSettingIssue>
        begin
          Inc(Checked);
          AChecked := True;
          Result := nil;
        end;
      // Unverändert: nichts zu prüfen.
      Assert.IsTrue(Dialog.Validate);
      Assert.AreEqual(0, Checked);
      Model.SetValue(Model.IndexOf('memoryBudgetMb'), '256');
      Assert.IsTrue(Dialog.Validate);
      Assert.AreEqual(1, Checked);
      Dialog.ServerChecks := False;
      Assert.IsTrue(Dialog.HintLabel.Visible, 'Hinweis: nur Syntax');
      // Eine Zeile Hinweis: Nach dem Anpassen an die Breite bleibt kein hoher leerer Streifen.
      Dialog.HandleNeeded;
      Dialog.Width := Dialog.Width + 10;
      Assert.IsTrue(Dialog.HintLabel.Height < 60, 'Hinweis ohne leeren Streifen');
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageDialogTests);

end.
