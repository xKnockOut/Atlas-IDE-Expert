unit Atlas.Common.Editing.InterfaceStubs.Tests;

// Tests für das Anlegen fehlender Interface-Methoden (#466), Teil ohne Namensauflösung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInterfaceStubsTests = class
  public
    [Test]
    procedure MakesDeclarationAndBody;
    [Test]
    procedure FindsReturnType;
    [Test]
    procedure FindsLastSection;
    [Test]
    procedure MergesInsertions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.InterfaceStubs;

procedure TInterfaceStubsTests.MakesDeclarationAndBody;
var
  Stub: TInterfaceStub;
begin
  Assert.IsTrue(TInterfaceStubs.Make('IExporter', 'TJsonExporter',
    'procedure Export(const AFileName: string; ACount: Integer = 1);', #10, Stub));
  Assert.AreEqual('IExporter', Stub.InterfaceName);
  Assert.AreEqual('Export', Stub.Name);
  Assert.AreEqual('procedure Export(const AFileName: string; ACount: Integer = 1);', Stub.Declaration);
  // Standardwerte nur in der Deklaration; Prozeduren mit leerer Zeile, ohne inherited.
  Assert.AreEqual('procedure TJsonExporter.Export(const AFileName: string; ACount: Integer);'#10'begin'#10#10'end;',
    Stub.Body);
  // Aufrufkonvention und overload bleiben, andere Direktiven nicht.
  Assert.IsTrue(TInterfaceStubs.Make('IExporter', 'TJsonExporter', 'function GetName: string; stdcall; overload;',
    #10, Stub));
  Assert.AreEqual('GetName', Stub.Name);
  Assert.AreEqual('function GetName: string; overload; stdcall;', Stub.Declaration);
  Assert.AreEqual('function TJsonExporter.GetName: string;'#10'begin'#10'  Result := Default(string);'#10'end;',
    Stub.Body);
  Assert.IsTrue(TInterfaceStubs.Make('IListe', 'TListe', 'function Find<T>(const AName: string): T;', #10, Stub));
  Assert.AreEqual('Find', Stub.Name);
  Assert.IsFalse(TInterfaceStubs.Make('IExporter', 'TJsonExporter', 'property Name: string read GetName;', #10,
    Stub));
end;

procedure TInterfaceStubsTests.FindsReturnType;
begin
  Assert.AreEqual('', TInterfaceStubs.ReturnType('Export(const A: string)'));
  Assert.AreEqual('string', TInterfaceStubs.ReturnType('GetName: string'));
  Assert.AreEqual('TList<string>', TInterfaceStubs.ReturnType('Items(AIndex: Integer): TList<string>'));
  Assert.AreEqual('T', TInterfaceStubs.ReturnType('Find<T: class>(const A: string): T'));
end;

procedure TInterfaceStubsTests.FindsLastSection;
const
  Source =
    'type'#10 +
    '  TJsonExporter = class(TInterfacedObject, IExporter)'#10 +
    '  strict private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10;
begin
  Assert.AreEqual('public', TInterfaceStubs.LastSection(TPascalLexer.Tokenize(Source), 1, 6));
  Assert.AreEqual('strict private', TInterfaceStubs.LastSection(TPascalLexer.Tokenize(Source), 1, 4));
  Assert.AreEqual('', TInterfaceStubs.LastSection(TPascalLexer.Tokenize(Source), 1, 2));
end;

procedure TInterfaceStubsTests.MergesInsertions;
var
  Export_, Name, Flush: TInterfaceStub;
  Edits, Merged: TArray<TRuleEdit>;
begin
  TInterfaceStubs.Make('IExporter', 'TJsonExporter', 'procedure Export;', #10, Export_);
  TInterfaceStubs.Make('IExporter', 'TJsonExporter', 'function GetName: string;', #10, Name);
  TInterfaceStubs.Make('IFlush', 'TJsonExporter', 'procedure Flush;', #10, Flush);
  Edits := TInterfaceStubs.ClassEdits(Export_, 6, '  ', 'public', True, #10);
  Assert.AreEqual(3, Integer(Length(Edits)));
  Edits := Edits + TInterfaceStubs.ClassEdits(Name, 6, '  ', 'public', True, #10);
  Edits := Edits + [TRuleEdit.Create(TTextRange.Create(9, 0, 9, 0), 'Rumpf')];
  Edits := Edits + TInterfaceStubs.ClassEdits(Flush, 6, '  ', 'public', True, #10);
  Merged := TInterfaceStubs.Merge(Edits);
  Assert.AreEqual(2, Integer(Length(Merged)));
  Assert.AreEqual(
    '  public'#10 +
    '    { IExporter }'#10 +
    '    procedure Export;'#10 +
    '    function GetName: string;'#10 +
    '    { IFlush }'#10 +
    '    procedure Flush;'#10, Merged[0].NewText);
  Assert.AreEqual(6, Merged[0].Range.StartPos.Line);
  Assert.AreEqual('Rumpf', Merged[1].NewText);
  // Ohne Abschnitt, wenn der letzte schon passt.
  Assert.AreEqual(2, Integer(Length(TInterfaceStubs.ClassEdits(Flush, 6, '  ', 'public', False, #10))));
end;

end.
