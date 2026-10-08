unit BDLsp.Common.Editing.UnitFiles.Tests;

// Tests für Dateioperationen auf Units (#181).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnitFilesTests = class
  public
    [Test]
    procedure DerivesUnitNameFromPath;
    [Test]
    procedure BuildsSkeleton;
    [Test]
    procedure ReadsDottedHeader;
    [Test]
    procedure RenamesHeaderAndUses;
    [Test]
    procedure RenamesPathInProgramUses;
    [Test]
    procedure FindsReferences;
    [Test]
    procedure IgnoresContainsAsVariable;
    [Test]
    procedure RenamesDprojReference;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Editing.UnitFiles;

procedure TUnitFilesTests.DerivesUnitNameFromPath;
begin
  Assert.AreEqual('Data.Model', TUnitFiles.UnitNameOf('C:\App\Data.Model.pas'));
  Assert.AreEqual('Main', TUnitFiles.UnitNameOf('/src/Main.pas'));
  Assert.IsTrue(TUnitFiles.IsUnitFile('a\B.PAS'));
  Assert.IsFalse(TUnitFiles.IsUnitFile('a\B.dpr'));
end;

procedure TUnitFilesTests.BuildsSkeleton;
begin
  Assert.AreEqual('unit Neu;'#10#10'interface'#10#10'implementation'#10#10'end.'#10,
    TUnitFiles.Skeleton('Neu', #10));
end;

procedure TUnitFilesTests.ReadsDottedHeader;
var
  Name, Keyword: string;
  Range: TTextRange;
begin
  Assert.IsTrue(TUnitFiles.Header(TPascalLexer.Tokenize('// Kopf'#10'unit Data.Model;'#10'interface'), Name, Range,
    Keyword));
  Assert.AreEqual('Data.Model', Name);
  Assert.AreEqual('unit', Keyword);
  Assert.AreEqual(1, Range.StartPos.Line);
  Assert.AreEqual(5, Range.StartPos.Character);
  Assert.AreEqual(15, Range.EndPos.Character);
  Assert.IsFalse(TUnitFiles.Header(TPascalLexer.Tokenize('begin end.'), Name, Range, Keyword));
end;

procedure TUnitFilesTests.RenamesHeaderAndUses;
var
  Edits: TArray<TRuleEdit>;
begin
  Edits := TUnitFiles.RenameEdits(TPascalLexer.Tokenize(
    'unit Alt;'#10'interface'#10'uses Other, ALT;'#10'implementation'#10'uses Alt.Sub;'#10'end.'), 'Alt', 'Neu');
  Assert.AreEqual(2, Integer(Length(Edits)));
  Assert.AreEqual(0, Edits[0].Range.StartPos.Line);
  Assert.AreEqual(5, Edits[0].Range.StartPos.Character);
  Assert.AreEqual('Neu', Edits[0].NewText);
  Assert.AreEqual(2, Edits[1].Range.StartPos.Line);
  Assert.AreEqual(12, Edits[1].Range.StartPos.Character);
  Assert.AreEqual(15, Edits[1].Range.EndPos.Character);
end;

procedure TUnitFilesTests.RenamesPathInProgramUses;
var
  Edits: TArray<TRuleEdit>;
begin
  Edits := TUnitFiles.RenameEdits(TPascalLexer.Tokenize(
    'program App;'#10'uses'#10'  Forms,'#10'  Alt in ''Source\Alt.pas'' {Form1};'#10'begin'#10'end.'), 'Alt', 'Neu');
  Assert.AreEqual(2, Integer(Length(Edits)));
  Assert.AreEqual('Neu', Edits[0].NewText);
  Assert.AreEqual(3, Edits[1].Range.StartPos.Line);
  Assert.AreEqual(9, Edits[1].Range.StartPos.Character);
  Assert.AreEqual('''Source\Neu.pas''', Edits[1].NewText);
end;

procedure TUnitFilesTests.FindsReferences;
var
  Found: TArray<TTextRange>;
begin
  Found := TUnitFiles.References(TPascalLexer.Tokenize(
    'package P;'#10'requires rtl;'#10'contains'#10'  A.B in ''A.B.pas'','#10'  C;'#10'end.'), 'a.b');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(3, Found[0].StartPos.Line);
  Assert.AreEqual(2, Found[0].StartPos.Character);
  Assert.AreEqual(5, Found[0].EndPos.Character);
end;

procedure TUnitFilesTests.IgnoresContainsAsVariable;
begin
  Assert.AreEqual(0, Integer(Length(TUnitFiles.References(TPascalLexer.Tokenize(
    'unit U;'#10'implementation'#10'begin'#10'  X := contains + A;'#10'end.'), 'A'))));
end;

procedure TUnitFilesTests.RenamesDprojReference;
var
  Edits: TArray<TRuleEdit>;
begin
  Edits := TUnitFiles.ProjectFileEdits(
    '<Project>'#13#10'  <DCCReference Include="Source\Alt.pas"/>'#13#10'  <DCCReference Include="Other.pas"/>',
    'C:\App\Source\Alt.pas', 'C:\App\Source\Neu.pas');
  Assert.AreEqual(1, Integer(Length(Edits)));
  Assert.AreEqual(1, Edits[0].Range.StartPos.Line);
  Assert.AreEqual(32, Edits[0].Range.StartPos.Character);
  Assert.AreEqual(39, Edits[0].Range.EndPos.Character);
  Assert.AreEqual('Neu.pas', Edits[0].NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitFilesTests);

end.
