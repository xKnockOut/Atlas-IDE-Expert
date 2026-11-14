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
  cCaseBodies =
    'unit U1;'#10'interface'#10'function Foo: Integer;'#10'procedure Bar;'#10'implementation'#10 +
    'function Foo: Integer;'#10'{$IFDEF MSWINDOWS}'#10'begin'#10'  Result := 1;'#10'end;'#10'{$ELSE}'#10 +
    'begin'#10'  Result := 2;'#10'end;'#10'{$ENDIF}'#10'procedure Bar;'#10'begin'#10'end;'#10'end.';
  cCaseAncestor =
    'unit U2;'#10'interface'#10'type'#10'  TFoo = class({$IFDEF X}TBaseA{$ELSE}TBaseB{$ENDIF})'#10 +
    '  public'#10'    procedure A;'#10'  end;'#10'implementation'#10'procedure TFoo.A;'#10'begin'#10'end;'#10'end.';
  cCaseHeader =
    'unit U3;'#10'interface'#10'implementation'#10'{$IFDEF X}'#10'procedure Foo(A: Integer);'#10'{$ELSE}'#10 +
    'procedure Foo(A: Int64);'#10'{$ENDIF}'#10'begin'#10'end;'#10'procedure Bar;'#10'begin'#10'end;'#10'end.';
  cCaseAsm =
    'unit U10;'#10'interface'#10'implementation'#10'function Swap32(V: Cardinal): Cardinal;'#10'{$IFDEF CPUX86}'#10 +
    'asm'#10'  BSWAP EAX'#10'end;'#10'{$ELSE}'#10'begin'#10'  Result := V;'#10'end;'#10'{$ENDIF}'#10 +
    'procedure After;'#10'begin'#10'end;'#10'end.';
  cCaseUses =
    'unit U11;'#10'interface'#10'uses'#10'  {$IFDEF MSWINDOWS}Winapi.Windows,{$ENDIF}'#10 +
    '  {$IFDEF POSIX}Posix.Unistd,{$ENDIF}'#10'  System.SysUtils;'#10'type'#10'  TA = class end;'#10 +
    'implementation'#10'end.';

var
  // Symbole, die der Provider in diesen Tests meldet.
  ProjectDefines: TArray<string>;

function NewDocument(const AText: string; AVersion: Integer): ITextDocument; overload;
begin
  Result := TTextDocument.Create('file:///c:/u.pas', 'objectpascal', AVersion, AText);
end;

function NewDocument(const AText: string): ITextDocument; overload;
begin
  Result := NewDocument(AText, 1);
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
  mParts: string;
begin
  mParts := '';
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
        begin
          Prefix := Prefix + '>';
        end;
        Outer := Outer.Parent;
      end;
      case ANode.Kind of
        TSyntaxKind.UsedUnit, TSyntaxKind.TypeDecl, TSyntaxKind.Field, TSyntaxKind.RoutineDecl:
          mParts := mParts + ' ' + Prefix + ANode.Name;
        TSyntaxKind.TypeReference:
          if (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.ClassType) then
          begin
            mParts := mParts + ' (' + ANode.Name + ')';
          end;
        TSyntaxKind.InitializationSection:
          mParts := mParts + ' init';
      else
        // Übrige Arten: nichts zu tun.
      end;
    end);
  Result := Trim(mParts);
end;

function ActiveOutline(const AText: string; const ADefines: TArray<string>): string;
var
  mShared: ISharedSyntaxTree;
begin
  UseDefines(ADefines);
  mShared := TSyntaxTreeCache.Get(NewDocument(AText));
  Result := Outline(mShared.Tree);
  Assert.AreEqual(0, Integer(Length(mShared.Tree.Diagnostics)), 'Syntaxfehler im aktiven Baum');
end;

procedure TActiveBranchesTests.TearDown;
begin
  TSyntaxTreeCache.SetDefinesProvider(nil);
  ProjectDefines := nil;
end;

procedure TActiveBranchesTests.TwoBodies;
begin
  // Fall 01: Der Rumpf von Bar steht hinter dem {$ENDIF}, kein initialization (Vollbaum: "… Foo init").
  Assert.AreEqual('Foo Bar Foo Bar', ActiveOutline(cCaseBodies, ['MSWINDOWS']));
  Assert.AreEqual('Foo Bar Foo Bar', ActiveOutline(cCaseBodies, ['LINUX']));
end;

procedure TActiveBranchesTests.AncestorByCondition;
begin
  // Fall 02: genau ein Vorfahr, kein Feld „TBaseB“.
  Assert.AreEqual('TFoo (TBaseA) TFoo.A', ActiveOutline(cCaseAncestor, ['X']));
  Assert.AreEqual('TFoo (TBaseB) TFoo.A', ActiveOutline(cCaseAncestor, ['MSWINDOWS']));
end;

procedure TActiveBranchesTests.TwoHeadersOneBody;
var
  mShared: ISharedSyntaxTree;
  mHeader: TSyntaxNode;
begin
  // Fall 03: eine Fassung von Foo, Bar nicht darin verschachtelt.
  Assert.AreEqual('Foo Bar', ActiveOutline(cCaseHeader, ['X']));
  UseDefines(['MSWINDOWS']);
  mShared := TSyntaxTreeCache.Get(NewDocument(cCaseHeader));
  mHeader := mShared.Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl)
    .FindChild(TSyntaxKind.RoutineHeader);
  Assert.AreEqual(6, mHeader.StartPos.Line, 'Kopf aus dem {$ELSE}-Zweig');
end;

procedure TActiveBranchesTests.AsmOrPascalBody;
var
  mShared: ISharedSyntaxTree;
  mRoutine: TSyntaxNode;
begin
  // Fall 10: asm-Rumpf unter Win32, Pascal-Rumpf sonst; After ist immer da.
  Assert.AreEqual('Swap32 After', ActiveOutline(cCaseAsm, ['CPUX86']));
  Assert.AreEqual('Swap32 After', ActiveOutline(cCaseAsm, ['CPUX64']));
  UseDefines(['CPUX86']);
  mShared := TSyntaxTreeCache.Get(NewDocument(cCaseAsm));
  mRoutine := mShared.Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl);
  Assert.IsNotNull(mRoutine.FindChild(TSyntaxKind.AsmBlock));
  Assert.IsNull(mRoutine.FindChild(TSyntaxKind.Block));
end;

procedure TActiveBranchesTests.UsesPerPlatform;
begin
  // Fall 11: nur die Units der Plattform.
  Assert.AreEqual('Winapi.Windows System.SysUtils TA', ActiveOutline(cCaseUses, ['MSWINDOWS']));
  Assert.AreEqual('Posix.Unistd System.SysUtils TA', ActiveOutline(cCaseUses, ['POSIX', 'LINUX']));
end;

procedure TActiveBranchesTests.TokensAndPositionsStay;
var
  mShared: ISharedSyntaxTree;
  mFull: TSyntaxTree;
  mBar: TSyntaxNode;
begin
  // Die Token der inaktiven Zweige bleiben, Positionen stimmen mit dem Text.
  UseDefines(['MSWINDOWS']);
  mShared := TSyntaxTreeCache.Get(NewDocument(cCaseBodies));
  mFull := TSyntaxTreeCache.Parse(cCaseBodies);
  try
    Assert.AreEqual(Integer(Length(mFull.Tokens)), Integer(Length(mShared.Tree.Tokens)));
  finally
    mFull.Free;
  end;
  mBar := mShared.Tree.Root.FindChild(TSyntaxKind.ImplementationSection);
  mBar := mBar[mBar.ChildCount - 1];
  Assert.AreEqual('Bar', mBar.Name);
  Assert.AreEqual(15, mBar.StartPos.Line);
  Assert.AreEqual('procedure Bar;', Copy(cCaseBodies, mBar.StartOffset + 1, Length('procedure Bar;')));
end;

procedure TActiveBranchesTests.DefinesChangeRebuildsTree;
var
  mDocument: ITextDocument;
  mBefore: Integer;
  mWin32, mAgain, mWin64: ISharedSyntaxTree;
begin
  // Plattformwechsel Win32 → Win64: neuer Baum; derselbe Stand: derselbe Baum.
  mDocument := NewDocument(cCaseAsm);
  UseDefines(TPascalPreprocessor.PredefinedSymbols('Win32', 37.0));
  mBefore := TSyntaxTreeCache.ParseCount;
  mWin32 := TSyntaxTreeCache.Get(mDocument);
  mAgain := TSyntaxTreeCache.Get(mDocument);
  Assert.AreSame(mAgain.Tree, mWin32.Tree);
  UseDefines(TPascalPreprocessor.PredefinedSymbols('Win64', 37.0));
  mWin64 := TSyntaxTreeCache.Get(mDocument);
  Assert.AreNotSame(mWin32.Tree, mWin64.Tree);
  Assert.AreEqual(2, TSyntaxTreeCache.ParseCount - mBefore);
  Assert.IsNotNull(mWin32.Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl)
    .FindChild(TSyntaxKind.AsmBlock));
  Assert.IsNotNull(mWin64.Tree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl)
    .FindChild(TSyntaxKind.Block));
end;

procedure TActiveBranchesTests.TextWithoutConditionalsKeepsTree;
var
  mDocument: ITextDocument;
  mFirst, mSecond: ISharedSyntaxTree;
begin
  // Ohne bedingte Direktive ändert ein Plattformwechsel nichts: kein neuer Parse.
  mDocument := NewDocument('unit A;'#10'interface'#10'implementation'#10'end.');
  UseDefines(['WIN32']);
  mFirst := TSyntaxTreeCache.Get(mDocument);
  UseDefines(['WIN64']);
  mSecond := TSyntaxTreeCache.Get(mDocument);
  Assert.AreSame(mSecond.Tree, mFirst.Tree);
  Assert.AreEqual(0, Integer(Length(mFirst.Conditionals)));
end;

procedure TActiveBranchesTests.GetAllSeesEveryBranch;
var
  mDocument: ITextDocument;
  mAll: ISharedSyntaxTree;
begin
  mDocument := NewDocument(cCaseUses);
  UseDefines(['MSWINDOWS']);
  mAll := TSyntaxTreeCache.GetAll(mDocument);
  Assert.AreEqual('Winapi.Windows Posix.Unistd System.SysUtils TA', Outline(mAll.Tree));
  Assert.AreNotSame(mAll.Tree, TSyntaxTreeCache.Get(mDocument).Tree);
  Assert.AreSame(TSyntaxTreeCache.GetAll(mDocument).Tree, mAll.Tree);
end;

procedure TActiveBranchesTests.ConditionalsOfTheFile;
var
  mShared: ISharedSyntaxTree;
  mConditional: TConditionalRange;
  mActive: string;
begin
  UseDefines(['MSWINDOWS']);
  mShared := TSyntaxTreeCache.Get(NewDocument(cCaseBodies));
  mActive := '';
  for mConditional in mShared.Conditionals do
  begin
    if mConditional.Active then
    begin
      mActive := mActive + mConditional.Condition + ' ' + IntToStr(mConditional.Range.StartPos.Line);
    end;
  end;
  Assert.AreEqual('MSWINDOWS 6', mActive);
  Assert.AreEqual(2, Integer(Length(mShared.Conditionals)));
end;

procedure TActiveBranchesTests.ActiveDiagnosticsMatchTree;
var
  mDiagnostics: TArray<TSyntaxDiagnostic>;
  mTree: TSyntaxTree;
begin
  // Ohne Projekt gelten die Vordefinitionen (Win32): derselbe Zweig wie in ActiveDiagnostics.
  Assert.IsTrue(TPascalParser.ActiveDiagnostics(cCaseAsm, nil, mDiagnostics));
  Assert.AreEqual(0, Integer(Length(mDiagnostics)));
  mTree := TPascalParser.ParseActive(cCaseAsm, nil);
  try
    Assert.IsNotNull(mTree.Root.FindChild(TSyntaxKind.ImplementationSection).FindChild(TSyntaxKind.RoutineDecl)
      .FindChild(TSyntaxKind.AsmBlock));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TActiveBranchesTests);

end.
