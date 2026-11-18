unit Atlas.Core.Debug.NextStatement.Tests;

// Tests für „Nächste Anweisung hier“ bzw. den gezogenen Ausführungspfeil (#871): erlaubte und verbotene Ziele, Folge
// (erneut ausführen oder überspringen) und die Suche der Zieladresse über die Zeile je Adresse.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.NextStatement;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasNextStatementTests = class
  private
    FCheck: TAtlasNextStatement;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TargetInSameBlockAllowed;
    [Test]
    procedure SameLineRefused;
    [Test]
    procedure OtherRoutineRefused;
    [Test]
    procedure LineWithoutCodeRefused;
    [Test]
    procedure TryPartsAreSeparate;
    [Test]
    procedure CountedForHeadRefused;
    [Test]
    procedure AnonymousMethodIsSeparate;
    [Test]
    procedure EffectNamesLines;
    [Test]
    procedure RoutineAtNamesLines;
    [Test]
    procedure FindAddressBackwardTakesSmallest;
    [Test]
    procedure FindAddressForward;
    [Test]
    procedure FindAddressStopsAtRoutine;
  end;

implementation

uses
  System.SysUtils;

const
  cSource =
    'unit Kunden;' + #10 +                                     // 0
    'implementation' + #10 +                                   // 1
    'procedure Laden(A: Integer);' + #10 +                     // 2
    'var' + #10 +                                              // 3
    '  I: Integer;' + #10 +                                    // 4
    '  R: record case Integer of 0: (X: Integer); end;' + #10 + // 5
    'begin' + #10 +                                            // 6
    '  A := 1;' + #10 +                                        // 7
    '  try' + #10 +                                            // 8
    '    A := 2; // try' + #10 +                               // 9
    '    A := 3;' + #10 +                                      // 10
    '  finally' + #10 +                                        // 11
    '    A := 4;' + #10 +                                      // 12
    '  end;' + #10 +                                           // 13
    '  for I := 0 to 3 do' + #10 +                             // 14
    '    A := I;' + #10 +                                      // 15
    '  Spaeter(procedure' + #10 +                              // 16
    '    begin' + #10 +                                        // 17
    '      A := 5;' + #10 +                                    // 18
    '    end);' + #10 +                                        // 19
    '  A := 6;' + #10 +                                        // 20
    'end;' + #10 +                                             // 21
    '' + #10 +                                                 // 22
    'procedure Anders;' + #10 +                                // 23
    'begin' + #10 +                                            // 24
    '  Anders;' + #10 +                                        // 25
    'end;' + #10 +                                             // 26
    '' + #10 +                                                 // 27
    'end.';                                                    // 28

  cFile = 'C:\P\Kunden.pas';

/// <summary>Gefälschte Zeilentabelle: 99 in einer anderen Datei, 100..104 Zeile 7, 105..109 Zeile 9, 110..119
/// Zeile 10, 120..129 Zeile 12, 130..139 Zeile 15, 140..145 Zeile 14 (Bedingung der Schleife am Ende), 146..150
/// Zeile 20, dahinter die nächste Routine (Zeile 25).</summary>
function FakeLineAt(AAddress: UInt64; out AFileName: string; out ALine: Integer): Boolean;
begin
  AFileName := cFile;
  ALine := -1;
  Result := (AAddress >= 99) and (AAddress <= 160);
  if not Result then
  begin
    Exit;
  end;
  if AAddress = 99 then
  begin
    AFileName := 'C:\P\Andere.pas';
    ALine := 7;
  end
  else if AAddress <= 104 then
  begin
    ALine := 7;
  end
  else if AAddress <= 109 then
  begin
    ALine := 9;
  end
  else if AAddress <= 119 then
  begin
    ALine := 10;
  end
  else if AAddress <= 129 then
  begin
    ALine := 12;
  end
  else if AAddress <= 139 then
  begin
    ALine := 15;
  end
  else if AAddress <= 145 then
  begin
    ALine := 14;
  end
  else if AAddress <= 150 then
  begin
    ALine := 20;
  end
  else
  begin
    ALine := 25;
  end;
end;

/// <summary>Zeile ALine in der Routine Laden (Zeilen 2..21).</summary>
function Target(ALine: Integer): TAtlasNextStatementTarget;
begin
  Result := Default(TAtlasNextStatementTarget);
  Result.FileName := cFile;
  Result.Line := ALine;
  Result.FirstLine := 2;
  Result.LastLine := 21;
end;

{ TAtlasNextStatementTests }

procedure TAtlasNextStatementTests.Setup;
begin
  FCheck := TAtlasNextStatement.Create(cSource);
end;

procedure TAtlasNextStatementTests.TearDown;
begin
  FreeAndNil(FCheck);
end;

procedure TAtlasNextStatementTests.TargetInSameBlockAllowed;
begin
  Assert.IsTrue(FCheck.Check(7, 20) = TAtlasNextStatementVerdict.Allowed, 'vorwärts');
  Assert.IsTrue(FCheck.Check(20, 7) = TAtlasNextStatementVerdict.Allowed, 'zurück');
  Assert.IsTrue(FCheck.Check(9, 10) = TAtlasNextStatementVerdict.Allowed, 'im selben try-Teil');
  Assert.IsTrue(FCheck.Check(7, 15) = TAtlasNextStatementVerdict.Allowed, 'Rumpf der Schleife');
  Assert.IsTrue(FCheck.Check(7, 16) = TAtlasNextStatementVerdict.Allowed, 'Aufruf mit anonymer Methode');
end;

procedure TAtlasNextStatementTests.SameLineRefused;
begin
  Assert.IsTrue(FCheck.Check(7, 7) = TAtlasNextStatementVerdict.SameLine);
end;

procedure TAtlasNextStatementTests.OtherRoutineRefused;
begin
  Assert.IsTrue(FCheck.Check(7, 25) = TAtlasNextStatementVerdict.OutsideRoutine, 'andere Routine');
  Assert.IsTrue(FCheck.Check(7, 22) = TAtlasNextStatementVerdict.OutsideRoutine, 'zwischen Routinen');
end;

procedure TAtlasNextStatementTests.LineWithoutCodeRefused;
begin
  Assert.IsTrue(FCheck.Check(7, 8) = TAtlasNextStatementVerdict.NoCode, 'try');
  Assert.IsTrue(FCheck.Check(7, 4) = TAtlasNextStatementVerdict.NoCode, 'var-Abschnitt');
end;

procedure TAtlasNextStatementTests.TryPartsAreSeparate;
begin
  Assert.IsTrue(FCheck.Check(7, 9) = TAtlasNextStatementVerdict.OtherBlock, 'in den try-Teil');
  Assert.IsTrue(FCheck.Check(9, 7) = TAtlasNextStatementVerdict.OtherBlock, 'aus dem try-Teil');
  Assert.IsTrue(FCheck.Check(10, 12) = TAtlasNextStatementVerdict.OtherBlock, 'in den finally-Teil');
end;

procedure TAtlasNextStatementTests.CountedForHeadRefused;
begin
  Assert.IsTrue(FCheck.Check(7, 14) = TAtlasNextStatementVerdict.ForHead);
end;

procedure TAtlasNextStatementTests.AnonymousMethodIsSeparate;
begin
  Assert.IsTrue(FCheck.Check(7, 18) = TAtlasNextStatementVerdict.OtherBlock, 'hinein');
  Assert.IsTrue(FCheck.Check(18, 20) = TAtlasNextStatementVerdict.OtherBlock, 'heraus');
  Assert.IsTrue(FCheck.Check(7, 19) = TAtlasNextStatementVerdict.OtherBlock, 'end der anonymen Methode');
end;

procedure TAtlasNextStatementTests.EffectNamesLines;
var
  mFirst, mLast: Integer;
begin
  Assert.IsTrue(TAtlasNextStatement.Effect(20, 7, mFirst, mLast) = TAtlasNextStatementEffect.Rerun);
  Assert.AreEqual(7, mFirst);
  Assert.AreEqual(19, mLast);
  Assert.IsTrue(TAtlasNextStatement.Effect(7, 20, mFirst, mLast) = TAtlasNextStatementEffect.Skip);
  Assert.AreEqual(7, mFirst);
  Assert.AreEqual(19, mLast);
  Assert.IsTrue(TAtlasNextStatement.Effect(7, 7, mFirst, mLast) = TAtlasNextStatementEffect.None);
  Assert.AreEqual(-1, mFirst);
end;

procedure TAtlasNextStatementTests.RoutineAtNamesLines;
var
  mFirst, mLast: Integer;
begin
  Assert.IsTrue(FCheck.RoutineAt(10, mFirst, mLast));
  Assert.AreEqual(2, mFirst);
  Assert.AreEqual(21, mLast);
  Assert.IsFalse(FCheck.RoutineAt(22, mFirst, mLast), 'zwischen Routinen');
  Assert.AreEqual(-1, mFirst);
end;

procedure TAtlasNextStatementTests.FindAddressBackwardTakesSmallest;
var
  mFound: UInt64;
begin
  Assert.IsTrue(TAtlasNextStatement.FindAddress(112, Target(7), FakeLineAt, mFound));
  Assert.AreEqual<UInt64>(100, mFound);
  Assert.IsTrue(TAtlasNextStatement.FindAddress(112, Target(10), FakeLineAt, mFound), 'eigene Zeile');
  Assert.AreEqual<UInt64>(110, mFound);
end;

procedure TAtlasNextStatementTests.FindAddressForward;
var
  mFound: UInt64;
begin
  Assert.IsTrue(TAtlasNextStatement.FindAddress(112, Target(15), FakeLineAt, mFound));
  Assert.AreEqual<UInt64>(130, mFound);
  Assert.IsTrue(TAtlasNextStatement.FindAddress(112, Target(14), FakeLineAt, mFound), 'Bedingung am Ende');
  Assert.AreEqual<UInt64>(140, mFound);
end;

procedure TAtlasNextStatementTests.FindAddressStopsAtRoutine;
var
  mFound: UInt64;
begin
  Assert.IsFalse(TAtlasNextStatement.FindAddress(112, Target(25), FakeLineAt, mFound), 'andere Routine');
  Assert.AreEqual<UInt64>(0, mFound);
  Assert.IsFalse(TAtlasNextStatement.FindAddress(112, Target(18), FakeLineAt, mFound), 'Zeile ohne Adresse');
end;

end.
