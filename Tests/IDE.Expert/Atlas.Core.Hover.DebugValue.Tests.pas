unit Atlas.Core.Hover.DebugValue.Tests;

// Tests für den Variablenwert im Hover beim Debuggen (#891): Ausdruck unter der
// Maus, Zustände des Werts und Kürzen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Hover.DebugValue;

type
  [TestFixture]
  TDebugValueTests = class
  private
    /// <summary>Ausdruck zum ersten Vorkommen von AWord in ALine.</summary>
    function ExpressionAt(const ALine, AWord: string): string;
  public
    [Test]
    procedure PlainIdentifier;
    [Test]
    procedure QualifiedChain;
    [Test]
    procedure FirstPartOfChainOnly;
    [Test]
    procedure IndexAndDereference;
    [Test]
    procedure CallBeforeDotGivesNothing;
    [Test]
    procedure CallInIndexGivesNothing;
    [Test]
    procedure RangeIsNoQualifier;
    [Test]
    procedure ReservedWordsAndNumbers;
    [Test]
    procedure StringsAndComments;
    [Test]
    procedure EscapedIdentifier;
    [Test]
    procedure AtCharacterFindsWordBounds;
    [Test]
    procedure ShortenLongValues;
    [Test]
    procedure StatesAndPlainText;
  end;

implementation

uses
  System.SysUtils;

function TDebugValueTests.ExpressionAt(const ALine, AWord: string): string;
var
  mStart: Integer;
begin
  mStart := Pos(AWord, ALine) - 1;
  Assert.IsTrue(mStart >= 0, AWord + ' fehlt in der Zeile');
  Result := TAtlasDebugExpression.At(ALine, mStart, mStart + Length(AWord));
end;

procedure TDebugValueTests.PlainIdentifier;
begin
  Assert.AreEqual('Kunde', ExpressionAt('  Kunde := nil;', 'Kunde'));
  Assert.AreEqual('Result', ExpressionAt('  Result := 0;', 'Result'));
end;

procedure TDebugValueTests.QualifiedChain;
begin
  Assert.AreEqual('FList.Count', ExpressionAt('  for I := 0 to FList.Count - 1 do', 'Count'));
  Assert.AreEqual('Self.FKunde.Name', ExpressionAt('  S := Self.FKunde.Name;', 'Name'));
end;

procedure TDebugValueTests.FirstPartOfChainOnly;
begin
  // Wie in der IDE: rechts vom Bezeichner wird nichts angehängt.
  Assert.AreEqual('FList', ExpressionAt('  N := FList.Count;', 'FList'));
end;

procedure TDebugValueTests.IndexAndDereference;
begin
  Assert.AreEqual('Kunden[I].Name', ExpressionAt('  S := Kunden[I].Name;', 'Name'));
  Assert.AreEqual('Matrix[I][J + 1].Wert', ExpressionAt('  X := Matrix[I][J + 1].Wert;', 'Wert'));
  Assert.AreEqual('P^.Wert', ExpressionAt('  X := P^.Wert;', 'Wert'));
end;

procedure TDebugValueTests.CallBeforeDotGivesNothing;
begin
  // Aufruf bzw. Typumwandlung vor dem Punkt: nicht auswerten, auch nicht nur „Name“.
  Assert.AreEqual('', ExpressionAt('  S := Get(X).Name;', 'Name'));
  Assert.AreEqual('', ExpressionAt('  S := TKunde(Obj).Name;', 'Name'));
end;

procedure TDebugValueTests.CallInIndexGivesNothing;
begin
  Assert.AreEqual('', ExpressionAt('  S := Kunden[Index(1)].Name;', 'Name'));
  Assert.AreEqual('', ExpressionAt('  S := Werte[''a''].Name;', 'Name'));
end;

procedure TDebugValueTests.RangeIsNoQualifier;
begin
  Assert.AreEqual('Count', ExpressionAt('  for I in [0..Count] do', 'Count'));
end;

procedure TDebugValueTests.ReservedWordsAndNumbers;
begin
  Assert.AreEqual('', ExpressionAt('  begin', 'begin'));
  Assert.AreEqual('', ExpressionAt('  if A then', 'then'));
  Assert.AreEqual('', TAtlasDebugExpression.At('  X := 42;', 7, 9));
  Assert.IsTrue(TAtlasDebugExpression.IsReserved('END'));
  Assert.IsFalse(TAtlasDebugExpression.IsReserved('Self'));
end;

procedure TDebugValueTests.StringsAndComments;
begin
  Assert.AreEqual('', ExpressionAt('  S := ''Kunde'';', 'Kunde'));
  Assert.AreEqual('', ExpressionAt('  X := 1; // Kunde', 'Kunde'));
  Assert.AreEqual('', ExpressionAt('  X := 1; { Kunde }', 'Kunde'));
  Assert.AreEqual('', ExpressionAt('  X := 1; (* Kunde *)', 'Kunde'));
  // Nach dem Ende von String und Kommentar wieder auswertbar.
  Assert.AreEqual('Kunde', ExpressionAt('  S := ''a'' + { b } Kunde;', 'Kunde'));
end;

procedure TDebugValueTests.EscapedIdentifier;
begin
  Assert.AreEqual('&Type.Name', ExpressionAt('  S := &Type.Name;', 'Name'));
end;

procedure TDebugValueTests.AtCharacterFindsWordBounds;
var
  mLine: string;
begin
  mLine := '  N := FList.Count;';
  // Mitten in „Count“.
  Assert.AreEqual('FList.Count', TAtlasDebugExpression.AtCharacter(mLine, Pos('ount', mLine) - 1));
  // Auf dem Leerzeichen: nichts.
  Assert.AreEqual('', TAtlasDebugExpression.AtCharacter(mLine, 0));
  Assert.AreEqual('', TAtlasDebugExpression.AtCharacter(mLine, Length(mLine)));
end;

procedure TDebugValueTests.ShortenLongValues;
var
  mValue: TAtlasDebugValue;
begin
  Assert.AreEqual('abc', TAtlasDebugExpression.Shorten('abc', 3));
  Assert.AreEqual('ab …', TAtlasDebugExpression.Shorten('abc', 2));
  mValue := TAtlasDebugValue.Evaluated('S', StringOfChar('x', TAtlasDebugExpression.cMaxValueLength + 10));
  Assert.AreEqual(TAtlasDebugExpression.cMaxValueLength + 2, Integer(Length(mValue.Text)));
end;

procedure TDebugValueTests.StatesAndPlainText;
var
  mValue: TAtlasDebugValue;
begin
  mValue := Default(TAtlasDebugValue);
  Assert.IsFalse(mValue.Visible);
  Assert.AreEqual('', mValue.PlainText);
  mValue := TAtlasDebugValue.Pending('Count');
  Assert.IsTrue(mValue.Visible);
  Assert.AreEqual('', mValue.PlainText, 'ausstehend: noch kein Text für die IDE');
  mValue := TAtlasDebugValue.Evaluated('Count', '3');
  Assert.IsTrue(mValue.Visible);
  Assert.AreEqual('Count = 3', mValue.PlainText);
  // Fehler ohne Erklärung zeigt der Tooltip nicht; mit Erklärung „kein Zugriff“ schon (#840).
  mValue := TAtlasDebugValue.Failed('Count', 'Undeclared identifier');
  Assert.IsFalse(mValue.Visible);
  Assert.IsFalse(mValue.Explained);
  Assert.AreEqual('', mValue.PlainText);
  mValue.Note.Caption := '<kein Zugriff>';
  mValue.Note.Reason := 'Optimierung an.';
  Assert.IsTrue(mValue.Visible);
  Assert.IsTrue(mValue.Explained);
  Assert.AreEqual('Count = <kein Zugriff>' + sLineBreak + 'Optimierung an.', mValue.PlainText);
end;

initialization
  TDUnitX.RegisterTestFixture(TDebugValueTests);

end.
