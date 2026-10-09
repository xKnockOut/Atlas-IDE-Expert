unit Argus.Common.Pascal.IncludeFiles.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Common.Documents.Contract,
  Argus.Common.Pascal.Preprocessor,
  Argus.Common.Pascal.IncludeFiles,
  Argus.Common.Index.Contract,
  Argus.Common.Index.Extractor,
  Argus.Common.Editing.DocumentLinks,
  Argus.Common.Lsp.InactiveRegions;

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

initialization
  TDUnitX.RegisterTestFixture(TIncludeFilesTests);

end.
