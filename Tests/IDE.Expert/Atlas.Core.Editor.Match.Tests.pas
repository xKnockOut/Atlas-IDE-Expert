unit Atlas.Core.Editor.Match.Tests;

// Sprung zum Gegenstück (#635): jedes Paar (begin/end, case/end, class/
// record/end, try/finally/except/end reihum, repeat/until, Klammern,
// Direktiven über inaktive Zweige, Methodenname Deklaration ⇄
// Implementierung), Verschachtelung, end in Strings und Kommentaren,
// unvollständiger Code und die Markierung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasJumpToMatchTests = class
  public
    [Test]
    procedure BeginEndNested;
    [Test]
    procedure CaseRecordClassAndRepeat;
    [Test]
    procedure TryCyclesThroughFinallyAndExcept;
    [Test]
    procedure Brackets;
    [Test]
    procedure IgnoresStringsAndComments;
    [Test]
    procedure DirectivesCycleOverInactiveBranches;
    [Test]
    procedure MethodNameDeclarationAndImplementation;
    [Test]
    procedure NoJumpInIncompleteCode;
    [Test]
    procedure SelectsToCounterpart;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Editor.Match;

function Jump(const AText: string; ALine, ACharacter: Integer): string;
var
  mTarget: TAtlasMatchSpot;
begin
  if TAtlasJumpToMatch.Target(AText, ALine, ACharacter, mTarget) then
  begin
    Result := Format('%d:%d', [mTarget.Line, mTarget.Character]);
  end
  else
  begin
    Result := '-';
  end;
end;

procedure TAtlasJumpToMatchTests.BeginEndNested;
const
  cCode =
    'procedure P;'#13#10 +            // 0
    'begin'#13#10 +                   // 1
    '  if A then'#13#10 +             // 2
    '  begin'#13#10 +                 // 3
    '    B;'#13#10 +                  // 4
    '  end;'#13#10 +                  // 5
    'end;';                           // 6
begin
  Assert.AreEqual('6:0', Jump(cCode, 1, 0));
  Assert.AreEqual('1:0', Jump(cCode, 6, 0));
  Assert.AreEqual('1:0', Jump(cCode, 6, 3), 'direkt hinter end');
  Assert.AreEqual('5:2', Jump(cCode, 3, 4), 'im Wort');
  Assert.AreEqual('3:2', Jump(cCode, 5, 2));
  Assert.AreEqual('-', Jump(cCode, 4, 4), 'kein Paar');
  Assert.AreEqual('-', Jump(cCode, 2, 2), 'Besitzer if zählt nicht');
end;

procedure TAtlasJumpToMatchTests.CaseRecordClassAndRepeat;
const
  cCode =
    'type'#13#10 +                              // 0
    '  TR = record'#13#10 +                     // 1
    '    X: Integer;'#13#10 +                   // 2
    '  end;'#13#10 +                            // 3
    '  TC = class(TObject)'#13#10 +             // 4
    '  end;'#13#10 +                            // 5
    'procedure P;'#13#10 +                      // 6
    'begin'#13#10 +                             // 7
    '  case X of'#13#10 +                       // 8
    '    1: ;'#13#10 +                          // 9
    '  end;'#13#10 +                            // 10
    '  repeat'#13#10 +                          // 11
    '    Inc(X);'#13#10 +                       // 12
    '  until X > 3;'#13#10 +                    // 13
    'end;';                                     // 14
begin
  Assert.AreEqual('3:2', Jump(cCode, 1, 7));
  Assert.AreEqual('1:7', Jump(cCode, 3, 2));
  Assert.AreEqual('5:2', Jump(cCode, 4, 7));
  Assert.AreEqual('10:2', Jump(cCode, 8, 2));
  Assert.AreEqual('8:2', Jump(cCode, 10, 2));
  Assert.AreEqual('13:2', Jump(cCode, 11, 2));
  Assert.AreEqual('11:2', Jump(cCode, 13, 2));
  Assert.AreEqual('14:0', Jump(cCode, 7, 0));
end;

procedure TAtlasJumpToMatchTests.TryCyclesThroughFinallyAndExcept;
const
  cCode =
    'begin'#13#10 +                  // 0
    '  try'#13#10 +                  // 1
    '    try'#13#10 +                // 2
    '      A;'#13#10 +               // 3
    '    except'#13#10 +             // 4
    '      B;'#13#10 +               // 5
    '    end;'#13#10 +               // 6
    '  finally'#13#10 +              // 7
    '    C;'#13#10 +                 // 8
    '  end;'#13#10 +                 // 9
    'end.';                          // 10
begin
  Assert.AreEqual('7:2', Jump(cCode, 1, 2), 'try → finally');
  Assert.AreEqual('9:2', Jump(cCode, 7, 2), 'finally → end');
  Assert.AreEqual('1:2', Jump(cCode, 9, 2), 'end → try');
  Assert.AreEqual('4:4', Jump(cCode, 2, 4), 'inneres try → except');
  Assert.AreEqual('6:4', Jump(cCode, 4, 4));
  Assert.AreEqual('2:4', Jump(cCode, 6, 4));
end;

procedure TAtlasJumpToMatchTests.Brackets;
const
  cCode = 'X := (A[1] + (B * C))';
begin
  Assert.AreEqual('0:20', Jump(cCode, 0, 5));
  Assert.AreEqual('0:5', Jump(cCode, 0, 20));
  Assert.AreEqual('0:9', Jump(cCode, 0, 7), '[ ⇄ ]');
  Assert.AreEqual('0:19', Jump(cCode, 0, 13));
end;

procedure TAtlasJumpToMatchTests.IgnoresStringsAndComments;
const
  cCode =
    'begin'#13#10 +                       // 0
    '  S := ''end'';'#13#10 +             // 1
    '  { end }'#13#10 +                   // 2
    '  // end'#13#10 +                    // 3
    '  (* begin *)'#13#10 +               // 4
    '  F('')'');'#13#10 +                 // 5
    'end;';                               // 6
begin
  Assert.AreEqual('6:0', Jump(cCode, 0, 0));
  Assert.AreEqual('-', Jump(cCode, 1, 9), 'end im String');
  Assert.AreEqual('-', Jump(cCode, 2, 4), 'end im Kommentar');
  Assert.AreEqual('5:7', Jump(cCode, 5, 3), 'Klammer im String zählt nicht');
end;

procedure TAtlasJumpToMatchTests.DirectivesCycleOverInactiveBranches;
const
  cCode =
    '{$IFDEF GIBTSNICHT}'#13#10 +         // 0
    '  begin'#13#10 +                     // 1
    '{$ELSE}'#13#10 +                     // 2
    '  {$IF CompilerVersion > 30}'#13#10 + // 3
    '  {$IFEND}'#13#10 +                  // 4
    '{$ENDIF}'#13#10 +                    // 5
    '// {$ENDIF}'#13#10 +                 // 6
    '(*$IFNDEF X*) (*$ENDIF*)';           // 7
begin
  Assert.AreEqual('2:0', Jump(cCode, 0, 3));
  Assert.AreEqual('5:0', Jump(cCode, 2, 0));
  Assert.AreEqual('0:0', Jump(cCode, 5, 0));
  Assert.AreEqual('4:2', Jump(cCode, 3, 2));
  Assert.AreEqual('3:2', Jump(cCode, 4, 2));
  Assert.AreEqual('7:14', Jump(cCode, 7, 1));
  Assert.AreEqual('-', Jump(cCode, 6, 4), 'im Kommentar');
  Assert.AreEqual('-', Jump('{$IFDEF A}'#13#10'{$IFDEF B}'#13#10'{$ENDIF}', 2, 0), 'mehrdeutig');
  Assert.AreEqual('-', Jump('{$IFDEF A}'#13#10'{$ELSE}', 1, 0), 'unvollständig');
end;

procedure TAtlasJumpToMatchTests.MethodNameDeclarationAndImplementation;
const
  cCode =
    'unit U;'#13#10 +                             // 0
    'interface'#13#10 +                           // 1
    'type'#13#10 +                                // 2
    '  TFoo = class'#13#10 +                      // 3
    '    procedure Run;'#13#10 +                  // 4
    '  end;'#13#10 +                              // 5
    'implementation'#13#10 +                      // 6
    'procedure TFoo.Run;'#13#10 +                 // 7
    'begin'#13#10 +                               // 8
    'end;'#13#10 +                                // 9
    'end.';                                       // 10
begin
  Assert.AreEqual('7:15', Jump(cCode, 4, 15));
  Assert.AreEqual('4:14', Jump(cCode, 7, 17));
  Assert.AreEqual('-', Jump(cCode, 4, 6), 'auf procedure, nicht auf dem Namen');
end;

procedure TAtlasJumpToMatchTests.NoJumpInIncompleteCode;
const
  cMissing =
    'procedure P;'#13#10 +            // 0
    'begin'#13#10 +                   // 1
    '  if A then'#13#10 +             // 2
    '  begin'#13#10 +                 // 3
    '    B;'#13#10 +                  // 4
    'end;';                           // 5
  cExtra =
    'begin'#13#10 +                   // 0
    'end;'#13#10 +                    // 1
    'end;';                           // 2
begin
  // Das end kann zu beiden begin gehören: kein Sprung.
  Assert.AreEqual('-', Jump(cMissing, 3, 2));
  Assert.AreEqual('-', Jump(cMissing, 5, 0));
  Assert.AreEqual('-', Jump(cMissing, 1, 0), 'unpaarig');
  Assert.AreEqual('-', Jump(cExtra, 0, 0), 'überzähliges end dahinter');
  Assert.AreEqual('-', Jump('X := (A + B', 0, 5));
  Assert.AreEqual('-', Jump('', 0, 0));
end;

procedure TAtlasJumpToMatchTests.SelectsToCounterpart;
const
  cCode =
    'begin'#13#10 +          // 0
    '  A;'#13#10 +           // 1
    'end;';                  // 2
var
  mStart, mStop: TAtlasMatchSpot;
begin
  Assert.IsTrue(TAtlasJumpToMatch.Selection(cCode, 0, 2, mStart, mStop));
  Assert.AreEqual('0:2-2:3', Format('%d:%d-%d:%d', [mStart.Line, mStart.Character, mStop.Line, mStop.Character]),
    'vorwärts bis hinter end');
  Assert.IsTrue(TAtlasJumpToMatch.Selection(cCode, 2, 1, mStart, mStop));
  Assert.AreEqual('0:0-2:1', Format('%d:%d-%d:%d', [mStart.Line, mStart.Character, mStop.Line, mStop.Character]),
    'rückwärts ab begin');
  Assert.IsFalse(TAtlasJumpToMatch.Selection(cCode, 1, 2, mStart, mStop));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasJumpToMatchTests);

end.
