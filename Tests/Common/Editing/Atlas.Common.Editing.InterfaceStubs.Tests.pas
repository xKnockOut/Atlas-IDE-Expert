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
  mStub: TInterfaceStub;
begin
  Assert.IsTrue(TInterfaceStubs.Make('IExporter', 'TJsonExporter',
    'procedure Export(const AFileName: string; ACount: Integer = 1);', #10, mStub));
  Assert.AreEqual('IExporter', mStub.InterfaceName);
  Assert.AreEqual('Export', mStub.Name);
  Assert.AreEqual('procedure Export(const AFileName: string; ACount: Integer = 1);', mStub.Declaration);
  // Standardwerte nur in der Deklaration; Prozeduren mit leerer Zeile, ohne inherited.
  Assert.AreEqual('procedure TJsonExporter.Export(const AFileName: string; ACount: Integer);'#10'begin'#10#10'end;',
    mStub.Body);
  // Aufrufkonvention und overload bleiben, andere Direktiven nicht.
  Assert.IsTrue(TInterfaceStubs.Make('IExporter', 'TJsonExporter', 'function GetName: string; stdcall; overload;',
    #10, mStub));
  Assert.AreEqual('GetName', mStub.Name);
  Assert.AreEqual('function GetName: string; overload; stdcall;', mStub.Declaration);
  Assert.AreEqual('function TJsonExporter.GetName: string;'#10'begin'#10'  Result := Default(string);'#10'end;',
    mStub.Body);
  Assert.IsTrue(TInterfaceStubs.Make('IListe', 'TListe', 'function Find<T>(const AName: string): T;', #10, mStub));
  Assert.AreEqual('Find', mStub.Name);
  Assert.IsFalse(TInterfaceStubs.Make('IExporter', 'TJsonExporter', 'property Name: string read GetName;', #10,
    mStub));
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
  cSource =
    'type'#10 +
    '  TJsonExporter = class(TInterfacedObject, IExporter)'#10 +
    '  strict private'#10 +
    '    FName: string;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10;
begin
  Assert.AreEqual('public', TInterfaceStubs.LastSection(TPascalLexer.Tokenize(cSource), 1, 6));
  Assert.AreEqual('strict private', TInterfaceStubs.LastSection(TPascalLexer.Tokenize(cSource), 1, 4));
  Assert.AreEqual('', TInterfaceStubs.LastSection(TPascalLexer.Tokenize(cSource), 1, 2));
end;

procedure TInterfaceStubsTests.MergesInsertions;
var
  mExport_, mName, mFlush: TInterfaceStub;
  mEdits, mMerged: TArray<TRuleEdit>;
begin
  TInterfaceStubs.Make('IExporter', 'TJsonExporter', 'procedure Export;', #10, mExport_);
  TInterfaceStubs.Make('IExporter', 'TJsonExporter', 'function GetName: string;', #10, mName);
  TInterfaceStubs.Make('IFlush', 'TJsonExporter', 'procedure Flush;', #10, mFlush);
  mEdits := TInterfaceStubs.ClassEdits(mExport_, 6, '  ', 'public', True, #10);
  Assert.AreEqual(3, Integer(Length(mEdits)));
  mEdits := mEdits + TInterfaceStubs.ClassEdits(mName, 6, '  ', 'public', True, #10);
  mEdits := mEdits + [TRuleEdit.Create(TTextRange.Create(9, 0, 9, 0), 'Rumpf')];
  mEdits := mEdits + TInterfaceStubs.ClassEdits(mFlush, 6, '  ', 'public', True, #10);
  mMerged := TInterfaceStubs.Merge(mEdits);
  Assert.AreEqual(2, Integer(Length(mMerged)));
  Assert.AreEqual(
    '  public'#10 +
    '    { IExporter }'#10 +
    '    procedure Export;'#10 +
    '    function GetName: string;'#10 +
    '    { IFlush }'#10 +
    '    procedure Flush;'#10, mMerged[0].NewText);
  Assert.AreEqual(6, mMerged[0].Range.StartPos.Line);
  Assert.AreEqual('Rumpf', mMerged[1].NewText);
  // Ohne Abschnitt, wenn der letzte schon passt.
  Assert.AreEqual(2, Integer(Length(TInterfaceStubs.ClassEdits(mFlush, 6, '  ', 'public', False, #10))));
end;

end.
