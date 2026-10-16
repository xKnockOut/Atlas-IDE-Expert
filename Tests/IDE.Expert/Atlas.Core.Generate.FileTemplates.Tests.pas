unit Atlas.Core.Generate.FileTemplates.Tests;

// Tests für die Dateivorlagen von „Neu mit Atlas“ (#759): mitgelieferte
// Vorlagen je Art, eigene Vorlagen, Einträge für das Erzeugen-Menü und das
// Einsetzen der Variablen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasFileTemplatesTests = class
  public
    [Test]
    procedure BuiltInCoversEveryKind;
    [Test]
    procedure UserTemplatesReplaceAndAdd;
    [Test]
    procedure EntriesForGenerateMenu;
    [Test]
    procedure RendersUnit;
    [Test]
    procedure RendersFormAndTest;
    [Test]
    procedure ShortNameDropsNamespace;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Generate.Menu,
  Atlas.Core.Generate.FileTemplates;

function Own(const APrefix, AKind, ABody: string): TAtlasSnippet;
begin
  Result := Default(TAtlasSnippet);
  Result.Prefix := APrefix;
  Result.Name := APrefix;
  Result.FileKind := AKind;
  Result.Body := ABody;
  Result.Origin := TAtlasSnippetOrigin.User;
end;

{ TAtlasFileTemplatesTests }

procedure TAtlasFileTemplatesTests.BuiltInCoversEveryKind;
var
  Kind: TAtlasNewFileKind;
  Snippet: TAtlasSnippet;
begin
  for Kind := Low(TAtlasNewFileKind) to High(TAtlasNewFileKind) do
    Assert.IsTrue(Length(TAtlasFileTemplates.OfKind(nil, Kind)) > 0, TAtlasFileTemplates.KindWord(Kind));
  Assert.AreEqual(2, Integer(Length(TAtlasFileTemplates.OfKind(nil, TAtlasNewFileKind.UnitFile))));
  for Snippet in TAtlasFileTemplates.BuiltIn do
  begin
    Assert.IsTrue(Snippet.FileKind <> '', Snippet.Prefix);
    Assert.IsTrue(Snippet.Origin = TAtlasSnippetOrigin.BuiltIn, Snippet.Prefix);
    Assert.Contains(Snippet.Body, 'unit %Unit%;', Snippet.Prefix);
  end;
  Assert.AreEqual('test', TAtlasFileTemplates.KindWord(TAtlasNewFileKind.TestFile));
end;

procedure TAtlasFileTemplatesTests.UserTemplatesReplaceAndAdd;
var
  List: TAtlasSnippetList;
begin
  // Eigene Vorlage mit gleichem Kürzel ersetzt die mitgelieferte; Code-Vorlagen zählen nicht.
  List := TAtlasFileTemplates.OfKind([Own('newtest', 'test', 'unit %Unit%; // eigen'), Own('dao', 'test', 'x'),
    Own('tryf', '', 'try'), Own('frm2', 'form', 'f')], TAtlasNewFileKind.TestFile);
  Assert.AreEqual(2, Integer(Length(List)));
  Assert.AreEqual('newtest', List[0].Prefix);
  Assert.Contains(List[0].Body, '// eigen');
  Assert.AreEqual('dao', List[1].Prefix);
  Assert.AreEqual(2, Integer(Length(TAtlasFileTemplates.OfKind([Own('frm2', 'form', 'f')],
    TAtlasNewFileKind.FormFile))));
end;

procedure TAtlasFileTemplatesTests.EntriesForGenerateMenu;
var
  Entries: TArray<TAtlasGenerateEntry>;
  List: TAtlasSnippetList;
begin
  List := TAtlasFileTemplates.OfKind([Own('svc', 'unit', 'x')], TAtlasNewFileKind.UnitFile);
  Entries := TAtlasFileTemplates.Entries(List);
  Assert.AreEqual(3, Integer(Length(Entries)));
  Assert.AreEqual('snippet:newunit', Entries[0].Id);
  Assert.AreEqual('Leere Unit', Entries[0].Caption);
  Assert.AreEqual(0, Entries[0].Source);
  Assert.IsTrue(Entries[2].Group = TAtlasGenerateGroup.Templates);
  Assert.IsTrue(Entries[2].Kind = TAtlasGenerateKind.Snippet);
  Assert.AreEqual(2, Entries[2].Source);
  Assert.IsFalse(Entries[2].NeedsStep, 'Dateivorlagen brauchen kein Argument');
end;

procedure TAtlasFileTemplatesTests.RendersUnit;
var
  Text: string;
begin
  Text := TAtlasFileTemplates.Render(TAtlasFileTemplates.BuiltIn[1].Body, 'App.Kunden', '', '', #13#10);
  Assert.Contains(Text, 'unit App.Kunden;'#13#10#13#10'interface');
  Assert.Contains(Text, '  TKunden = class');
  Assert.Contains(Text, 'constructor TKunden.Create;');
  Assert.IsTrue(Text.EndsWith('end.'#13#10), Text);
  Assert.IsTrue(Pos('%', Text) = 0, Text);
  // Platzhalter und $$ wie bei Code-Vorlagen.
  Assert.AreEqual('unit U;'#10'const C = ''Name'';'#10'// $1'#10,
    TAtlasFileTemplates.Render('unit %unit%;'#10'const C = ''${1:Name}'';'#10'// $$1'#10#10, 'U', '', '', #10));
end;

procedure TAtlasFileTemplatesTests.RendersFormAndTest;
var
  Text: string;
begin
  Text := TAtlasFileTemplates.Render(TAtlasFileTemplates.OfKind(nil, TAtlasNewFileKind.FormFile)[0].Body, 'Unit3',
    'Form3', 'Form', #10);
  Assert.Contains(Text, '  TForm3 = class(TForm)');
  Assert.Contains(Text, '  Form3: TForm3;');
  Assert.Contains(Text, '{$R *.dfm}');
  Text := TAtlasFileTemplates.Render(TAtlasFileTemplates.OfKind(nil, TAtlasNewFileKind.FormFile)[0].Body, 'Unit3',
    '', '', #10);
  Assert.Contains(Text, '  TUnit3 = class(TForm)', 'ohne Angaben: Name der Unit und TForm');
  Text := TAtlasFileTemplates.Render(TAtlasFileTemplates.OfKind(nil, TAtlasNewFileKind.TestFile)[0].Body,
    'Tests.Kunden', '', '', #10);
  Assert.Contains(Text, 'uses'#10'  DUnitX.TestFramework;');
  Assert.Contains(Text, '  [TestFixture]'#10'  TKundenTests = class');
  Assert.Contains(Text, '  TDUnitX.RegisterTestFixture(TKundenTests);');
end;

procedure TAtlasFileTemplatesTests.ShortNameDropsNamespace;
begin
  Assert.AreEqual('Kunden', TAtlasFileTemplates.ShortName('App.Model.Kunden'));
  Assert.AreEqual('Unit2', TAtlasFileTemplates.ShortName(' Unit2 '));
  Assert.AreEqual('', TAtlasFileTemplates.ShortName(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFileTemplatesTests);

end.
