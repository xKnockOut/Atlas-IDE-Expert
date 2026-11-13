unit Atlas.Core.Debug.RunTo.Tests;

// Tests für „Bis hier ausführen“ (#851) ohne IDE: ausführbare Zeilen,
// Haltepunkte zum Ausschalten, Merken und Wiederherstellen des Zustands.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.RunTo;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasRunToTests = class
  public
    [Test]
    procedure CodeLinesInsideBody;
    [Test]
    procedure NoCodeOutsideBody;
    [Test]
    procedure CommentsAndKeywordsHaveNoCode;
    [Test]
    procedure NestedRoutineHasOwnBegin;
    /// <summary>Akzeptanzkriterium: nur aktive Haltepunkte außer am Ziel werden ausgeschaltet.</summary>
    [Test]
    procedure ToDisableKeepsTargetAndInactive;
    /// <summary>Akzeptanzkriterium: Zustand merken und wiederherstellen (auch nach Absturz über JSON).</summary>
    [Test]
    procedure StateRoundTrip;
    [Test]
    procedure ForeignJsonIsRejected;
    [Test]
    procedure WithoutDropsRestored;
  end;

implementation

uses
  System.SysUtils;

const
  cSource =
    'unit Kunden;' + #10 +                       // 0
    'interface' + #10 +                          // 1
    'procedure Laden(A: Integer);' + #10 +       // 2
    'implementation' + #10 +                     // 3
    'procedure Laden(A: Integer);' + #10 +       // 4
    'var' + #10 +                                // 5
    '  B: Integer;' + #10 +                      // 6
    '' + #10 +                                   // 7
    '  procedure Innen;' + #10 +                 // 8
    '  begin' + #10 +                            // 9
    '    B := 2;' + #10 +                        // 10
    '  end;' + #10 +                             // 11
    '' + #10 +                                   // 12
    'begin' + #10 +                              // 13
    '  // Kommentar' + #10 +                     // 14
    '  { Block' + #10 +                          // 15
    '    B := 3; }' + #10 +                      // 16
    '  try' + #10 +                              // 17
    '    B := A; // rechnen' + #10 +             // 18
    '    Innen;' + #10 +                         // 19
    '  finally' + #10 +                          // 20
    '    Writeln(''{ kein Kommentar'');' + #10 + // 21
    '  end;' + #10 +                             // 22
    '' + #10 +                                   // 23
    'end;' + #10 +                               // 24
    '' + #10 +                                   // 25
    'end.';                                      // 26

function Place(const AFileName: string; ALine: Integer; AEnabled: Boolean): TAtlasBreakpointState;
begin
  Result := TAtlasBreakpointState.Create(AFileName, ALine, AEnabled);
end;

procedure TAtlasRunToTests.CodeLinesInsideBody;
begin
  Assert.IsTrue(TAtlasRunTo.CodeLine(cSource, 13), 'begin der Routine');
  Assert.IsTrue(TAtlasRunTo.CodeLine(cSource, 18), 'Zuweisung mit Kommentar dahinter');
  Assert.IsTrue(TAtlasRunTo.CodeLine(cSource, 19), 'Aufruf');
  Assert.IsTrue(TAtlasRunTo.CodeLine(cSource, 21), 'Klammer im String ist kein Kommentar');
  Assert.IsTrue(TAtlasRunTo.CodeLine(cSource, 24), 'end der Routine');
end;

procedure TAtlasRunToTests.NoCodeOutsideBody;
begin
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 0));
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 2), 'Deklaration');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 4), 'Kopf');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 6), 'var-Abschnitt');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 26));
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, -1));
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 99));
end;

procedure TAtlasRunToTests.CommentsAndKeywordsHaveNoCode;
begin
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 14), 'Zeilenkommentar');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 15), 'Anfang Blockkommentar');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 16), 'im Blockkommentar');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 17), 'try');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 20), 'finally');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 22), 'end; eines Blocks');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 23), 'Leerzeile');
end;

procedure TAtlasRunToTests.NestedRoutineHasOwnBegin;
begin
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 8), 'Kopf der lokalen Routine');
  Assert.IsTrue(TAtlasRunTo.CodeLine(cSource, 9), 'begin der lokalen Routine');
  Assert.IsTrue(TAtlasRunTo.CodeLine(cSource, 10));
  Assert.IsTrue(TAtlasRunTo.CodeLine(cSource, 11), 'end der lokalen Routine');
  Assert.IsFalse(TAtlasRunTo.CodeLine(cSource, 12), 'zwischen lokaler Routine und begin');
end;

procedure TAtlasRunToTests.ToDisableKeepsTargetAndInactive;
var
  mStates, mDisable: TAtlasBreakpointStates;
begin
  mStates := [Place('C:\P\A.pas', 4, True), Place('C:\P\A.pas', 9, False), Place('c:\p\a.PAS', 18, True),
    Place('C:\P\B.pas', 18, True)];
  mDisable := TAtlasRunTo.ToDisable(mStates, 'C:\P\A.pas', 18);
  Assert.AreEqual(2, Integer(Length(mDisable)));
  Assert.AreEqual(4, mDisable[0].Line);
  Assert.AreEqual('C:\P\B.pas', mDisable[1].FileName);
end;

procedure TAtlasRunToTests.StateRoundTrip;
var
  mState, mRead: TAtlasRunToState;
begin
  mState := Default(TAtlasRunToState);
  mState.FileName := 'C:\P\Kunden ö.pas';
  mState.Line := 18;
  mState.Created := True;
  mState.Changed := [Place('C:\P\A.pas', 4, True), Place('C:\P\Kunden ö.pas', 18, False)];
  Assert.IsTrue(TAtlasRunTo.Parse(TAtlasRunTo.ToJson(mState), mRead));
  Assert.AreEqual(mState.FileName, mRead.FileName);
  Assert.AreEqual(18, mRead.Line);
  Assert.IsTrue(mRead.Created);
  Assert.AreEqual(2, Integer(Length(mRead.Changed)));
  Assert.AreEqual(4, mRead.Changed[0].Line);
  Assert.IsTrue(mRead.Changed[0].Enabled);
  Assert.IsFalse(mRead.Changed[1].Enabled);
end;

procedure TAtlasRunToTests.ForeignJsonIsRejected;
var
  mState: TAtlasRunToState;
begin
  Assert.IsFalse(TAtlasRunTo.Parse('', mState));
  Assert.IsFalse(TAtlasRunTo.Parse('[1]', mState));
  Assert.IsFalse(TAtlasRunTo.Parse('{"format":2,"file":"a.pas","line":1}', mState));
  Assert.IsFalse(TAtlasRunTo.Parse('{"format":1,"line":1}', mState), 'ohne Ziel');
  Assert.IsFalse(mState.Active);
end;

procedure TAtlasRunToTests.WithoutDropsRestored;
var
  mLeft: TAtlasBreakpointStates;
begin
  mLeft := TAtlasRunTo.Without([Place('A.pas', 1, True), Place('B.pas', 2, True), Place('A.pas', 3, False)],
    [Place('a.pas', 1, False), Place('A.pas', 3, True)]);
  Assert.AreEqual(1, Integer(Length(mLeft)));
  Assert.AreEqual('B.pas', mLeft[0].FileName);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRunToTests);

end.
