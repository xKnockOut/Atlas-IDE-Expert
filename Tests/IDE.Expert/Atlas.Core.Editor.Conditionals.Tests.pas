unit Atlas.Core.Editor.Conditionals.Tests;

// Bedingte Übersetzung für die Lexer des Plugins: aktive Zweige von $IFDEF,
// $IFNDEF, $IF, $ELSEIF, $ELSE, verschachtelt, mit $DEFINE und $UNDEF.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasConditionalsTests = class
  public
    [Test]
    procedure IfdefElseEndif;
    [Test]
    procedure NestedBranchesInInactiveParent;
    [Test]
    procedure IfExpressions;
    [Test]
    procedure ElseIfTakesFirstTrueBranch;
    [Test]
    procedure DefineAndUndefOnlyInActiveBranches;
    [Test]
    procedure OtherDirectivesAreNotConditional;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.Conditionals;

function NewConditionals: TAtlasConditionals;
begin
  Result := TAtlasConditionals.Create(['MSWINDOWS', 'win32', 'CONDITIONALEXPRESSIONS'], 37.0);
end;

procedure TAtlasConditionalsTests.IfdefElseEndif;
var
  mConditionals: TAtlasConditionals;
begin
  mConditionals := NewConditionals;
  try
    Assert.IsTrue(mConditionals.Active);
    Assert.IsTrue(mConditionals.Handle('IFDEF FPC'));
    Assert.IsFalse(mConditionals.Active, 'FPC fehlt');
    mConditionals.Handle('ELSE');
    Assert.IsTrue(mConditionals.Active);
    mConditionals.Handle('ENDIF');
    Assert.IsTrue(mConditionals.Active);
    mConditionals.Handle('IFDEF Win32');
    Assert.IsTrue(mConditionals.Active, 'Groß-/Kleinschreibung egal');
    mConditionals.Handle('ELSE');
    Assert.IsFalse(mConditionals.Active);
    mConditionals.Handle('IFEND');
    mConditionals.Handle('IFNDEF FPC');
    Assert.IsTrue(mConditionals.Active);
    mConditionals.Handle('ENDIF');
  finally
    mConditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.NestedBranchesInInactiveParent;
var
  mConditionals: TAtlasConditionals;
begin
  mConditionals := NewConditionals;
  try
    // {$IFDEF FPC}{$IFDEF UNIX} … {$ELSE} … {$ENDIF}{$ELSE} … {$ENDIF}
    mConditionals.Handle('IFDEF FPC');
    mConditionals.Handle('IFDEF UNIX');
    Assert.IsFalse(mConditionals.Active);
    mConditionals.Handle('ELSE');
    Assert.IsFalse(mConditionals.Active, 'ELSE in einem inaktiven Zweig bleibt inaktiv');
    mConditionals.Handle('ENDIF');
    Assert.IsFalse(mConditionals.Active);
    mConditionals.Handle('ELSE');
    Assert.IsTrue(mConditionals.Active);
    mConditionals.Handle('ENDIF');
    Assert.IsTrue(mConditionals.Active);
  finally
    mConditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.IfExpressions;
var
  mConditionals: TAtlasConditionals;

  function Holds(const AExpression: string): Boolean;
  begin
    mConditionals.Handle('IF ' + AExpression);
    Result := mConditionals.Active;
    mConditionals.Handle('IFEND');
  end;

begin
  mConditionals := NewConditionals;
  try
    Assert.IsTrue(Holds('Defined(MSWINDOWS)'));
    Assert.IsFalse(Holds('Defined(FPC)'));
    Assert.IsTrue(Holds('Defined(MSWINDOWS) and not Defined(FPC)'));
    Assert.IsTrue(Holds('Defined(FPC) or Defined(WIN32)'));
    Assert.IsFalse(Holds('not (Defined(MSWINDOWS) or Defined(FPC))'));
    Assert.IsTrue(Holds('CompilerVersion >= 35'));
    Assert.IsFalse(Holds('CompilerVersion < 30.5'));
    Assert.IsTrue(Holds('RTLVersion = 37'));
    // Was nur der Compiler weiß, gilt als wahr.
    Assert.IsTrue(Holds('Declared(TFoo)'));
    Assert.IsTrue(Holds('SizeOf(Pointer) = 8'));
  finally
    mConditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.ElseIfTakesFirstTrueBranch;
var
  mConditionals: TAtlasConditionals;
begin
  mConditionals := NewConditionals;
  try
    mConditionals.Handle('IF Defined(FPC)');
    Assert.IsFalse(mConditionals.Active);
    mConditionals.Handle('ELSEIF Defined(MSWINDOWS)');
    Assert.IsTrue(mConditionals.Active);
    mConditionals.Handle('ELSEIF Defined(WIN32)');
    Assert.IsFalse(mConditionals.Active, 'schon ein Zweig genommen');
    mConditionals.Handle('ELSE');
    Assert.IsFalse(mConditionals.Active);
    mConditionals.Handle('IFEND');
    Assert.IsTrue(mConditionals.Active);
  finally
    mConditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.DefineAndUndefOnlyInActiveBranches;
var
  mConditionals: TAtlasConditionals;
begin
  mConditionals := NewConditionals;
  try
    mConditionals.Handle('IFDEF FPC');
    mConditionals.Handle('DEFINE NURFPC');
    mConditionals.Handle('UNDEF MSWINDOWS');
    mConditionals.Handle('ENDIF');
    Assert.IsFalse(mConditionals.Defined('NURFPC'), 'im inaktiven Zweig ohne Wirkung');
    Assert.IsTrue(mConditionals.Defined('MSWINDOWS'));
    mConditionals.Handle('DEFINE Eigen');
    Assert.IsTrue(mConditionals.Defined('EIGEN'));
    mConditionals.Handle('UNDEF eigen');
    Assert.IsFalse(mConditionals.Defined('Eigen'));
  finally
    mConditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.OtherDirectivesAreNotConditional;
var
  mConditionals: TAtlasConditionals;
begin
  mConditionals := NewConditionals;
  try
    Assert.IsFalse(mConditionals.Handle('MODE DELPHIUNICODE'));
    Assert.IsFalse(mConditionals.Handle('R *.dfm'));
    // $IFOPT kennt nur der Compiler: gilt als falsch, der ELSE-Zweig ist aktiv.
    Assert.IsTrue(mConditionals.Handle('IFOPT R+'));
    Assert.IsFalse(mConditionals.Active);
    mConditionals.Handle('ELSE');
    Assert.IsTrue(mConditionals.Active);
    mConditionals.Handle('ENDIF');
    // Ein ENDIF zu viel bricht nichts.
    mConditionals.Handle('ENDIF');
    Assert.IsTrue(mConditionals.Active);
  finally
    mConditionals.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasConditionalsTests);

end.
