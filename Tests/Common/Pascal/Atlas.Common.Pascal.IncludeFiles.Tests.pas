unit Atlas.Common.Pascal.IncludeFiles.Tests;

// Tests für den gemeinsamen Include-Resolver (#264): Suche, Index,
// Abblenden und Verweise finden dieselbe Datei; Zyklen ergeben einen Befund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIncludeFilesTests = class
  public
    // Dateien je Test neu anlegen: Ein gemeinsames Wörterbuch wuchs und schrumpfte
    // zwischen den Tests, der Leck-Monitor meldete das als Lecks.
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SearchOrderUnitDirThenSearchPaths;
    [Test]
    procedure AddsIncExtension;
    [Test]
    procedure QuotedNameWithSpaces;
    [Test]
    procedure SharedFileForLinksIndexAndInactive;
    [Test]
    procedure MissingIncludeIsReported;
    [Test]
    procedure CycleGivesOneIssue;
    [Test]
    procedure WithoutResolverNoIssues;
    [Test]
    procedure IndexesDeclarationsFromIncludes;
    [Test]
    procedure IncludeCycleEndsWithoutDuplicates;
    [Test]
    procedure DefinitionAndCompletionReachIncludeFile;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.DocumentLinks,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.Completion;

const
  MainFile = 'C:\P\Main.pas';

var
  // Dateien im Speicher: Name in Großbuchstaben auf Inhalt.
  Files: TDictionary<string, string>;

procedure Put(const AFileName, AText: string);
begin
  Files.AddOrSetValue(UpperCase(AFileName), AText);
end;

function Exists: TIncludeFileExists;
begin
  Result :=
    function(const AFileName: string): Boolean
    begin
      Result := Files.ContainsKey(UpperCase(AFileName));
    end;
end;

function Resolver(const ASearchPaths: TArray<string>): TIncludeResolver;
begin
  Result := TIncludeFiles.Resolver(ASearchPaths, Exists(),
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Files.TryGetValue(UpperCase(AFileName), AText);
    end);
end;

{ TIncludeFilesTests }

procedure TIncludeFilesTests.Setup;
begin
  Files := TDictionary<string, string>.Create;
end;

procedure TIncludeFilesTests.TearDown;
begin
  FreeAndNil(Files);
end;

procedure TIncludeFilesTests.SearchOrderUnitDirThenSearchPaths;
var
  FileName: string;
begin
  Files.Clear;
  Put('C:\Lib\Shared.inc', '');
  Assert.IsTrue(TIncludeFiles.FindInclude('Shared.inc', MainFile, ['C:\Lib'], Exists(), FileName));
  Assert.AreEqual('C:\Lib\Shared.inc', FileName);
  Put('C:\P\Shared.inc', '');
  Assert.IsTrue(TIncludeFiles.FindInclude('Shared.inc', MainFile, ['C:\Lib'], Exists(), FileName));
  Assert.AreEqual('C:\P\Shared.inc', FileName, 'Ordner der Unit vor Suchpfad');
  Assert.IsFalse(TIncludeFiles.FindInclude('Fehlt.inc', MainFile, ['C:\Lib'], Exists(), FileName));
end;

procedure TIncludeFilesTests.AddsIncExtension;
var
  FileName: string;
begin
  Files.Clear;
  Put('C:\P\Defines.inc', '');
  Assert.IsTrue(TIncludeFiles.FindInclude('Defines', MainFile, nil, Exists(), FileName));
  Assert.AreEqual('C:\P\Defines.inc', FileName);
  // FindFile ($R, Strings) ergänzt keine Endung.
  Assert.IsFalse(TIncludeFiles.FindFile('Defines', 'C:\P', nil, Exists(), FileName));
end;

procedure TIncludeFilesTests.QuotedNameWithSpaces;
var
  FileName: string;
begin
  Files.Clear;
  Put('C:\P\Mit Leerzeichen.inc', '');
  Assert.IsTrue(TIncludeFiles.FindInclude('''Mit Leerzeichen.inc''', MainFile, nil, Exists(), FileName));
  Assert.AreEqual('C:\P\Mit Leerzeichen.inc', FileName);
end;

procedure TIncludeFilesTests.SharedFileForLinksIndexAndInactive;
const
  Text = 'unit Main;'#10'{$I Defines.inc}'#10'interface'#10 +
    '{$IFDEF FEATURE}'#10'procedure MitFeature;'#10'{$ELSE}'#10'procedure OhneFeature;'#10'{$ENDIF}'#10 +
    'implementation'#10'end.';
var
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Names: string;
  Ranges: TArray<TTextRange>;
  Issues: TArray<TPreprocessorIssue>;
  Links: TArray<TDocumentLink>;
begin
  Files.Clear;
  Put('C:\Lib\Defines.inc', '{$DEFINE FEATURE}');
  // Index
  UnitIndex := TIndexExtractor.ExtractText(Text, MainFile, nil, Resolver(['C:\Lib']));
  Names := '';
  for Symbol in UnitIndex.Symbols do
    Names := Names + Symbol.Name + ';';
  Assert.Contains(Names, 'MitFeature');
  Assert.DoesNotContain(Names, 'OhneFeature');
  Assert.AreEqual(1, Integer(Length(UnitIndex.Includes)));
  Assert.AreEqual('C:\Lib\Defines.inc', UnitIndex.Includes[0]);
  // Abblenden: nur der $ELSE-Zweig (Zeile 6) ist inaktiv.
  Ranges := TLspInactiveRegions.Ranges(Text, nil, MainFile, Resolver(['C:\Lib']), Issues);
  Assert.AreEqual(1, Integer(Length(Ranges)));
  Assert.IsTrue((Ranges[0].StartPos.Line <= 6) and (Ranges[0].EndPos.Line >= 6) and (Ranges[0].StartPos.Line >= 5));
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Verweise: dieselbe Datei
  Links := TDocumentLinks.Find(Text, MainFile, ['C:\Lib'], Exists());
  Assert.AreEqual(1, Integer(Length(Links)));
  Assert.AreEqual('C:\Lib\Defines.inc', Links[0].Target);
end;

procedure TIncludeFilesTests.MissingIncludeIsReported;
var
  Issues: TArray<TPreprocessorIssue>;
begin
  Files.Clear;
  TLspInactiveRegions.Ranges('unit Main;'#10'{$I Fehlt.inc}'#10'end.', nil, MainFile, Resolver(nil), Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual(Ord(TPreprocessorIssueKind.IncludeMissing), Ord(Issues[0].Kind));
  Assert.AreEqual(1, Issues[0].Range.StartPos.Line);
end;

procedure TIncludeFilesTests.CycleGivesOneIssue;
var
  Issues: TArray<TPreprocessorIssue>;
begin
  Files.Clear;
  Put('C:\P\A.inc', '{$I B.inc}');
  Put('C:\P\B.inc', '{$I A.inc}');
  TLspInactiveRegions.Ranges('unit Main;'#10'{$I A.inc}'#10'end.', nil, MainFile, Resolver(nil), Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual(Ord(TPreprocessorIssueKind.IncludeCycle), Ord(Issues[0].Kind));
  // Gemeldet an der $I-Direktive der Datei selbst, mit Ort in der .inc.
  Assert.AreEqual(1, Issues[0].Range.StartPos.Line);
  Assert.Contains(Issues[0].Message, 'B.inc, Zeile 1');
end;

procedure TIncludeFilesTests.WithoutResolverNoIssues;
var
  Issues: TArray<TPreprocessorIssue>;
begin
  TLspInactiveRegions.Ranges('unit Main;'#10'{$I Fehlt.inc}'#10'end.', nil, MainFile, nil, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

const
  // Unit mit drei Include-Dateien (#500): mit eigenem type, mitten im type-Abschnitt, Rumpf im implementation-Teil.
  HauptText =
    'unit Haupt;'#10 +
    'interface'#10 +
    '{$I Typen.inc}'#10 +
    'type'#10 +
    '  TListe = class'#10 +
    '  end;'#10 +
    '  {$I Mehr.inc}'#10 +
    'implementation'#10 +
    '{$I Rumpf.inc}'#10 +
    'end.';

procedure PutIncludes;
begin
  Files.Clear;
  Put('C:\P\Typen.inc', 'type'#10'  TKunde = class'#10'    procedure Speichern;'#10'  end;');
  Put('C:\P\Mehr.inc', 'TAuftrag = record'#10'  Nr: Integer;'#10'end;');
  Put('C:\P\Rumpf.inc', 'procedure TKunde.Speichern;'#10'begin'#10'end;');
end;

function FindSymbol(const AUnit: TUnitIndex; const AName, AContainer, AFile: string; out ASymbol: TIndexSymbol): Boolean;
var
  Symbol: TIndexSymbol;
begin
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Name, AName) and SameText(Symbol.Container, AContainer) and SameText(Symbol.FileName, AFile) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  Result := False;
end;

procedure TIncludeFilesTests.IndexesDeclarationsFromIncludes;
var
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  PutIncludes;
  UnitIndex := TIndexExtractor.ExtractText(HauptText, 'C:\P\Haupt.pas', nil, Resolver(nil));
  // Eigene Deklaration bleibt in der Unit.
  Assert.IsTrue(FindSymbol(UnitIndex, 'TListe', '', '', Symbol));
  Assert.AreEqual('', Symbol.FileName);
  Assert.AreEqual('C:\P\Haupt.pas', UnitIndex.SymbolFile(Symbol));
  // Aus Typen.inc: Ort in der .inc, sichtbar wie interface.
  Assert.IsTrue(FindSymbol(UnitIndex, 'TKunde', '', 'C:\P\Typen.inc', Symbol));
  Assert.AreEqual('C:\P\Typen.inc', Symbol.FileName);
  Assert.IsTrue(Symbol.InInterface);
  Assert.AreEqual(1, Symbol.SelectionRange.StartPos.Line);
  Assert.AreEqual(2, Symbol.SelectionRange.StartPos.Character);
  // Mehr.inc ohne eigenes type: Zeilen stimmen trotz vorangestelltem Schlüsselwort.
  Assert.IsTrue(FindSymbol(UnitIndex, 'TAuftrag', '', 'C:\P\Mehr.inc', Symbol));
  Assert.AreEqual('C:\P\Mehr.inc', Symbol.FileName);
  Assert.AreEqual(0, Symbol.SelectionRange.StartPos.Line);
  Assert.AreEqual(0, Symbol.SelectionRange.StartPos.Character);
  // Rumpf.inc im implementation-Teil.
  Assert.IsTrue(FindSymbol(UnitIndex, 'Speichern', 'TKunde', 'C:\P\Rumpf.inc', Symbol));
  Assert.AreEqual('C:\P\Rumpf.inc', Symbol.FileName);
  Assert.IsFalse(Symbol.InInterface);
  Assert.AreEqual(3, Integer(Length(UnitIndex.Includes)));
end;

procedure TIncludeFilesTests.IncludeCycleEndsWithoutDuplicates;
var
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Count: Integer;
begin
  Files.Clear;
  Put('C:\P\A.inc', 'const'#10'  WertA = 1;'#10'{$I B.inc}');
  Put('C:\P\B.inc', 'const'#10'  WertB = 2;'#10'{$I A.inc}');
  UnitIndex := TIndexExtractor.ExtractText('unit Main;'#10'interface'#10'{$I A.inc}'#10'implementation'#10'end.',
    MainFile, nil, Resolver(nil));
  Count := 0;
  for Symbol in UnitIndex.Symbols do
    if SameText(Symbol.Name, 'WertA') or SameText(Symbol.Name, 'WertB') then
      Inc(Count);
  Assert.AreEqual(2, Count);
end;

procedure TIncludeFilesTests.DefinitionAndCompletionReachIncludeFile;
const
  DritteText = 'unit Dritte;'#10'interface'#10'uses Haupt;'#10'var K: TKunde;'#10'implementation'#10'end.';
  TippText = 'unit Dritte;'#10'interface'#10'uses Haupt;'#10'var K: TKu'#10'implementation'#10'end.';
var
  Index: ISymbolIndex;
  Resolver_: TNameResolver;
  Tree: TSyntaxTree;
  Targets: TArray<TDefinitionTarget>;
  Items: TCompletionItems;
  Item: TCompletionItem;
  Found: Boolean;
begin
  PutIncludes;
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(HauptText, 'C:\P\Haupt.pas', nil, Resolver(nil)));
  Resolver_ := TNameResolver.Create(Index);
  try
    // Strg+Klick auf TKunde in einer dritten Unit springt in Typen.inc.
    Tree := TPascalParser.Parse(DritteText);
    try
      Targets := TLspDefinition.Targets(Resolver_, Index, Tree, 'C:\P\Dritte.pas', TTextPosition.Create(3, 8), False);
    finally
      Tree.Free;
    end;
    Assert.AreEqual(1, Integer(Length(Targets)));
    Assert.AreEqual('C:\P\Typen.inc', Targets[0].FileName);
    Assert.AreEqual(1, Targets[0].SelectionRange.StartPos.Line);
    // Vervollständigung bietet TKunde an, Details kommen aus der .inc.
    Tree := TPascalParser.Parse(TippText);
    try
      Items := TLspCompletion.Collect(Resolver_, Index, Tree, 'C:\P\Dritte.pas', TTextPosition.Create(3, 10));
    finally
      Tree.Free;
    end;
    Found := False;
    for Item in Items.Items do
      if Item.Name = 'TKunde' then
      begin
        Found := True;
        Assert.AreEqual('C:\P\Typen.inc', Item.SourceFile);
      end;
    Assert.IsTrue(Found, 'TKunde fehlt in der Vervollständigung');
  finally
    Resolver_.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIncludeFilesTests);

end.
