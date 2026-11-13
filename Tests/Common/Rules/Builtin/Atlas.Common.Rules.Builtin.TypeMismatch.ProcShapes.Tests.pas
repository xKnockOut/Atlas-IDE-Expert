unit Atlas.Common.Rules.Builtin.TypeMismatch.ProcShapes.Tests;

// Tests für den Kopf prozeduraler Typen (#1369): Prozedurtyp, Methodenzeiger, Methodenreferenz und Routinenkopf
// lesen, Modifizierer der Parameter angleichen, unlesbare Köpfe ablehnen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TProcShapesTests = class
  public
    [Test]
    procedure ReadsProcedureOfObject;
    [Test]
    procedure ReadsReferenceToFunction;
    [Test]
    procedure ReadsRoutineHeaderWithName;
    [Test]
    procedure RejectsTextWithoutKeyword;
    [Test]
    procedure ModifierKeepsLastWord;
  end;

implementation

uses
  Atlas.Common.Rules.Builtin.TypeMismatch.ProcShapes;

procedure TProcShapesTests.ReadsProcedureOfObject;
var
  mShape: TProcShape;
begin
  Assert.IsTrue(TProcShapes.ParseShape('procedure(Sender: TObject; var A: Integer) of object', False, mShape));
  Assert.IsFalse(mShape.IsFunction);
  Assert.IsTrue(mShape.OfObject);
  Assert.IsFalse(mShape.Reference);
  Assert.AreEqual(2, Integer(Length(mShape.Params)));
  Assert.AreEqual('TObject', mShape.Params[0].TypeName);
  Assert.AreEqual('var', TProcShapes.NormalizedModifier(mShape.Params[1].Modifier));
end;

procedure TProcShapesTests.ReadsReferenceToFunction;
var
  mShape: TProcShape;
begin
  Assert.IsTrue(TProcShapes.ParseShape('reference to function(const AName: string): Boolean', False, mShape));
  Assert.IsTrue(mShape.IsFunction);
  Assert.IsTrue(mShape.Reference);
  Assert.IsFalse(mShape.OfObject);
  Assert.AreEqual('Boolean', mShape.ResultType);
  Assert.AreEqual(1, Integer(Length(mShape.Params)));
end;

procedure TProcShapesTests.ReadsRoutineHeaderWithName;
var
  mShape: TProcShape;
begin
  Assert.IsTrue(TProcShapes.ParseShape('function Summe(A, B: Integer): Integer;', True, mShape));
  Assert.IsTrue(mShape.IsFunction);
  Assert.AreEqual(2, Integer(Length(mShape.Params)));
  Assert.AreEqual('Integer', mShape.ResultType);
end;

procedure TProcShapesTests.RejectsTextWithoutKeyword;
var
  mShape: TProcShape;
begin
  Assert.IsFalse(TProcShapes.ParseShape('Integer', False, mShape));
end;

procedure TProcShapesTests.ModifierKeepsLastWord;
begin
  Assert.AreEqual('const', TProcShapes.NormalizedModifier('[ref] const'));
  Assert.AreEqual('var', TProcShapes.NormalizedModifier(' VAR '));
  Assert.AreEqual('', TProcShapes.NormalizedModifier(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TProcShapesTests);

end.
