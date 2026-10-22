unit Atlas.UI.Settings.Rules.Tests;

// Regel-Editor der Seite „Prüfregeln“ (#909): Gruppe mit Hauptschalter, der
// alles sperrt, Suche und Gruppenauswahl, Schweregrad, Ausnahmen und Optionen
// je Regel, Schalter in der Tabelle, „(global: …)“ und Katalogtext.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasRulesEditorTests = class
  private
    FLanguage: TAtlasLanguage;
    FChanges: Integer;
    procedure EditorChanged(Sender: TObject);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure GroupMasterLocksTable;
    /// <summary>#1024: „Regeln der Stufe T prüfen“ nur in der Gruppe „Compiler vorab“, als Option des
    /// Gruppenschlüssels; der Hauptschalter sperrt ihn.</summary>
    [Test]
    procedure CompilerGroupTypeLevel;
    [Test]
    procedure SearchAndGroupChoiceFilter;
    [Test]
    procedure SeverityExcludeAndOptionsWriteRules;
    [Test]
    procedure CheckboxTurnsRuleOffAndOn;
    [Test]
    procedure ShowsGlobalValueAndCatalogText;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.UI.Settings.Rules;

const
  CatalogText =
    '{"rules": [' +
    '{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell", "severity": "hint",' +
    ' "group": "style", "description": "Zahl ohne Namen", "bad": "X := 42;", "good": "X := Answer;",' +
    ' "options": [{"name": "ignore", "type": "string-list", "default": ["0", "1"]},' +
    ' {"name": "maxDigits", "type": "integer", "default": 3}], "experimental": true},' +
    '{"id": "lock-without-finally", "name": "Sperre ohne finally", "category": "bug", "severity": "warning",' +
    ' "group": "threads", "description": "Sperre bleibt bei Exception", "options": []}]}';

function NewEditor(AHost: TForm; const AGroup: string; ACatalog: TJSONValue; const ARules,
  AOther: string): TAtlasRulesEditor;
begin
  Result := TAtlasRulesEditor.Create(AHost);
  Result.Parent := AHost;
  Result.Width := 700;
  Result.FixedGroup := AGroup;
  Result.SetRules(ACatalog, ARules, AOther);
  Result.HandleNeeded;
end;

{ TAtlasRulesEditorTests }

procedure TAtlasRulesEditorTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasRulesEditorTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasRulesEditorTests.EditorChanged(Sender: TObject);
begin
  Inc(FChanges);
end;

procedure TAtlasRulesEditorTests.GroupMasterLocksTable;
var
  Host: TForm;
  Catalog: TJSONValue;
  Editor: TAtlasRulesEditor;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Host := TForm.CreateNew(nil);
  try
    Editor := NewEditor(Host, 'threads', Catalog, '', '');
    Assert.AreEqual(1, Editor.List.Items.Count);
    Assert.AreEqual('lock-without-finally', Editor.List.Items[0].Caption);
    Assert.IsFalse(Editor.Search.Parent.Visible, 'feste Gruppe: keine Suche');
    Assert.IsTrue(Editor.Master.Visible);
    Assert.IsTrue(Editor.Master.Checked);
    Assert.AreEqual('Regeln der Gruppe „Threads“ prüfen', Editor.Master.Caption);
    Editor.Master.Checked := False;
    Assert.AreEqual('{"group:threads":"off"}', Editor.RulesJson);
    Assert.IsTrue(Editor.GroupOff);
    Assert.IsFalse(Editor.List.Enabled, 'Hauptschalter aus sperrt die Tabelle');
    Assert.IsFalse(Editor.SeverityChoice.Enabled);
    Editor.Master.Checked := True;
    Assert.AreEqual('', Editor.RulesJson);
    Assert.IsTrue(Editor.List.Enabled);
  finally
    Host.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.CompilerGroupTypeLevel;
var
  Host: TForm;
  Catalog: TJSONValue;
  Editor: TAtlasRulesEditor;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Host := TForm.CreateNew(nil);
  try
    Editor := NewEditor(Host, 'threads', Catalog, '', '');
    Assert.IsFalse(Editor.TypeLevel.Visible, 'nur in der Gruppe Compiler vorab');
    Editor.Free;
    Editor := NewEditor(Host, 'compiler', Catalog, '{"group:compiler": {"typeLevel": "off"}}', '');
    Assert.IsTrue(Editor.TypeLevel.Visible);
    Assert.IsFalse(Editor.TypeLevel.Checked);
    Assert.IsTrue(Editor.Master.Checked);
    Editor.TypeLevel.Checked := True;
    Assert.AreEqual('', Editor.RulesJson);
    Editor.TypeLevel.Checked := False;
    Editor.Master.Checked := False;
    Assert.AreEqual('{"group:compiler":{"typeLevel":"off","severity":"off"}}', Editor.RulesJson);
    Assert.IsFalse(Editor.TypeLevel.Enabled, 'Hauptschalter aus sperrt auch die Stufe T');
    Assert.IsFalse(Editor.TypeLevel.Checked);
  finally
    Host.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.SearchAndGroupChoiceFilter;
var
  Host: TForm;
  Catalog: TJSONValue;
  Editor: TAtlasRulesEditor;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Host := TForm.CreateNew(nil);
  try
    Editor := NewEditor(Host, '', Catalog, '', '');
    Assert.AreEqual(2, Editor.List.Items.Count);
    Assert.IsFalse(Editor.Master.Visible, 'alle Gruppen: kein Hauptschalter');
    // Suche über die Kategorie.
    Editor.Search.Text := 'code-smell';
    Assert.AreEqual(1, Editor.List.Items.Count);
    Assert.AreEqual('magic-number', Editor.List.Items[0].Caption);
    Editor.Search.Text := '';
    // Gruppe „Threads“ (Eintrag 0 = alle Gruppen) mit eigenem Hauptschalter.
    Editor.GroupChoice.ItemIndex := 3;
    Editor.GroupChoice.OnChange(Editor.GroupChoice);
    Assert.AreEqual(1, Editor.List.Items.Count);
    Assert.AreEqual('lock-without-finally', Editor.List.Items[0].Caption);
    Assert.IsTrue(Editor.Master.Visible);
    // Eine verborgene Regel markieren setzt Gruppe und Suche zurück.
    Assert.IsTrue(Editor.SelectRule('magic-number'));
    Assert.AreEqual(0, Editor.GroupChoice.ItemIndex);
    Assert.IsNotNull(Editor.List.Selected);
    Assert.AreEqual('magic-number', Editor.List.Selected.Caption);
    Assert.IsFalse(Editor.SelectRule('unbekannt'));
  finally
    Host.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.SeverityExcludeAndOptionsWriteRules;
var
  Host: TForm;
  Catalog: TJSONValue;
  Editor: TAtlasRulesEditor;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Host := TForm.CreateNew(nil);
  try
    Editor := NewEditor(Host, 'style', Catalog, '', '');
    FChanges := 0;
    Editor.OnChange := EditorChanged;
    Assert.IsTrue(Editor.SelectRule('magic-number'));
    Assert.AreEqual('Vorgabe (Hinweis)', Editor.SeverityChoice.Items[0]);
    Assert.AreEqual(0, Editor.SeverityChoice.ItemIndex);
    // Eintrag 1 = Error.
    Editor.SeverityChoice.ItemIndex := 1;
    Editor.SeverityChoice.OnChange(Editor.SeverityChoice);
    Assert.AreEqual('{"magic-number":"error"}', Editor.RulesJson);
    Assert.AreEqual('Error', Editor.List.Items[0].SubItems[2]);
    Editor.ExcludeEdit.Text := 'Tests\*.pas; Vendor.*';
    Assert.AreEqual('{"magic-number":{"severity":"error","exclude":["Tests\\*.pas","Vendor.*"]}}',
      Editor.RulesJson);
    Assert.AreEqual('Tests\*.pas; Vendor.*', Editor.List.Items[0].SubItems[3]);
    // Optionen nach Typ: Liste und Zahl; ungültige Zahl wird nicht übernommen.
    Assert.AreEqual(2, Integer(Length(Editor.OptionControls)));
    Assert.AreEqual('0; 1', (Editor.OptionControls[0] as TEdit).Text);
    (Editor.OptionControls[0] as TEdit).Text := '0; 1; 7';
    Assert.IsTrue(Editor.RulesJson.Contains('"ignore":["0","1","7"]'), Editor.RulesJson);
    (Editor.OptionControls[1] as TEdit).Text := '5';
    Assert.IsTrue(Editor.RulesJson.Contains('"maxDigits":5'), Editor.RulesJson);
    // Gleich der Vorgabe: Option fällt weg.
    (Editor.OptionControls[1] as TEdit).Text := '3';
    Assert.IsFalse(Editor.RulesJson.Contains('maxDigits'), Editor.RulesJson);
    Assert.IsTrue(FChanges >= 5);
    // Vorgabe: Schweregrad weg, Ausnahmen und Optionen bleiben.
    Editor.SetSeverity('');
    Assert.IsFalse(Editor.RulesJson.Contains('severity'), Editor.RulesJson);
    Assert.IsTrue(Editor.RulesJson.Contains('exclude'), Editor.RulesJson);
  finally
    Host.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.CheckboxTurnsRuleOffAndOn;
var
  Host: TForm;
  Catalog: TJSONValue;
  Editor: TAtlasRulesEditor;
  Item: TListItem;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Host := TForm.CreateNew(nil);
  try
    Editor := NewEditor(Host, 'threads', Catalog, '', '');
    Item := Editor.List.Items[0];
    Assert.IsTrue(Item.Checked);
    Item.Checked := False;
    Editor.List.OnItemChecked(Editor.List, Item);
    Assert.AreEqual('{"lock-without-finally":"off"}', Editor.RulesJson);
    Item := Editor.List.Items[0];
    Item.Checked := True;
    Editor.List.OnItemChecked(Editor.List, Item);
    Assert.AreEqual('', Editor.RulesJson, 'an = Vorgabe');
    Assert.IsTrue(Editor.SetRuleSeverity('lock-without-finally', 'off'));
    Assert.IsFalse(Editor.List.Items[0].Checked);
    Assert.IsFalse(Editor.SetRuleSeverity('unbekannt', 'off'));
  finally
    Host.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.ShowsGlobalValueAndCatalogText;
var
  Host: TForm;
  Catalog: TJSONValue;
  Editor: TAtlasRulesEditor;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Host := TForm.CreateNew(nil);
  try
    Editor := NewEditor(Host, 'style', Catalog, '', '{"magic-number": "warning"}');
    Assert.AreEqual('Vorgabe (Hinweis) (global: Warnung)', Editor.List.Items[0].SubItems[2]);
    Assert.IsTrue(Editor.SelectRule('magic-number'));
    Assert.AreEqual('Magische Zahl  ·  magic-number', Editor.TitleLabel.Caption);
    Assert.IsTrue(Editor.MarkLabel.Visible, 'experimentell');
    Assert.AreEqual('Zahl ohne Namen', Editor.DescriptionLabel.Caption);
    Assert.AreEqual('X := 42;', Trim(Editor.BadMemo.Lines.Text));
    Assert.AreEqual('X := Answer;', Trim(Editor.GoodMemo.Lines.Text));
    Assert.AreEqual('Stil und Metriken', AtlasRuleGroupCaption('style'));
    // Ohne Katalog: Hinweis und nur die eingestellten Regeln.
    Editor.FixedGroup := '';
    Editor.SetRules(nil, '{"magic-number": "off"}', '');
    Assert.IsTrue(Editor.Status.Visible);
    Assert.AreEqual(1, Editor.List.Items.Count);
  finally
    Host.Free;
    Catalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRulesEditorTests);

end.
