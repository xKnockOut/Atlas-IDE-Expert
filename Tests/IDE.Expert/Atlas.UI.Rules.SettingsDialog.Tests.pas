unit Atlas.UI.Rules.SettingsDialog.Tests;

// Dialog der Einstellungsdateien mit Regel-Editor (#909, #1296), seit #1755 im Modul Prüfregeln: Regeltabelle
// ändert nur ihre Regel, ein Knoten je Gruppe mit Hauptschalter, „Regel einstellen…“ springt zur Regel, Felder
// unter dem Editor rücken mit. Ohne Modul: Atlas.UI.Settings.Page.Dialog.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
  TAtlasRulesSettingsDialogTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure ProviderNamesRulesDialog;
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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  System.Math,
  Vcl.Controls,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Layers,
  Atlas.UI.Settings.ProjectDialog,
  Atlas.UI.Rules.Editor,
  Atlas.UI.Rules.SettingsDialog,
  Atlas.UI.Settings.Page.TestSupport;

procedure TAtlasRulesSettingsDialogTests.WarmUp;
begin
  WarmUpSettingsPage;
end;
procedure TAtlasRulesSettingsDialogTests.ProviderNamesRulesDialog;
var
  mProvider: IAtlasSettingsDialogProvider;
begin
  mProvider := TAtlasRulesDialogProvider.Create;
  Assert.IsTrue(mProvider.DialogClass = TAtlasRulesSettingsDialog);
end;
procedure TAtlasRulesSettingsDialogTests.DialogRuleTableChangesOnlyThatRule;
const
  cText = '{' + #13#10 + '  "rules": {' + #13#10 + '    "no-with": "error" // streng' + #13#10 + '  }' + #13#10 + '}';
var
  mModel: TAtlasSettingsModel;
  mDialog: TAtlasRulesSettingsDialog;
  mCatalog: TJSONValue;
begin
  mCatalog := TJSONObject.ParseJSONValue('{"rules": [{"id": "no-with", "name": "Kein with", "category": "code-smell",' +
    ' "severity": "warning"}, {"id": "empty-except", "name": "Leeres except", "category": "bug",' +
    ' "severity": "error"}]}');
  mModel := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), cText, '', False);
  try
    mDialog := TAtlasRulesSettingsDialog.CreateDialog(nil, mModel, 'C:\P\atlas.json');
    try
      mDialog.Catalog := mCatalog;
      // Mit Fenster: Erst dann hat der Behälter seine Breite; ohne war die Prüfung der Breite wertlos.
      mDialog.HandleNeeded;
      Assert.IsTrue(mDialog.SelectPage(mModel.Fields[mModel.IndexOf('rules')].Page));
      Assert.AreEqual(2, Integer(mDialog.RuleList.Items.Count));
      Assert.IsTrue(mDialog.RuleEditor.Parent.ClientWidth > 400, 'Behälter breit');
      // AutoSize ohne Align ließ den Editor auf die Breite eines leeren Panels schrumpfen.
      Assert.IsTrue(mDialog.RuleEditor.Left + mDialog.RuleEditor.Width >= mDialog.RuleEditor.Parent.ClientWidth - 50,
        'Regel-Editor in voller Breite');
      Assert.IsTrue(mDialog.SetRuleSeverity('no-with', 'off'));
      Assert.AreEqual(StringReplace(cText, '"error"', '"off"', []), mModel.ResultText);
      Assert.IsFalse(mDialog.SetRuleSeverity('unbekannt', 'off'));
    finally
      mDialog.Free;
    end;
  finally
    mModel.Free;
    mCatalog.Free;
  end;
end;
procedure TAtlasRulesSettingsDialogTests.DialogRulesByGroupNodes;
const
  cCatalogText = '{"rules": [{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell",' +
    ' "severity": "hint", "group": "style"}, {"id": "lock-without-finally", "name": "Sperre ohne finally",' +
    ' "category": "bug", "severity": "warning", "group": "threads"}]}';
var
  mModel: TAtlasSettingsModel;
  mDialog: TAtlasRulesSettingsDialog;
  mCatalog: TJSONValue;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mModel := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', True);
  try
    mDialog := TAtlasRulesSettingsDialog.CreateDialog(nil, mModel, 'C:\Users\X\settings.json');
    try
      mDialog.Catalog := mCatalog;
      // Unter der Seite mit "rules" je Gruppe ein Knoten (Aufbau wie früher in Tools › Optionen).
      Assert.IsNotNull(mDialog.GroupNode('threads'));
      Assert.IsNotNull(mDialog.GroupNode('style'));
      Assert.AreEqual(mModel.Fields[mModel.IndexOf('rules')].Page, mDialog.GroupNode('threads').Parent.Text);
      // Knoten der Gruppe: nur ihre Regeln; der Hauptschalter schreibt "group:threads".
      mDialog.HandleNeeded;
      mDialog.PageTree.Selected := mDialog.GroupNode('threads');
      Assert.AreEqual('threads', mDialog.RuleEditor.FixedGroup);
      Assert.AreEqual(1, mDialog.RuleList.Items.Count);
      Assert.IsTrue(mDialog.RuleEditor.Left + mDialog.RuleEditor.Width >= mDialog.RuleEditor.Parent.ClientWidth - 50,
        'Regel-Editor der Gruppe in voller Breite');
      mDialog.RuleEditor.Master.Checked := False;
      Assert.Contains(mModel.ResultText, '"group:threads"');
      // „Regel einstellen…“: Knoten der Gruppe der Regel, die Regel markiert.
      Assert.IsTrue(mDialog.SelectRule('magic-number'));
      Assert.IsTrue(mDialog.PageTree.Selected = mDialog.GroupNode('style'));
      Assert.AreEqual('style', mDialog.RuleEditor.FixedGroup);
      Assert.IsNotNull(mDialog.RuleList.Selected);
      Assert.AreEqual('magic-number', mDialog.RuleList.Selected.Caption);
      Assert.IsFalse(mDialog.SelectRule('unbekannt'));
    finally
      mDialog.Free;
    end;
  finally
    mModel.Free;
    mCatalog.Free;
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
procedure TAtlasRulesSettingsDialogTests.DialogRuleEditorPushesFieldsDown;
const
  cCatalogText = '{"rules": [{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell",' +
    ' "severity": "hint", "group": "style", "description": "Zahl ohne Namen", "bad": "X := 42;",' +
    ' "good": "X := Answer;", "options": [{"name": "ignore", "type": "string-list", "default": ["0"]},' +
    ' {"name": "maxDigits", "type": "integer", "default": 3}], "experimental": true},' +
    ' {"id": "no-with", "name": "Kein with", "category": "code-smell", "severity": "warning"}]}';
var
  mModel: TAtlasSettingsModel;
  mDialog: TAtlasRulesSettingsDialog;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
  mBox: TWinControl;
  mBefore, mSpacing, mBelow: Integer;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mModel := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', False);
  try
    mDialog := TAtlasRulesSettingsDialog.CreateDialog(nil, mModel, 'C:\P\atlas.json');
    try
      mDialog.Catalog := mCatalog;
      mDialog.HandleNeeded;
      Assert.IsTrue(mDialog.SelectPage(mModel.Fields[mModel.IndexOf('rules')].Page));
      mEditor := mDialog.RuleEditor;
      mBox := mEditor.Parent;
      // Abstand des ersten Steuerelements unter dem Editor zu seiner Unterkante beim Aufbau.
      mSpacing := SpaceBelow(mBox, mEditor);
      Assert.IsTrue(mSpacing < MaxInt, 'Zustand und Zurücksetzen von "rules" stehen unter dem Editor');
      Assert.IsTrue(mSpacing >= 0);
      mBefore := mEditor.Height;
      Assert.IsTrue(mEditor.SelectRule('magic-number'));
      Assert.IsTrue(mEditor.Height > mBefore, 'Optionen und Beispiele lassen den Editor wachsen');
      mBelow := SpaceBelow(mBox, mEditor);
      Assert.AreEqual(mSpacing, mBelow, 'Felder darunter rücken mit dem Editor nach unten');
      // Zurück zu einer Regel ohne Optionen: Die Felder rücken wieder hoch.
      Assert.IsTrue(mEditor.SelectRule('no-with'));
      mBelow := SpaceBelow(mBox, mEditor);
      Assert.AreEqual(mSpacing, mBelow, 'Felder darunter rücken mit dem Editor wieder hoch');
    finally
      mDialog.Free;
    end;
  finally
    mModel.Free;
    mCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRulesSettingsDialogTests);

end.
