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
  mKind: TAtlasNewFileKind;
  mSnippet: TAtlasSnippet;
begin
  for mKind := Low(TAtlasNewFileKind) to High(TAtlasNewFileKind) do
  begin
    Assert.IsTrue(Length(TAtlasFileTemplates.OfKind(nil, mKind)) > 0, TAtlasFileTemplates.KindWord(mKind));
  end;
  Assert.AreEqual(2, Integer(Length(TAtlasFileTemplates.OfKind(nil, TAtlasNewFileKind.UnitFile))));
  for mSnippet in TAtlasFileTemplates.BuiltIn do
  begin
    Assert.AreNotEqual('', mSnippet.FileKind, mSnippet.Prefix);
    Assert.AreEqual<TAtlasSnippetOrigin>(TAtlasSnippetOrigin.BuiltIn, mSnippet.Origin, mSnippet.Prefix);
    Assert.Contains(mSnippet.Body, 'unit %Unit%;', mSnippet.Prefix);
  end;
  Assert.AreEqual('test', TAtlasFileTemplates.KindWord(TAtlasNewFileKind.TestFile));
end;

procedure TAtlasFileTemplatesTests.UserTemplatesReplaceAndAdd;
var
  mList: TAtlasSnippetList;
begin
  // Eigene Vorlage mit gleichem Kürzel ersetzt die mitgelieferte; Code-Vorlagen zählen nicht.
  mList := TAtlasFileTemplates.OfKind([Own('newtest', 'test', 'unit %Unit%; // eigen'), Own('dao', 'test', 'x'),
    Own('tryf', '', 'try'), Own('frm2', 'form', 'f')], TAtlasNewFileKind.TestFile);
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('newtest', mList[0].Prefix);
  Assert.Contains(mList[0].Body, '// eigen');
  Assert.AreEqual('dao', mList[1].Prefix);
  Assert.AreEqual(2, Integer(Length(TAtlasFileTemplates.OfKind([Own('frm2', 'form', 'f')],
    TAtlasNewFileKind.FormFile))));
end;

procedure TAtlasFileTemplatesTests.EntriesForGenerateMenu;
var
  mEntries: TArray<TAtlasGenerateEntry>;
  mList: TAtlasSnippetList;
begin
  mList := TAtlasFileTemplates.OfKind([Own('svc', 'unit', 'x')], TAtlasNewFileKind.UnitFile);
  mEntries := TAtlasFileTemplates.Entries(mList);
  Assert.AreEqual(3, Integer(Length(mEntries)));
  Assert.AreEqual('snippet:newunit', mEntries[0].Id);
  Assert.AreEqual('Leere Unit', mEntries[0].Caption);
  Assert.AreEqual(0, mEntries[0].Source);
  Assert.AreEqual<TAtlasGenerateGroup>(TAtlasGenerateGroup.Templates, mEntries[2].Group);
  Assert.AreEqual<TAtlasGenerateKind>(TAtlasGenerateKind.Snippet, mEntries[2].Kind);
  Assert.AreEqual(2, mEntries[2].Source);
  Assert.IsFalse(mEntries[2].NeedsStep, 'Dateivorlagen brauchen kein Argument');
end;

procedure TAtlasFileTemplatesTests.RendersUnit;
var
  mText: string;
begin
  mText := TAtlasFileTemplates.Render(TAtlasFileTemplates.BuiltIn[1].Body, 'App.Kunden', '', '', #13#10);
  Assert.Contains(mText, 'unit App.Kunden;'#13#10#13#10'interface');
  Assert.Contains(mText, '  TKunden = class');
  Assert.Contains(mText, 'constructor TKunden.Create;');
  Assert.IsTrue(mText.EndsWith('end.'#13#10), mText);
  Assert.AreEqual(0, Pos('%', mText), mText);
  // Platzhalter und $$ wie bei Code-Vorlagen.
  Assert.AreEqual('unit U;'#10'const C = ''Name'';'#10'// $1'#10,
    TAtlasFileTemplates.Render('unit %unit%;'#10'const C = ''${1:Name}'';'#10'// $$1'#10#10, 'U', '', '', #10));
end;

procedure TAtlasFileTemplatesTests.RendersFormAndTest;
var
  mText: string;
begin
  mText := TAtlasFileTemplates.Render(TAtlasFileTemplates.OfKind(nil, TAtlasNewFileKind.FormFile)[0].Body, 'Unit3',
    'Form3', 'Form', #10);
  Assert.Contains(mText, '  TForm3 = class(TForm)');
  Assert.Contains(mText, '  Form3: TForm3;');
  Assert.Contains(mText, '{$R *.dfm}');
  mText := TAtlasFileTemplates.Render(TAtlasFileTemplates.OfKind(nil, TAtlasNewFileKind.FormFile)[0].Body, 'Unit3',
    '', '', #10);
  Assert.Contains(mText, '  TUnit3 = class(TForm)', 'ohne Angaben: Name der Unit und TForm');
  mText := TAtlasFileTemplates.Render(TAtlasFileTemplates.OfKind(nil, TAtlasNewFileKind.TestFile)[0].Body,
    'Tests.Kunden', '', '', #10);
  Assert.Contains(mText, 'uses'#10'  DUnitX.TestFramework;');
  Assert.Contains(mText, '  [TestFixture]'#10'  TKundenTests = class');
  Assert.Contains(mText, '  TDUnitX.RegisterTestFixture(TKundenTests);');
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
