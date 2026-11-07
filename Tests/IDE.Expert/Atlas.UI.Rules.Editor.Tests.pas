unit Atlas.UI.Rules.Editor.Tests;

// Regel-Editor der Seite „Prüfregeln“ (#909): Gruppe mit Hauptschalter, der
// alles sperrt, Suche und Gruppenauswahl, Schweregrad, Ausnahmen und Optionen
// je Regel, Schalter in der Tabelle, „(global: …)“ und Katalogtext.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
  TAtlasRulesEditorTests = class
  private
    FLanguage: TAtlasLanguage;
    FChanges: Integer;
    procedure EditorChanged(Sender: TObject);
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
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
    /// <summary>AutoSize regelt nur die Höhe: Die Breite aus SetBounds bleibt, mit und ohne Fenster, und folgt dem
    /// Anker (früher blieb der Editor bei den 185 Pixeln eines frischen Panels).</summary>
    [Test]
    procedure KeepsRequestedWidth;
    /// <summary>#1296: Eingeblendete Teile (Marke, Optionen, Beispiele, Fehlermeldung) stehen an ihrem Platz und
    /// nicht am Ende des Detailbereichs.</summary>
    [Test]
    procedure DetailsKeepOrderWhenShown;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Atlas.UI.Rules.Editor;

const
  cCatalogText =
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

procedure TAtlasRulesEditorTests.WarmUpFirstUse;
begin
  Setup;
  try
    GroupMasterLocksTable;
  finally
    TearDown;
  end;
end;

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
  mHost: TForm;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mHost := TForm.CreateNew(nil);
  try
    mEditor := NewEditor(mHost, 'threads', mCatalog, '', '');
    Assert.AreEqual(1, mEditor.List.Items.Count);
    Assert.AreEqual('lock-without-finally', mEditor.List.Items[0].Caption);
    Assert.IsFalse(mEditor.Search.Parent.Visible, 'feste Gruppe: keine Suche');
    Assert.IsTrue(mEditor.Master.Visible);
    Assert.IsTrue(mEditor.Master.Checked);
    Assert.AreEqual('Regeln der Gruppe „Threads“ prüfen', mEditor.Master.Caption);
    mEditor.Master.Checked := False;
    Assert.AreEqual('{"group:threads":"off"}', mEditor.RulesJson);
    Assert.IsTrue(mEditor.GroupOff);
    Assert.IsFalse(mEditor.List.Enabled, 'Hauptschalter aus sperrt die Tabelle');
    Assert.IsFalse(mEditor.SeverityChoice.Enabled);
    mEditor.Master.Checked := True;
    Assert.AreEqual('', mEditor.RulesJson);
    Assert.IsTrue(mEditor.List.Enabled);
  finally
    mHost.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.KeepsRequestedWidth;
var
  mHost: TForm;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mHost := TForm.CreateNew(nil);
  try
    mHost.ClientWidth := 900;
    mEditor := TAtlasRulesEditor.Create(mHost);
    mEditor.Parent := mHost;
    mEditor.SetBounds(10, 10, 700, 400);
    Assert.AreEqual(700, mEditor.Width, 'ohne Fenster');
    mEditor.Anchors := [akLeft, akTop, akRight];
    mEditor.SetRules(mCatalog, '', '');
    mEditor.HandleNeeded;
    Assert.AreEqual(700, mEditor.Width, 'mit Fenster');
    Assert.IsTrue(mEditor.Height > 100, 'Höhe aus dem Inhalt');
    mHost.ClientWidth := 1000;
    Assert.AreEqual(800, mEditor.Width, 'folgt dem Anker');
  finally
    mHost.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.DetailsKeepOrderWhenShown;
var
  mHost: TForm;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
  mOrder: TArray<TControl>;
  mIndex: Integer;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mHost := TForm.CreateNew(nil);
  try
    // Ohne Auswahl sind Marke, Optionen und Beispiele ausgeblendet; die übrigen Teile sind schon ausgerichtet.
    mEditor := NewEditor(mHost, 'style', mCatalog, '', '');
    Assert.IsFalse(mEditor.BadMemo.Visible);
    Assert.IsTrue(mEditor.SelectRule('magic-number'));
    Assert.IsTrue(mEditor.MarkLabel.Visible);
    Assert.IsTrue(mEditor.OptionsTitleLabel.Visible);
    Assert.IsTrue(mEditor.GoodMemo.Visible);
    mOrder := TArray<TControl>.Create(mEditor.TitleLabel, mEditor.MarkLabel, mEditor.DescriptionLabel,
      mEditor.SeverityChoice.Parent, mEditor.ExcludeEdit, mEditor.OptionsTitleLabel, mEditor.OptionsBox,
      mEditor.BadLabel, mEditor.BadMemo, mEditor.GoodLabel, mEditor.GoodMemo);
    for mIndex := 1 to High(mOrder) do
    begin
      Assert.IsTrue(mOrder[mIndex - 1].Top + mOrder[mIndex - 1].Height <= mOrder[mIndex].Top,
        Format('%d (%s) vor %d (%s)', [mIndex - 1, mOrder[mIndex - 1].ClassName, mIndex, mOrder[mIndex].ClassName]));
    end;
    // Ungültige Zahl: Die Meldung steht unter den Optionen, nicht unter den Beispielen.
    (mEditor.OptionControls[1] as TEdit).Text := 'x';
    Assert.IsTrue(mEditor.InvalidLabel.Visible);
    Assert.IsTrue(mEditor.InvalidLabel.Top >= mEditor.OptionsBox.Top + mEditor.OptionsBox.Height);
    Assert.IsTrue(mEditor.InvalidLabel.Top + mEditor.InvalidLabel.Height <= mEditor.BadLabel.Top);
  finally
    mOrder := nil;
    mHost.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.CompilerGroupTypeLevel;
var
  mHost: TForm;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mHost := TForm.CreateNew(nil);
  try
    mEditor := NewEditor(mHost, 'threads', mCatalog, '', '');
    Assert.IsFalse(mEditor.TypeLevel.Visible, 'nur in der Gruppe Compiler vorab');
    mEditor.Free;
    mEditor := NewEditor(mHost, 'compiler', mCatalog, '{"group:compiler": {"typeLevel": "off"}}', '');
    Assert.IsTrue(mEditor.TypeLevel.Visible);
    Assert.IsFalse(mEditor.TypeLevel.Checked);
    Assert.IsTrue(mEditor.Master.Checked);
    mEditor.TypeLevel.Checked := True;
    Assert.AreEqual('', mEditor.RulesJson);
    mEditor.TypeLevel.Checked := False;
    mEditor.Master.Checked := False;
    Assert.AreEqual('{"group:compiler":{"typeLevel":"off","severity":"off"}}', mEditor.RulesJson);
    Assert.IsFalse(mEditor.TypeLevel.Enabled, 'Hauptschalter aus sperrt auch die Stufe T');
    Assert.IsFalse(mEditor.TypeLevel.Checked);
  finally
    mHost.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.SearchAndGroupChoiceFilter;
var
  mHost: TForm;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mHost := TForm.CreateNew(nil);
  try
    mEditor := NewEditor(mHost, '', mCatalog, '', '');
    Assert.AreEqual(2, mEditor.List.Items.Count);
    Assert.IsFalse(mEditor.Master.Visible, 'alle Gruppen: kein Hauptschalter');
    // Suche über die Kategorie.
    mEditor.Search.Text := 'code-smell';
    Assert.AreEqual(1, mEditor.List.Items.Count);
    Assert.AreEqual('magic-number', mEditor.List.Items[0].Caption);
    mEditor.Search.Text := '';
    // Gruppe „Threads“ (Eintrag 0 = alle Gruppen) mit eigenem Hauptschalter.
    mEditor.GroupChoice.ItemIndex := 3;
    mEditor.GroupChoice.OnChange(mEditor.GroupChoice);
    Assert.AreEqual(1, mEditor.List.Items.Count);
    Assert.AreEqual('lock-without-finally', mEditor.List.Items[0].Caption);
    Assert.IsTrue(mEditor.Master.Visible);
    // Eine verborgene Regel markieren setzt Gruppe und Suche zurück.
    Assert.IsTrue(mEditor.SelectRule('magic-number'));
    Assert.AreEqual(0, mEditor.GroupChoice.ItemIndex);
    Assert.IsNotNull(mEditor.List.Selected);
    Assert.AreEqual('magic-number', mEditor.List.Selected.Caption);
    Assert.IsFalse(mEditor.SelectRule('unbekannt'));
  finally
    mHost.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.SeverityExcludeAndOptionsWriteRules;
var
  mHost: TForm;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mHost := TForm.CreateNew(nil);
  try
    mEditor := NewEditor(mHost, 'style', mCatalog, '', '');
    FChanges := 0;
    mEditor.OnChange := EditorChanged;
    Assert.IsTrue(mEditor.SelectRule('magic-number'));
    Assert.AreEqual('Vorgabe (Hinweis)', mEditor.SeverityChoice.Items[0]);
    Assert.AreEqual(0, mEditor.SeverityChoice.ItemIndex);
    // Eintrag 1 = Error.
    mEditor.SeverityChoice.ItemIndex := 1;
    mEditor.SeverityChoice.OnChange(mEditor.SeverityChoice);
    Assert.AreEqual('{"magic-number":"error"}', mEditor.RulesJson);
    Assert.AreEqual('Error', mEditor.List.Items[0].SubItems[2]);
    mEditor.ExcludeEdit.Text := 'Tests\*.pas; Vendor.*';
    Assert.AreEqual('{"magic-number":{"severity":"error","exclude":["Tests\\*.pas","Vendor.*"]}}',
      mEditor.RulesJson);
    Assert.AreEqual('Tests\*.pas; Vendor.*', mEditor.List.Items[0].SubItems[3]);
    // Optionen nach Typ: Liste und Zahl; ungültige Zahl wird nicht übernommen.
    Assert.AreEqual(2, Integer(Length(mEditor.OptionControls)));
    Assert.AreEqual('0; 1', (mEditor.OptionControls[0] as TEdit).Text);
    (mEditor.OptionControls[0] as TEdit).Text := '0; 1; 7';
    Assert.IsTrue(mEditor.RulesJson.Contains('"ignore":["0","1","7"]'), mEditor.RulesJson);
    (mEditor.OptionControls[1] as TEdit).Text := '5';
    Assert.IsTrue(mEditor.RulesJson.Contains('"maxDigits":5'), mEditor.RulesJson);
    // Gleich der Vorgabe: Option fällt weg.
    (mEditor.OptionControls[1] as TEdit).Text := '3';
    Assert.IsFalse(mEditor.RulesJson.Contains('maxDigits'), mEditor.RulesJson);
    Assert.IsTrue(FChanges >= 5);
    // Vorgabe: Schweregrad weg, Ausnahmen und Optionen bleiben.
    mEditor.SetSeverity('');
    Assert.IsFalse(mEditor.RulesJson.Contains('severity'), mEditor.RulesJson);
    Assert.IsTrue(mEditor.RulesJson.Contains('exclude'), mEditor.RulesJson);
  finally
    mHost.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.CheckboxTurnsRuleOffAndOn;
var
  mHost: TForm;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
  mItem: TListItem;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mHost := TForm.CreateNew(nil);
  try
    mEditor := NewEditor(mHost, 'threads', mCatalog, '', '');
    mItem := mEditor.List.Items[0];
    Assert.IsTrue(mItem.Checked);
    mItem.Checked := False;
    mEditor.List.OnItemChecked(mEditor.List, mItem);
    Assert.AreEqual('{"lock-without-finally":"off"}', mEditor.RulesJson);
    mItem := mEditor.List.Items[0];
    mItem.Checked := True;
    mEditor.List.OnItemChecked(mEditor.List, mItem);
    Assert.AreEqual('', mEditor.RulesJson, 'an = Vorgabe');
    Assert.IsTrue(mEditor.SetRuleSeverity('lock-without-finally', 'off'));
    Assert.IsFalse(mEditor.List.Items[0].Checked);
    Assert.IsFalse(mEditor.SetRuleSeverity('unbekannt', 'off'));
  finally
    mHost.Free;
    mCatalog.Free;
  end;
end;

procedure TAtlasRulesEditorTests.ShowsGlobalValueAndCatalogText;
var
  mHost: TForm;
  mCatalog: TJSONValue;
  mEditor: TAtlasRulesEditor;
begin
  mCatalog := TJSONObject.ParseJSONValue(cCatalogText);
  mHost := TForm.CreateNew(nil);
  try
    mEditor := NewEditor(mHost, 'style', mCatalog, '', '{"magic-number": "warning"}');
    Assert.AreEqual('Vorgabe (Hinweis) (global: Warnung)', mEditor.List.Items[0].SubItems[2]);
    Assert.IsTrue(mEditor.SelectRule('magic-number'));
    Assert.AreEqual('Magische Zahl  ·  magic-number', mEditor.TitleLabel.Caption);
    Assert.IsTrue(mEditor.MarkLabel.Visible, 'experimentell');
    Assert.AreEqual('Zahl ohne Namen', mEditor.DescriptionLabel.Caption);
    Assert.AreEqual('X := 42;', Trim(mEditor.BadMemo.Lines.Text));
    Assert.AreEqual('X := Answer;', Trim(mEditor.GoodMemo.Lines.Text));
    Assert.AreEqual('Stil und Metriken', AtlasRuleGroupCaption('style'));
    // Ohne Katalog: Hinweis und nur die eingestellten Regeln.
    mEditor.FixedGroup := '';
    mEditor.SetRules(nil, '{"magic-number": "off"}', '');
    Assert.IsTrue(mEditor.Status.Visible);
    Assert.AreEqual(1, mEditor.List.Items.Count);
  finally
    mHost.Free;
    mCatalog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRulesEditorTests);

end.
