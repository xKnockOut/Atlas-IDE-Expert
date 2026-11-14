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
  Atlas.Common.Lsp.Completion.Lists,
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
  cMainFile = 'C:\P\Main.pas';

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
  mFileName: string;
begin
  Files.Clear;
  Put('C:\Lib\Shared.inc', '');
  Assert.IsTrue(TIncludeFiles.FindInclude('Shared.inc', cMainFile, ['C:\Lib'], Exists(), mFileName));
  Assert.AreEqual('C:\Lib\Shared.inc', mFileName);
  Put('C:\P\Shared.inc', '');
  Assert.IsTrue(TIncludeFiles.FindInclude('Shared.inc', cMainFile, ['C:\Lib'], Exists(), mFileName));
  Assert.AreEqual('C:\P\Shared.inc', mFileName, 'Ordner der Unit vor Suchpfad');
  Assert.IsFalse(TIncludeFiles.FindInclude('Fehlt.inc', cMainFile, ['C:\Lib'], Exists(), mFileName));
end;

procedure TIncludeFilesTests.AddsIncExtension;
var
  mFileName: string;
begin
  Files.Clear;
  Put('C:\P\Defines.inc', '');
  Assert.IsTrue(TIncludeFiles.FindInclude('Defines', cMainFile, nil, Exists(), mFileName));
  Assert.AreEqual('C:\P\Defines.inc', mFileName);
  // FindFile ($R, Strings) ergänzt keine Endung.
  Assert.IsFalse(TIncludeFiles.FindFile('Defines', 'C:\P', nil, Exists(), mFileName));
end;

procedure TIncludeFilesTests.QuotedNameWithSpaces;
var
  mFileName: string;
begin
  Files.Clear;
  Put('C:\P\Mit Leerzeichen.inc', '');
  Assert.IsTrue(TIncludeFiles.FindInclude('''Mit Leerzeichen.inc''', cMainFile, nil, Exists(), mFileName));
  Assert.AreEqual('C:\P\Mit Leerzeichen.inc', mFileName);
end;

procedure TIncludeFilesTests.SharedFileForLinksIndexAndInactive;
const
  cText = 'unit Main;'#10'{$I Defines.inc}'#10'interface'#10 +
    '{$IFDEF FEATURE}'#10'procedure MitFeature;'#10'{$ELSE}'#10'procedure OhneFeature;'#10'{$ENDIF}'#10 +
    'implementation'#10'end.';
var
  mUnitIndex: TUnitIndex;
  mSymbol: TIndexSymbol;
  mNames: string;
  mRanges: TArray<TTextRange>;
  mIssues: TArray<TPreprocessorIssue>;
  mLinks: TArray<TDocumentLink>;
begin
  Files.Clear;
  Put('C:\Lib\Defines.inc', '{$DEFINE FEATURE}');
  // Index
  mUnitIndex := TIndexExtractor.ExtractText(cText, cMainFile, nil, Resolver(['C:\Lib']));
  mNames := '';
  for mSymbol in mUnitIndex.Symbols do
  begin
    mNames := mNames + mSymbol.Name + ';';
  end;
  Assert.Contains(mNames, 'MitFeature');
  Assert.DoesNotContain(mNames, 'OhneFeature');
  Assert.AreEqual(1, Integer(Length(mUnitIndex.Includes)));
  Assert.AreEqual('C:\Lib\Defines.inc', mUnitIndex.Includes[0]);
  // Abblenden: nur der $ELSE-Zweig (Zeile 6) ist inaktiv.
  mRanges := TLspInactiveRegions.Ranges(cText, nil, cMainFile, Resolver(['C:\Lib']), mIssues);
  Assert.AreEqual(1, Integer(Length(mRanges)));
  Assert.IsTrue((mRanges[0].StartPos.Line <= 6) and (mRanges[0].EndPos.Line >= 6) and (mRanges[0].StartPos.Line >= 5));
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // Verweise: dieselbe Datei
  mLinks := TDocumentLinks.Find(cText, cMainFile, ['C:\Lib'], Exists());
  Assert.AreEqual(1, Integer(Length(mLinks)));
  Assert.AreEqual('C:\Lib\Defines.inc', mLinks[0].Target);
end;

procedure TIncludeFilesTests.MissingIncludeIsReported;
var
  mIssues: TArray<TPreprocessorIssue>;
begin
  Files.Clear;
  TLspInactiveRegions.Ranges('unit Main;'#10'{$I Fehlt.inc}'#10'end.', nil, cMainFile, Resolver(nil), mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual(Ord(TPreprocessorIssueKind.IncludeMissing), Ord(mIssues[0].Kind));
  Assert.AreEqual(1, mIssues[0].Range.StartPos.Line);
end;

procedure TIncludeFilesTests.CycleGivesOneIssue;
var
  mIssues: TArray<TPreprocessorIssue>;
begin
  Files.Clear;
  Put('C:\P\A.inc', '{$I B.inc}');
  Put('C:\P\B.inc', '{$I A.inc}');
  TLspInactiveRegions.Ranges('unit Main;'#10'{$I A.inc}'#10'end.', nil, cMainFile, Resolver(nil), mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual(Ord(TPreprocessorIssueKind.IncludeCycle), Ord(mIssues[0].Kind));
  // Gemeldet an der $I-Direktive der Datei selbst, mit Ort in der .inc.
  Assert.AreEqual(1, mIssues[0].Range.StartPos.Line);
  Assert.Contains(mIssues[0].Message, 'B.inc, Zeile 1');
end;

procedure TIncludeFilesTests.WithoutResolverNoIssues;
var
  mIssues: TArray<TPreprocessorIssue>;
begin
  TLspInactiveRegions.Ranges('unit Main;'#10'{$I Fehlt.inc}'#10'end.', nil, cMainFile, nil, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

const
  // Unit mit drei Include-Dateien (#500): mit eigenem type, mitten im type-Abschnitt, Rumpf im implementation-Teil.
  cHauptText =
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

function FindSymbol(const AUnit: TUnitIndex; const AName, AContainer, AFile: string;
  out ASymbol: TIndexSymbol): Boolean;
var
  mSymbol: TIndexSymbol;
begin
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Name, AName) and SameText(mSymbol.Container, AContainer) and
      SameText(mSymbol.FileName, AFile) then
    begin
      ASymbol := mSymbol;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TIncludeFilesTests.IndexesDeclarationsFromIncludes;
var
  mUnitIndex: TUnitIndex;
  mSymbol: TIndexSymbol;
begin
  PutIncludes;
  mUnitIndex := TIndexExtractor.ExtractText(cHauptText, 'C:\P\Haupt.pas', nil, Resolver(nil));
  // Eigene Deklaration bleibt in der Unit.
  Assert.IsTrue(FindSymbol(mUnitIndex, 'TListe', '', '', mSymbol));
  Assert.AreEqual('', mSymbol.FileName);
  Assert.AreEqual('C:\P\Haupt.pas', mUnitIndex.SymbolFile(mSymbol));
  // Aus Typen.inc: Ort in der .inc, sichtbar wie interface.
  Assert.IsTrue(FindSymbol(mUnitIndex, 'TKunde', '', 'C:\P\Typen.inc', mSymbol));
  Assert.AreEqual('C:\P\Typen.inc', mSymbol.FileName);
  Assert.IsTrue(mSymbol.InInterface);
  Assert.AreEqual(1, mSymbol.SelectionRange.StartPos.Line);
  Assert.AreEqual(2, mSymbol.SelectionRange.StartPos.Character);
  // Mehr.inc ohne eigenes type: Zeilen stimmen trotz vorangestelltem Schlüsselwort.
  Assert.IsTrue(FindSymbol(mUnitIndex, 'TAuftrag', '', 'C:\P\Mehr.inc', mSymbol));
  Assert.AreEqual('C:\P\Mehr.inc', mSymbol.FileName);
  Assert.AreEqual(0, mSymbol.SelectionRange.StartPos.Line);
  Assert.AreEqual(0, mSymbol.SelectionRange.StartPos.Character);
  // Rumpf.inc im implementation-Teil.
  Assert.IsTrue(FindSymbol(mUnitIndex, 'Speichern', 'TKunde', 'C:\P\Rumpf.inc', mSymbol));
  Assert.AreEqual('C:\P\Rumpf.inc', mSymbol.FileName);
  Assert.IsFalse(mSymbol.InInterface);
  Assert.AreEqual(3, Integer(Length(mUnitIndex.Includes)));
end;

procedure TIncludeFilesTests.IncludeCycleEndsWithoutDuplicates;
var
  mUnitIndex: TUnitIndex;
  mSymbol: TIndexSymbol;
  mCount: Integer;
begin
  Files.Clear;
  Put('C:\P\A.inc', 'const'#10'  WertA = 1;'#10'{$I B.inc}');
  Put('C:\P\B.inc', 'const'#10'  WertB = 2;'#10'{$I A.inc}');
  mUnitIndex := TIndexExtractor.ExtractText('unit Main;'#10'interface'#10'{$I A.inc}'#10'implementation'#10'end.',
    cMainFile, nil, Resolver(nil));
  mCount := 0;
  for mSymbol in mUnitIndex.Symbols do
  begin
    if SameText(mSymbol.Name, 'WertA') or SameText(mSymbol.Name, 'WertB') then
    begin
      Inc(mCount);
    end;
  end;
  Assert.AreEqual(2, mCount);
end;

procedure TIncludeFilesTests.DefinitionAndCompletionReachIncludeFile;
const
  cDritteText = 'unit Dritte;'#10'interface'#10'uses Haupt;'#10'var K: TKunde;'#10'implementation'#10'end.';
  cTippText = 'unit Dritte;'#10'interface'#10'uses Haupt;'#10'var K: TKu'#10'implementation'#10'end.';
var
  mIndex: ISymbolIndex;
  mResolver_: TNameResolver;
  mTree: TSyntaxTree;
  mTargets: TArray<TDefinitionTarget>;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mFound: Boolean;
begin
  PutIncludes;
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cHauptText, 'C:\P\Haupt.pas', nil, Resolver(nil)));
  mResolver_ := TNameResolver.Create(mIndex);
  try
    // Strg+Klick auf TKunde in einer dritten Unit springt in Typen.inc.
    mTree := TPascalParser.Parse(cDritteText);
    try
      mTargets := TLspDefinition.Targets(mResolver_, mIndex, mTree, 'C:\P\Dritte.pas', TTextPosition.Create(3, 8), False);
    finally
      mTree.Free;
    end;
    Assert.AreEqual(1, Integer(Length(mTargets)));
    Assert.AreEqual('C:\P\Typen.inc', mTargets[0].FileName);
    Assert.AreEqual(1, mTargets[0].SelectionRange.StartPos.Line);
    // Vervollständigung bietet TKunde an, Details kommen aus der .inc.
    mTree := TPascalParser.Parse(cTippText);
    try
      mItems := TCompletionLists.Collect(mResolver_, mIndex, mTree, 'C:\P\Dritte.pas', TTextPosition.Create(3, 10));
    finally
      mTree.Free;
    end;
    mFound := False;
    for mItem in mItems.Items do
    begin
      if mItem.Name = 'TKunde' then
      begin
        mFound := True;
        Assert.AreEqual('C:\P\Typen.inc', mItem.SourceFile);
      end;
    end;
    Assert.IsTrue(mFound, 'TKunde fehlt in der Vervollständigung');
  finally
    mResolver_.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TIncludeFilesTests);

end.
