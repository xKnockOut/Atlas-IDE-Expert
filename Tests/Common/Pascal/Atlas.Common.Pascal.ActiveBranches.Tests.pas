unit Atlas.Common.Pascal.ActiveBranches.Tests;

// Tests für den Editor-Baum aus den aktiven {$IFDEF}-Zweigen (#845). Die Quellen
// sind die nachgestellten Fälle aus planung/parser-luecken-faelle (01, 02, 03,
// 10, 11): Mit dem Vollbaum fehlten Routinen nach dem {$ENDIF}, wurden zu
// verschachtelten Routinen oder Vorfahren zu Feldern.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TActiveBranchesTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TwoBodies;
    [Test]
    procedure AncestorByCondition;
    [Test]
    procedure TwoHeadersOneBody;
    [Test]
    procedure AsmOrPascalBody;
    [Test]
    procedure UsesPerPlatform;
    [Test]
    procedure TokensAndPositionsStay;
    [Test]
    procedure DefinesChangeRebuildsTree;
    [Test]
    procedure TextWithoutConditionalsKeepsTree;
    [Test]
    procedure GetAllSeesEveryBranch;
    [Test]
    procedure ConditionalsOfTheFile;
    [Test]
    procedure ActiveDiagnosticsMatchTree;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.TextDocument,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache;

const
  CaseBodies =
    'unit U1;'#10'interface'#10'function Foo: Integer;'#10'procedure Bar;'#10'implementation'#10 +
    'function Foo: Integer;'#10'{$IFDEF MSWINDOWS}'#10'begin'#10'  Result := 1;'#10'end;'#10'{$ELSE}'#10 +
    'begin'#10'  Result := 2;'#10'end;'#10'{$ENDIF}'#10'procedure Bar;'#10'begin'#10'end;'#10'end.';
  CaseAncestor =
    'unit U2;'#10'interface'#10'type'#10'  TFoo = class({$IFDEF X}TBaseA{$ELSE}TBaseB{$ENDIF})'#10 +
    '  public'#10'    procedure A;'#10'  end;'#10'implementation'#10'procedure TFoo.A;'#10'begin'#10'end;'#10'end.';
  CaseHeader =
    'unit U3;'#10'interface'#10'implementation'#10'{$IFDEF X}'#10'procedure Foo(A: Integer);'#10'{$ELSE}'#10 +
    'procedure Foo(A: Int64);'#10'{$ENDIF}'#10'begin'#10'end;'#10'procedure Bar;'#10'begin'#10'end;'#10'end.';
  CaseAsm =
    'unit U10;'#10'interface'#10'implementation'#10'function Swap32(V: Cardinal): Cardinal;'#10'{$IFDEF CPUX86}'#10 +
    'asm'#10'  BSWAP EAX'#10'end;'#10'{$ELSE}'#10'begin'#10'  Result := V;'#10'end;'#10'{$ENDIF}'#10 +
    'procedure After;'#10'begin'#10'end;'#10'end.';
  CaseUses =
    'unit U11;'#10'interface'#10'uses'#10'  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}'#10 +
    '  {$IFDEF POSIX}Posix.Unistd,{$ENDIF}'#10'  System.SysUtils;'#10'type'#10'  TA = class end;'#10 +
    'implementation'#10'end.';

var
  // Symbole, die der Provider in diesen Tests meldet.
  ProjectDefines: TArray<string>;

function NewDocument(const AText: string; AVersion: Integer = 1): ITextDocument;
begin
  Result := TTextDocument.Create('file:///c:/u.pas', 'objectpascal', AVersion, AText);
end;

procedure UseDefines(const ADefines: TArray<string>);
begin
  ProjectDefines := ADefines;
  TSyntaxTreeCache.SetDefinesProvider(
    function(const AUri: string; out ADefines: TArray<string>): Boolean
    begin
      ADefines := ProjectDefines;
      Result := True;
    end);
end;

/// <summary>Units, Typen, Vorfahren, Felder und Routinen in Baumreihenfolge; ">" je umschließende
/// Routine, "init" für einen initialization-Abschnitt.</summary>
function Outline(ATree: TSyntaxTree): string;
var
  Parts: string;
begin
  Parts := '';
  ATree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      Prefix: string;
      Outer: TSyntaxNode;
    begin
      Result := True;
      Prefix := '';
      Outer := ANode.Parent;
      while Outer <> nil do
      begin
        if Outer.Kind = TSyntaxKind.RoutineDecl then
          Prefix := Prefix + '>';
        Outer := Outer.Parent;
      end;
      case ANode.Kind of
        TSyntaxKind.UsedUnit, TSyntaxKind.TypeDecl, TSyntaxKind.Field, TSyntaxKind.RoutineDecl:
          Parts := Parts + ' ' + Prefix + ANode.Name;
        TSyntaxKind.TypeReference:
          if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.ClassType) then
            Parts := Parts + ' (' + ANode.Name + ')';
        TSyntaxKind.InitializationSection:
          Parts := Parts + ' init';
      else
        // Übrige Arten: nichts zu tun.
      end;
    end);
  Result := Trim(Parts);
end;

function ActiveOutline(const AText: string; const ADefines: TArray<string>): string;
var
  Shared: ISharedSyntaxTree;
begin
  UseDefines(ADefines);
  Shared := TSyntaxTreeCache.Get(NewDocument(AText));
  Result := Outline(Shared.Tree);
  Assert.AreEqual(0, Integer(Length(Shared.Tree.Diagnostics)), 'Syntaxfehler im aktiven Baum');
end;

procedure TActiveBranchesTests.TearDown;
begin
  TSyntaxTreeCache.SetDefinesProvider(nil);
  ProjectDefines := nil;
end;

procedure TActiveBranchesTests.TwoBodies;
begin
  // Fall 01: Der Rumpf von Bar steht hinter dem {$ENDIF}, kein initialization (Vollbaum: "… Foo init").
  Assert.AreEqual('Foo Bar Foo Bar', ActiveOutline(CaseBodies, ['MSWINDOWS']));
  Assert.AreEqual('Foo Bar Foo Bar', ActiveOutline(CaseBodies, ['LINUX']));
end;

procedure TActiveBranchesTests.AncestorByCondition;
begin
  // Fall 02: genau ein Vorfahr, kein Feld „TBaseB“.
  Assert.AreEqual('TFoo (TBaseA) TFoo.A', ActiveOutline(CaseAncestor, ['X']));
  Assert.AreEqual('TFoo (TBaseB) TFoo.A', ActiveOutline(CaseAncestor, ['MSWINDOWS']));
end;

procedure TActiveBranchesTests.TwoHeadersOneBody;
var
  Shared: ISharedSyntaxTree;
  Header: TSyntaxNode;
begin
  // Fall 03: eine Fassung von Foo, Bar nicht darin verschachtelt.
  Assert.AreEqual('Foo Bar', ActiveOutline(CaseHeader, ['X']));
  UseDefines(['MSWINDOWS']);
  Shared := TSyntaxTreeCache.Get(NewDocument(CaseHeader));
  Header := Shared.Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl)
    .FindChild(TSyntaxKind.RoutineHeader);
  Assert.AreEqual(6, Header.StartPos.Line, 'Kopf aus dem {$ELSE}-Zweig');
end;

procedure TActiveBranchesTests.AsmOrPascalBody;
var
  Shared: ISharedSyntaxTree;
  Routine: TSyntaxNode;
begin
  // Fall 10: asm-Rumpf unter Win32, Pascal-Rumpf sonst; After ist immer da.
  Assert.AreEqual('Swap32 After', ActiveOutline(CaseAsm, ['CPUX86']));
  Assert.AreEqual('Swap32 After', ActiveOutline(CaseAsm, ['CPUX64']));
  UseDefines(['CPUX86']);
  Shared := TSyntaxTreeCache.Get(NewDocument(CaseAsm));
  Routine := Shared.Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl);
  Assert.IsNotNull(Routine.FindChild(TSyntaxKind.AsmBlock));
  Assert.IsNull(Routine.FindChild(TSyntaxKind.Block));
end;

procedure TActiveBranchesTests.UsesPerPlatform;
begin
  // Fall 11: nur die Units der Plattform.
  Assert.AreEqual('Winapi.Windows System.SysUtils TA', ActiveOutline(CaseUses, ['MSWINDOWS']));
  Assert.AreEqual('Posix.Unistd System.SysUtils TA', ActiveOutline(CaseUses, ['POSIX', 'LINUX']));
end;

procedure TActiveBranchesTests.TokensAndPositionsStay;
var
  Shared: ISharedSyntaxTree;
  Full: TSyntaxTree;
  Bar: TSyntaxNode;
begin
  // Die Token der inaktiven Zweige bleiben, Positionen stimmen mit dem Text.
  UseDefines(['MSWINDOWS']);
  Shared := TSyntaxTreeCache.Get(NewDocument(CaseBodies));
  Full := TSyntaxTreeCache.Parse(CaseBodies);
  try
    Assert.AreEqual(Integer(Length(Full.Tokens)), Integer(Length(Shared.Tree.Tokens)));
  finally
    Full.Free;
  end;
  Bar := Shared.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  Bar := Bar[Bar.ChildCount - 1];
  Assert.AreEqual('Bar', Bar.Name);
  Assert.AreEqual(15, Bar.StartPos.Line);
  Assert.AreEqual('procedure Bar;', Copy(CaseBodies, Bar.StartOffset + 1, Length('procedure Bar;')));
end;

procedure TActiveBranchesTests.DefinesChangeRebuildsTree;
var
  Document: ITextDocument;
  Before: Integer;
  Win32, Again, Win64: ISharedSyntaxTree;
begin
  // Plattformwechsel Win32 → Win64: neuer Baum; derselbe Stand: derselbe Baum.
  Document := NewDocument(CaseAsm);
  UseDefines(TPascalPreprocessor.PredefinedSymbols('Win32', 37.0));
  Before := TSyntaxTreeCache.ParseCount;
  Win32 := TSyntaxTreeCache.Get(Document);
  Again := TSyntaxTreeCache.Get(Document);
  Assert.IsTrue(Win32.Tree = Again.Tree);
  UseDefines(TPascalPreprocessor.PredefinedSymbols('Win64', 37.0));
  Win64 := TSyntaxTreeCache.Get(Document);
  Assert.IsFalse(Win32.Tree = Win64.Tree);
  Assert.AreEqual(2, TSyntaxTreeCache.ParseCount - Before);
  Assert.IsNotNull(Win32.Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl)
    .FindChild(TSyntaxKind.AsmBlock));
  Assert.IsNotNull(Win64.Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl)
    .FindChild(TSyntaxKind.Block));
end;

procedure TActiveBranchesTests.TextWithoutConditionalsKeepsTree;
var
  Document: ITextDocument;
  First, Second: ISharedSyntaxTree;
begin
  // Ohne bedingte Direktive ändert ein Plattformwechsel nichts: kein neuer Parse.
  Document := NewDocument('unit A;'#10'interface'#10'implementation'#10'end.');
  UseDefines(['WIN32']);
  First := TSyntaxTreeCache.Get(Document);
  UseDefines(['WIN64']);
  Second := TSyntaxTreeCache.Get(Document);
  Assert.IsTrue(First.Tree = Second.Tree);
  Assert.AreEqual(0, Integer(Length(First.Conditionals)));
end;

procedure TActiveBranchesTests.GetAllSeesEveryBranch;
var
  Document: ITextDocument;
  All: ISharedSyntaxTree;
begin
  Document := NewDocument(CaseUses);
  UseDefines(['MSWINDOWS']);
  All := TSyntaxTreeCache.GetAll(Document);
  Assert.AreEqual('Winapi.Windows Posix.Unistd System.SysUtils TA', Outline(All.Tree));
  Assert.IsFalse(All.Tree = TSyntaxTreeCache.Get(Document).Tree);
  Assert.IsTrue(All.Tree = TSyntaxTreeCache.GetAll(Document).Tree);
end;

procedure TActiveBranchesTests.ConditionalsOfTheFile;
var
  Shared: ISharedSyntaxTree;
  Conditional: TConditionalRange;
  Active: string;
begin
  UseDefines(['MSWINDOWS']);
  Shared := TSyntaxTreeCache.Get(NewDocument(CaseBodies));
  Active := '';
  for Conditional in Shared.Conditionals do
    if Conditional.Active then
      Active := Active + Conditional.Condition + ' ' + IntToStr(Conditional.Range.StartPos.Line);
  Assert.AreEqual('MSWINDOWS 6', Active);
  Assert.AreEqual(2, Integer(Length(Shared.Conditionals)));
end;

procedure TActiveBranchesTests.ActiveDiagnosticsMatchTree;
var
  Diagnostics: TArray<TSyntaxDiagnostic>;
  Tree: TSyntaxTree;
begin
  // Ohne Projekt gelten die Vordefinitionen (Win32): derselbe Zweig wie in ActiveDiagnostics.
  Assert.IsTrue(TPascalParser.ActiveDiagnostics(CaseAsm, nil, Diagnostics));
  Assert.AreEqual(0, Integer(Length(Diagnostics)));
  Tree := TPascalParser.ParseActive(CaseAsm, nil);
  try
    Assert.IsNotNull(Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl)
      .FindChild(TSyntaxKind.AsmBlock));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TActiveBranchesTests);

end.
