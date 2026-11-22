unit Atlas.Common.Pascal.Destructors.Tests;

// Tests für Anweisungen im Destruktor (#666, #944) und im class destructor (#971).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalDestructorsTests = class
  public
    [Test]
    procedure StyleFromSetting;
    [Test]
    procedure StatementPerStyle;
    [Test]
    procedure ExistingDestructorBeforeInherited;
    [Test]
    procedure MissingDestructorAfterConstructor;
    [Test]
    procedure WithoutClassNothing;
    [Test]
    procedure MethodsAndConstructorsOfClass;
    [Test]
    procedure ClassDestructorIsCreatedOrFilled;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Destructors,
  Atlas.Tests.TextEdits,
  Atlas.Tests.SourceText;

const
  cWithDestructor =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKasse = class'#10 +
    '    FBeleg: TBeleg;'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TKasse.Create;'#10 +
    'begin'#10 +
    '  FBeleg := TBeleg.Create;'#10 +
    'end;'#10 +
    'destructor TKasse.Destroy;'#10 +
    'begin'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    'end.';
  cWithoutDestructor =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TKasse = class'#10 +
    '    FBeleg: TBeleg;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TKasse.Create;'#10 +
    'begin'#10 +
    '  FBeleg := TBeleg.Create;'#10 +
    'end;'#10 +
    'end.';

/// <summary>AStatements in den Destruktor von TKasse (Kopfzeile 3) und das Ergebnis.</summary>
function Freed(const AText: string; const AStatements: TArray<string>): string;
var
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Assert.IsTrue(TPascalDestructors.DestructorEdits(mTree, AText, 'TKasse', 3, AStatements, mEdits), AText);
  finally
    mTree.Free;
  end;
  Result := TTestEdits.Apply(AText, mEdits);
  Assert.IsTrue(TTestSource.Parses(Result), Result);
end;

procedure TPascalDestructorsTests.StyleFromSetting;
begin
  Assert.AreEqual(Ord(TFreeFieldsStyle.FreeAndNil), Ord(TPascalDestructors.StyleOf('freeAndNil')));
  Assert.AreEqual(Ord(TFreeFieldsStyle.Free), Ord(TPascalDestructors.StyleOf('free')));
  Assert.AreEqual(Ord(TFreeFieldsStyle.Free), Ord(TPascalDestructors.StyleOf('')));
end;

procedure TPascalDestructorsTests.StatementPerStyle;
begin
  Assert.AreEqual('FBeleg.Free;', TPascalDestructors.Statement('FBeleg', TFreeFieldsStyle.Free));
  Assert.AreEqual('FreeAndNil(FBeleg);', TPascalDestructors.Statement('FBeleg', TFreeFieldsStyle.FreeAndNil));
end;

procedure TPascalDestructorsTests.ExistingDestructorBeforeInherited;
var
  mResult: string;
begin
  mResult := Freed(cWithDestructor, ['FBeleg.Free;']);
  Assert.IsTrue(mResult.Contains('begin'#10'  FBeleg.Free;'#10'  inherited;'#10'end;'), mResult);
end;

procedure TPascalDestructorsTests.MissingDestructorAfterConstructor;
var
  mResult: string;
begin
  mResult := Freed(cWithoutDestructor, ['FreeAndNil(FBeleg);']);
  Assert.IsTrue(mResult.Contains('    destructor Destroy; override;'), mResult);
  Assert.IsTrue(mResult.Contains('destructor TKasse.Destroy;'#10'begin'#10'  FreeAndNil(FBeleg);'#10'  inherited;'),
    mResult);
end;

procedure TPascalDestructorsTests.WithoutClassNothing;
var
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  mTree := TPascalParser.Parse(cWithDestructor);
  try
    Assert.IsFalse(TPascalDestructors.DestructorEdits(mTree, cWithDestructor, 'TAndere', 3, ['FBeleg.Free;'],
      mEdits));
    Assert.IsFalse(TPascalDestructors.DestructorEdits(mTree, cWithDestructor, 'TKasse', 3, nil, mEdits));
    Assert.AreEqual(0, Integer(Length(mEdits)));
  finally
    mTree.Free;
  end;
end;

procedure TPascalDestructorsTests.MethodsAndConstructorsOfClass;
var
  mTree: TSyntaxTree;
  mMethods: TArray<TSyntaxNode>;
begin
  mTree := TPascalParser.Parse(cWithDestructor);
  try
    mMethods := TPascalDestructors.ClassMethods(mTree, 'TKasse');
    Assert.AreEqual(2, Integer(Length(mMethods)));
    Assert.IsTrue(TPascalDestructors.IsConstructor(cWithDestructor, mMethods[0]));
    Assert.IsFalse(TPascalDestructors.IsConstructor(cWithDestructor, mMethods[1]));
    Assert.AreEqual(0, Integer(Length(TPascalDestructors.ClassMethods(mTree, 'TAndere'))));
  finally
    mTree.Free;
  end;
end;

procedure TPascalDestructorsTests.ClassDestructorIsCreatedOrFilled;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TDienst<T> = class'#10'    class var FA: TListe;'#10 +
    '    class constructor Create;'#10'  end;'#10'implementation'#10'class constructor TDienst<T>.Create;'#10 +
    'begin'#10'  FA := TListe.Create;'#10'end;'#10'end.';
  cFilled = 'unit U;'#10'interface'#10'type'#10'  TDienst = class'#10'    class var FA: TListe;'#10 +
    '    class constructor Create;'#10'    class destructor Destroy;'#10'  end;'#10'implementation'#10 +
    'class constructor TDienst.Create;'#10'begin'#10'  FA := TListe.Create;'#10'end;'#10 +
    'class destructor TDienst.Destroy;'#10'begin'#10'  Protokolliere;'#10'end;'#10'end.';
var
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
  mDecl: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mDecl := mTree.Root.FindChild(TSyntaxKind.InterfaceSection)[0][0];
    Assert.IsTrue(TPascalDestructors.ClassDestructorEdits(mTree, cSource, mDecl, ['FreeAndNil(FA);'], mEdits));
    Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TDienst<T> = class'#10'    class var FA: TListe;'#10 +
      '    class constructor Create;'#10'    class destructor Destroy;'#10'  end;'#10'implementation'#10 +
      'class constructor TDienst<T>.Create;'#10'begin'#10'  FA := TListe.Create;'#10'end;'#10#10 +
      'class destructor TDienst<T>.Destroy;'#10'begin'#10'  FreeAndNil(FA);'#10'end;'#10'end.', TTestEdits.Apply(cSource, mEdits));
    Assert.IsTrue(TTestSource.Parses(TTestEdits.Apply(cSource, mEdits)));
  finally
    mTree.Free;
  end;
  mTree := TPascalParser.Parse(cFilled);
  try
    mDecl := mTree.Root.FindChild(TSyntaxKind.InterfaceSection)[0][0];
    Assert.IsTrue(TPascalDestructors.ClassDestructorEdits(mTree, cFilled, mDecl, ['FreeAndNil(FA);'], mEdits));
    Assert.AreEqual(1, Integer(Length(mEdits)));
    Assert.AreEqual(StringReplace(cFilled, '  Protokolliere;'#10, '  Protokolliere;'#10'  FreeAndNil(FA);'#10, []),
      TTestEdits.Apply(cFilled, mEdits));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalDestructorsTests);

end.
