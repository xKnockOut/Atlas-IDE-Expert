unit Atlas.UI.Settings.Page.Dialog.Tests;

// Tests der Einstellungsseite: Regeldialog.

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
    [Test]
    procedure DialogRuleTableChangesOnlyThatRule;
    /// <summary>Die Dialoge der Einstellungsdateien zeigen die Prüfregeln mit einem Knoten je Gruppe (#909).
    /// </summary>
    [Test]
    procedure DialogRulesByGroupNodes;
    /// <summary>#1296: Wächst der Regel-Editor mit der markierten Regel, rücken die Felder darunter nach statt
    /// überdeckt zu werden.</summary>
    [Test]
    procedure DialogRuleEditorPushesFieldsDown;
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
  System.JSON,
  System.Generics.Collections,
  System.Math,
  Vcl.Controls,
  Atlas.UI.Settings.Rules,
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
procedure TAtlasSettingsPageDialogTests.DialogRuleTableChangesOnlyThatRule;
const
  Text = '{' + #13#10 + '  "rules": {' + #13#10 + '    "no-with": "error" // streng' + #13#10 + '  }' + #13#10 + '}';
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Catalog: TJSONValue;
begin
  Catalog := TJSONObject.ParseJSONValue('{"rules": [{"id": "no-with", "name": "Kein with", "category": "code-smell",' +
    ' "severity": "warning"}, {"id": "empty-except", "name": "Leeres except", "category": "bug",' +
    ' "severity": "error"}]}');
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), Text, '', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\P\atlas.json');
    try
      Dialog.Catalog := Catalog;
      // Mit Fenster: Erst dann hat der Behälter seine Breite; ohne war die Prüfung der Breite wertlos.
      Dialog.HandleNeeded;
      Assert.IsTrue(Dialog.SelectPage(Model.Fields[Model.IndexOf('rules')].Page));
      Assert.AreEqual(2, Integer(Dialog.RuleList.Items.Count));
      Assert.IsTrue(Dialog.RuleEditor.Parent.ClientWidth > 400, 'Behälter breit');
      // AutoSize ohne Align ließ den Editor auf die Breite eines leeren Panels schrumpfen.
      Assert.IsTrue(Dialog.RuleEditor.Left + Dialog.RuleEditor.Width >= Dialog.RuleEditor.Parent.ClientWidth - 50,
        'Regel-Editor in voller Breite');
      Assert.IsTrue(Dialog.SetRuleSeverity('no-with', 'off'));
      Assert.AreEqual(StringReplace(Text, '"error"', '"off"', []), Model.ResultText);
      Assert.IsFalse(Dialog.SetRuleSeverity('unbekannt', 'off'));
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
    Catalog.Free;
  end;
end;
procedure TAtlasSettingsPageDialogTests.DialogRulesByGroupNodes;
const
  CatalogText = '{"rules": [{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell",' +
    ' "severity": "hint", "group": "style"}, {"id": "lock-without-finally", "name": "Sperre ohne finally",' +
    ' "category": "bug", "severity": "warning", "group": "threads"}]}';
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Catalog: TJSONValue;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', True);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Users\X\settings.json');
    try
      Dialog.Catalog := Catalog;
      // Unter der Seite mit "rules" je Gruppe ein Knoten (Aufbau wie früher in Tools › Optionen).
      Assert.IsNotNull(Dialog.GroupNode('threads'));
      Assert.IsNotNull(Dialog.GroupNode('style'));
      Assert.AreEqual(Model.Fields[Model.IndexOf('rules')].Page, Dialog.GroupNode('threads').Parent.Text);
      // Knoten der Gruppe: nur ihre Regeln; der Hauptschalter schreibt "group:threads".
      Dialog.HandleNeeded;
      Dialog.PageTree.Selected := Dialog.GroupNode('threads');
      Assert.AreEqual('threads', Dialog.RuleEditor.FixedGroup);
      Assert.AreEqual(1, Dialog.RuleList.Items.Count);
      Assert.IsTrue(Dialog.RuleEditor.Left + Dialog.RuleEditor.Width >= Dialog.RuleEditor.Parent.ClientWidth - 50,
        'Regel-Editor der Gruppe in voller Breite');
      Dialog.RuleEditor.Master.Checked := False;
      Assert.Contains(Model.ResultText, '"group:threads"');
      // „Regel einstellen…“: Knoten der Gruppe der Regel, die Regel markiert.
      Assert.IsTrue(Dialog.SelectRule('magic-number'));
      Assert.IsTrue(Dialog.PageTree.Selected = Dialog.GroupNode('style'));
      Assert.AreEqual('style', Dialog.RuleEditor.FixedGroup);
      Assert.IsNotNull(Dialog.RuleList.Selected);
      Assert.AreEqual('magic-number', Dialog.RuleList.Selected.Caption);
      Assert.IsFalse(Dialog.SelectRule('unbekannt'));
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
    Catalog.Free;
  end;
end;
/// <summary>Abstand des nächsten Steuerelements unter AEditor zu dessen Unterkante; MaxInt ohne.</summary>
function SpaceBelow(ABox: TWinControl; AEditor: TControl): Integer;
var
  mIndex: Integer;
  mControl: TControl;
begin
  Result := MaxInt;
  for mIndex := 0 to ABox.ControlCount - 1 do
  begin
    mControl := ABox.Controls[mIndex];
    if (mControl <> AEditor) and (mControl.Top > AEditor.Top) then
    begin
      Result := Min(Result, mControl.Top - (AEditor.Top + AEditor.Height));
    end;
  end;
end;
procedure TAtlasSettingsPageDialogTests.DialogRuleEditorPushesFieldsDown;
const
  CatalogText = '{"rules": [{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell",' +
    ' "severity": "hint", "group": "style", "description": "Zahl ohne Namen", "bad": "X := 42;",' +
    ' "good": "X := Answer;", "options": [{"name": "ignore", "type": "string-list", "default": ["0"]},' +
    ' {"name": "maxDigits", "type": "integer", "default": 3}], "experimental": true},' +
    ' {"id": "no-with", "name": "Kein with", "category": "code-smell", "severity": "warning"}]}';
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Catalog: TJSONValue;
  Editor: TAtlasRulesEditor;
  Box: TWinControl;
  Before, Spacing, Below: Integer;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Ptlas.json');
    try
      Dialog.Catalog := Catalog;
      Dialog.HandleNeeded;
      Assert.IsTrue(Dialog.SelectPage(Model.Fields[Model.IndexOf('rules')].Page));
      Editor := Dialog.RuleEditor;
      Box := Editor.Parent;
      // Abstand des ersten Steuerelements unter dem Editor zu seiner Unterkante beim Aufbau.
      Spacing := SpaceBelow(Box, Editor);
      Assert.IsTrue(Spacing < MaxInt, 'Zustand und Zurücksetzen von "rules" stehen unter dem Editor');
      Assert.IsTrue(Spacing >= 0);
      Before := Editor.Height;
      Assert.IsTrue(Editor.SelectRule('magic-number'));
      Assert.IsTrue(Editor.Height > Before, 'Optionen und Beispiele lassen den Editor wachsen');
      Below := SpaceBelow(Box, Editor);
      Assert.AreEqual(Spacing, Below, 'Felder darunter rücken mit dem Editor nach unten');
      // Zurück zu einer Regel ohne Optionen: Die Felder rücken wieder hoch.
      Assert.IsTrue(Editor.SelectRule('no-with'));
      Below := SpaceBelow(Box, Editor);
      Assert.AreEqual(Spacing, Below, 'Felder darunter rücken mit dem Editor wieder hoch');
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
    Catalog.Free;
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
