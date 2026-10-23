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
  Conditionals: TAtlasConditionals;
begin
  Conditionals := NewConditionals;
  try
    Assert.IsTrue(Conditionals.Active);
    Assert.IsTrue(Conditionals.Handle('IFDEF FPC'));
    Assert.IsFalse(Conditionals.Active, 'FPC fehlt');
    Conditionals.Handle('ELSE');
    Assert.IsTrue(Conditionals.Active);
    Conditionals.Handle('ENDIF');
    Assert.IsTrue(Conditionals.Active);
    Conditionals.Handle('IFDEF Win32');
    Assert.IsTrue(Conditionals.Active, 'Groß-/Kleinschreibung egal');
    Conditionals.Handle('ELSE');
    Assert.IsFalse(Conditionals.Active);
    Conditionals.Handle('IFEND');
    Conditionals.Handle('IFNDEF FPC');
    Assert.IsTrue(Conditionals.Active);
    Conditionals.Handle('ENDIF');
  finally
    Conditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.NestedBranchesInInactiveParent;
var
  Conditionals: TAtlasConditionals;
begin
  Conditionals := NewConditionals;
  try
    // {$IFDEF FPC}{$IFDEF UNIX} … {$ELSE} … {$ENDIF}{$ELSE} … {$ENDIF}
    Conditionals.Handle('IFDEF FPC');
    Conditionals.Handle('IFDEF UNIX');
    Assert.IsFalse(Conditionals.Active);
    Conditionals.Handle('ELSE');
    Assert.IsFalse(Conditionals.Active, 'ELSE in einem inaktiven Zweig bleibt inaktiv');
    Conditionals.Handle('ENDIF');
    Assert.IsFalse(Conditionals.Active);
    Conditionals.Handle('ELSE');
    Assert.IsTrue(Conditionals.Active);
    Conditionals.Handle('ENDIF');
    Assert.IsTrue(Conditionals.Active);
  finally
    Conditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.IfExpressions;
var
  Conditionals: TAtlasConditionals;

  function Holds(const AExpression: string): Boolean;
  begin
    Conditionals.Handle('IF ' + AExpression);
    Result := Conditionals.Active;
    Conditionals.Handle('IFEND');
  end;

begin
  Conditionals := NewConditionals;
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
    Conditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.ElseIfTakesFirstTrueBranch;
var
  Conditionals: TAtlasConditionals;
begin
  Conditionals := NewConditionals;
  try
    Conditionals.Handle('IF Defined(FPC)');
    Assert.IsFalse(Conditionals.Active);
    Conditionals.Handle('ELSEIF Defined(MSWINDOWS)');
    Assert.IsTrue(Conditionals.Active);
    Conditionals.Handle('ELSEIF Defined(WIN32)');
    Assert.IsFalse(Conditionals.Active, 'schon ein Zweig genommen');
    Conditionals.Handle('ELSE');
    Assert.IsFalse(Conditionals.Active);
    Conditionals.Handle('IFEND');
    Assert.IsTrue(Conditionals.Active);
  finally
    Conditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.DefineAndUndefOnlyInActiveBranches;
var
  Conditionals: TAtlasConditionals;
begin
  Conditionals := NewConditionals;
  try
    Conditionals.Handle('IFDEF FPC');
    Conditionals.Handle('DEFINE NURFPC');
    Conditionals.Handle('UNDEF MSWINDOWS');
    Conditionals.Handle('ENDIF');
    Assert.IsFalse(Conditionals.Defined('NURFPC'), 'im inaktiven Zweig ohne Wirkung');
    Assert.IsTrue(Conditionals.Defined('MSWINDOWS'));
    Conditionals.Handle('DEFINE Eigen');
    Assert.IsTrue(Conditionals.Defined('EIGEN'));
    Conditionals.Handle('UNDEF eigen');
    Assert.IsFalse(Conditionals.Defined('Eigen'));
  finally
    Conditionals.Free;
  end;
end;

procedure TAtlasConditionalsTests.OtherDirectivesAreNotConditional;
var
  Conditionals: TAtlasConditionals;
begin
  Conditionals := NewConditionals;
  try
    Assert.IsFalse(Conditionals.Handle('MODE DELPHIUNICODE'));
    Assert.IsFalse(Conditionals.Handle('R *.dfm'));
    // $IFOPT kennt nur der Compiler: gilt als falsch, der ELSE-Zweig ist aktiv.
    Assert.IsTrue(Conditionals.Handle('IFOPT R+'));
    Assert.IsFalse(Conditionals.Active);
    Conditionals.Handle('ELSE');
    Assert.IsTrue(Conditionals.Active);
    Conditionals.Handle('ENDIF');
    // Ein ENDIF zu viel bricht nichts.
    Conditionals.Handle('ENDIF');
    Assert.IsTrue(Conditionals.Active);
  finally
    Conditionals.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasConditionalsTests);

end.
