unit Atlas.Common.Editing.PromoteVariable.Tests;

// Tests für „Lokale Variable und Feld umwandeln“ (#668): var-Block- und
// Inline-Variable mit und ohne Startwert, Typ über die Ableitung, Platz hinter
// dem letzten Feld bzw. neuer private-Abschnitt, Records, Namenskonflikte,
// Warnungen zur Lebensdauer und Rekursion; Rückweg nur, wenn alle
// Bedingungen erfüllt sind (Gegenbeispiele: zweite Methode, Lesen vor
// Schreiben, Property, Formular, published, lokale Routine). Jedes Ergebnis
// muss fehlerfrei parsen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPromoteVariableTests = class
  public
    [Test]
    procedure Names;
    [Test]
    procedure VariableBecomesField;
    [Test]
    procedure InlineVariableKeepsAssignment;
    [Test]
    procedure NewPrivateSectionAndRecord;
    [Test]
    procedure FieldNameConflicts;
    [Test]
    procedure FieldWarnings;
    [Test]
    procedure FieldRefusals;
    [Test]
    procedure FieldBecomesLocal;
    [Test]
    procedure LocalRefusals;
    [Test]
    procedure TargetFromUsage;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Text.Lines;

const
  cLF = #10;

function Lines(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + cLF;
  end;
end;

/// <summary>Unit mit der Klasse TFoo (Rumpf AMembers) und der Implementierung AImplementation.</summary>
function ClassUnit(const AMembers, AImplementation: string): string;
begin
  Result := Lines(['unit U;', '', 'interface', '', 'type', '  TFoo = class']) + AMembers +
    Lines(['  end;', '', 'implementation', '']) + AImplementation + Lines(['', 'end.']);
end;

function PositionOf(const AText, AMarker: string): TTextPosition;
begin
  Assert.IsTrue(Pos(AMarker, AText) > 0, 'Marke fehlt: ' + AMarker);
  Result := TLineTable.Build(AText).PositionAt(Pos(AMarker, AText) - 1);
end;

/// <summary>Lookup ohne Namensauflösung; Inline-Variablen ohne Typ sind Integer, FForm steht im Formular,
/// FBase erbt die Klasse.</summary>
function TestLookup(ATree: TSyntaxTree): TPromoteLookup;
begin
  Result := TPromoteLookup.FromTree(ATree);
  Result.InlineType :=
    function(const ALocal: TRoutineLocal): string
    begin
      Result := 'Integer';
    end;
  Result.InForm :=
    function(const AName: string): Boolean
    begin
      Result := SameText(AName, 'FForm');
    end;
  Result.MemberExists :=
    function(const AClassName, AName: string; AOffset: Integer): Boolean
    begin
      Result := SameText(AName, 'FBase');
    end;
end;

type
  /// <summary>Wo umgewandelt wird (Marker) und unter welchem Namen ('' = Vorschlag).</summary>
  TPromoteAt = record
    Marker: string;
    Name: string;
  end;

function At(const AMarker, AName: string): TPromoteAt;
begin
  Result := Default(TPromoteAt);
  Result.Marker := AMarker;
  Result.Name := AName;
end;

/// <summary>Umwandlung nach AAt; AResult ist der Text, der fehlerfrei parsen muss.</summary>
function Run(const AText: string; const AAt: TPromoteAt; out ATarget: TPromoteTarget; out APromoted: TPromoteResult;
  out AReason, AResult: string): Boolean;
var
  mTree, mCheck: TSyntaxTree;
  mName: string;
begin
  AResult := '';
  APromoted := Default(TPromoteResult);
  mTree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    Result := TPromoteVariable.Target(AText, mTree, PositionOf(AText, AAt.Marker), TestLookup(mTree), ATarget, AReason);
    if not Result then
    begin
      Exit;
    end;
    mName := AAt.Name;
    if mName = '' then
    begin
      mName := ATarget.Suggested;
    end;
    Result := TPromoteVariable.Execute(AText, mTree, TPromoteRequest.Create(PositionOf(AText, AAt.Marker),
      TestLookup(mTree), TFormatStyle.Default, mName), APromoted, AReason);
    if Result then
    begin
      AResult := TChangeSignature.ApplyEdits(AText, APromoted.Edits);
      mCheck := TPascalParser.Parse(AResult);
      try
        Assert.AreEqual(0, Integer(Length(mCheck.Diagnostics)), 'Ergebnis parst nicht: ' + AResult);
      finally
        mCheck.Free;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

function Promoted(const AText, AMarker: string; out ATarget: TPromoteTarget; out AResult: TPromoteResult): string;
var
  mReason: string;
begin
  Assert.IsTrue(Run(AText, At(AMarker, ''), ATarget, AResult, mReason, Result),
    'Aktion fehlt (' + mReason + '): ' + AText);
end;

function PromotedText(const AText, AMarker: string): string;
var
  mTarget: TPromoteTarget;
  mPromote: TPromoteResult;
begin
  Result := Promoted(AText, AMarker, mTarget, mPromote);
end;

function Refused(const AText, AMarker: string): string;
var
  mTarget: TPromoteTarget;
  mPromote: TPromoteResult;
  mText: string;
begin
  Assert.IsFalse(Run(AText, At(AMarker, ''), mTarget, mPromote, Result, mText), 'Aktion unerwartet: ' + mText);
  Assert.AreNotEqual('', Result);
end;

/// <summary>Grund, aus dem die Umwandlung mit dem Namen AName scheitert (die Aktion wird angeboten).</summary>
function RefusedName(const AText, AMarker, AName: string): string;
var
  mTarget: TPromoteTarget;
  mPromote: TPromoteResult;
  mText: string;
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Assert.IsTrue(TPromoteVariable.Target(AText, mTree, PositionOf(AText, AMarker), TestLookup(mTree), mTarget, Result),
      Result);
  finally
    mTree.Free;
  end;
  Assert.IsFalse(Run(AText, At(AMarker, AName), mTarget, mPromote, Result, mText), 'Aktion unerwartet: ' + mText);
end;

procedure TPromoteVariableTests.Names;
begin
  Assert.AreEqual('FLineNo', TPromoteVariable.FieldName('LLineNo'));
  Assert.AreEqual('FCount', TPromoteVariable.FieldName('mCount'));
  Assert.AreEqual('FTotal', TPromoteVariable.FieldName('Total'));
  Assert.AreEqual('FLevel', TPromoteVariable.FieldName('Level'));
  Assert.AreEqual('FL', TPromoteVariable.FieldName('L'));
  Assert.AreEqual('LLineNo', TPromoteVariable.LocalName('FLineNo'));
  Assert.AreEqual('LFoo', TPromoteVariable.LocalName('Foo'));
end;

procedure TPromoteVariableTests.VariableBecomesField;
var
  mText, mDone: string;
  mTarget: TPromoteTarget;
  mPromote: TPromoteResult;
begin
  mText := ClassUnit(Lines(['  private', '    FCount: Integer;', '    procedure Show;', '  public',
    '    procedure Run;']), Lines([
    'procedure TFoo.Show;',
    'begin',
    'end;',
    '',
    'procedure TFoo.Run;',
    'var',
    '  I, LLineNo: Integer;',
    'begin',
    '  LLineNo := 0;',
    '  for I := 0 to 9 do',
    '    Inc(LLineNo);',
    '  FCount := LLineNo;',
    'end;']));
  mDone := Promoted(mText, 'LLineNo:', mTarget, mPromote);
  // Der Pfeil steht zwischen den Namen (ohne ihn zu vergleichen: der FPC-Lauf liest ihn anders).
  Assert.IsTrue(StartsStr(TPromoteVariable.ToFieldTitle + ' (LLineNo ', mTarget.Title), mTarget.Title);
  Assert.IsTrue(EndsStr(' FLineNo)', mTarget.Title), mTarget.Title);
  Assert.AreEqual(ClassUnit(Lines(['  private', '    FCount: Integer;', '    FLineNo: Integer;', '    procedure Show;',
    '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Show;',
    'begin',
    'end;',
    '',
    'procedure TFoo.Run;',
    'var',
    '  I: Integer;',
    'begin',
    '  FLineNo := 0;',
    '  for I := 0 to 9 do',
    '    Inc(FLineNo);',
    '  FCount := FLineNo;',
    'end;'])), mDone);
  Assert.AreEqual(5, mPromote.Places);
  Assert.AreEqual(0, Integer(Length(mPromote.Warnings)));
  // Auch von einer Verwendung aus; der einzige Eintrag nimmt var mit.
  mText := ClassUnit(Lines(['  private', '    procedure Run;']), Lines(['procedure TFoo.Run;', 'var', '  Total: Integer;',
    'begin', '  Total := 1;', 'end;']));
  Assert.AreEqual(ClassUnit(Lines(['  private', '    FTotal: Integer;', '    procedure Run;']),
    Lines(['procedure TFoo.Run;', 'begin', '  FTotal := 1;', 'end;'])), PromotedText(mText, 'Total := 1'));
end;

procedure TPromoteVariableTests.InlineVariableKeepsAssignment;
var
  mText: string;
begin
  mText := ClassUnit(Lines(['  private', '    FCount: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  var LSum: Integer := 0;',
    '  var LNext := LSum + 1;',
    '  var LText: string;',
    '  LText := ''a'';',
    '  FCount := LSum + LNext + Length(LText);',
    'end;']));
  Assert.AreEqual(ClassUnit(Lines(['  private', '    FCount: Integer;', '    FSum: Integer;', '  public',
    '    procedure Run;']), Lines([
    'procedure TFoo.Run;',
    'begin',
    '  FSum := 0;',
    '  var LNext := FSum + 1;',
    '  var LText: string;',
    '  LText := ''a'';',
    '  FCount := FSum + LNext + Length(LText);',
    'end;'])), PromotedText(mText, 'LSum:'));
  // Ohne Typangabe: Typ aus der Ableitung.
  Assert.IsTrue(ContainsStr(PromotedText(mText, 'LNext :='), '    FNext: Integer;' + cLF), mText);
  Assert.IsTrue(ContainsStr(PromotedText(mText, 'LNext :='), '  FNext := LSum + 1;' + cLF), mText);
  // Ohne Startwert verschwindet die Zeile.
  Assert.IsTrue(ContainsStr(PromotedText(mText, 'LText:'), 'begin' + cLF + '  var LSum: Integer := 0;' + cLF +
    '  var LNext := LSum + 1;' + cLF + '  FText := ''a'';' + cLF), PromotedText(mText, 'LText:'));
  Assert.IsTrue(ContainsStr(PromotedText(mText, 'LText:'), '    FText: string;' + cLF), mText);
end;

procedure TPromoteVariableTests.NewPrivateSectionAndRecord;
var
  mText: string;
begin
  // Kein private-Abschnitt: ein neuer vor end.
  mText := ClassUnit(Lines(['  public', '    procedure Run;']), Lines(['procedure TFoo.Run;', 'var', '  LValue: Double;',
    'begin', '  LValue := 1.5;', 'end;']));
  Assert.AreEqual(ClassUnit(Lines(['  public', '    procedure Run;', '  private', '    FValue: Double;']),
    Lines(['procedure TFoo.Run;', 'begin', '  FValue := 1.5;', 'end;'])), PromotedText(mText, 'LValue:'));
  // Record mit Methode: entsprechend.
  mText := Lines(['unit U;', '', 'interface', '', 'type', '  TPoint3 = record', '  private', '    FX: Integer;',
    '  public', '    procedure Reset;', '  end;', '', 'implementation', '', 'procedure TPoint3.Reset;', 'var',
    '  LY: Integer;', 'begin', '  LY := 0;', '  FX := LY;', 'end;', '', 'end.']);
  Assert.AreEqual(Lines(['unit U;', '', 'interface', '', 'type', '  TPoint3 = record', '  private', '    FX: Integer;',
    '    FY: Integer;', '  public', '    procedure Reset;', '  end;', '', 'implementation', '',
    'procedure TPoint3.Reset;', 'begin', '  FY := 0;', '  FX := FY;', 'end;', '', 'end.']), PromotedText(mText, 'LY:'));
end;

procedure TPromoteVariableTests.FieldNameConflicts;
var
  mText: string;
begin
  mText := ClassUnit(Lines(['  private', '    FTotal: Integer;', '  public', '    procedure Run;', '    procedure Other;']),
    Lines(['procedure TFoo.Run;', 'var', '  LSum, LTemp: Integer;', 'begin', '  LSum := FTotal;', '  LTemp := 0;',
    'end;', '', 'procedure TFoo.Other;', 'begin', '  Global := 1;', 'end;']));
  // Vorhandenes und geerbtes Mitglied, lokaler Name, anderer Bezeichner in einer Methode der Klasse, ungültig.
  Assert.IsTrue(ContainsText(RefusedName(mText, 'LSum,', 'FTotal'), 'Mitglied'));
  Assert.IsTrue(ContainsText(RefusedName(mText, 'LSum,', 'FBase'), 'erbt'));
  Assert.IsTrue(ContainsText(RefusedName(mText, 'LSum,', 'LTemp'), 'deklariert'));
  Assert.IsTrue(ContainsText(RefusedName(mText, 'LSum,', 'Global'), 'anderes'));
  Assert.IsTrue(ContainsText(RefusedName(mText, 'LSum,', 'begin'), 'Name'));
  Assert.IsTrue(ContainsText(RefusedName(mText, 'LSum,', '1X'), 'Name'));
  // Ein freier, selbst gewählter Name geht.
  Assert.IsTrue(ContainsStr(PromotedText(mText, 'LSum,'), '  FSum := FTotal;'), mText);
end;

procedure TPromoteVariableTests.FieldWarnings;
var
  mText: string;
  mTarget: TPromoteTarget;
  mPromote: TPromoteResult;
begin
  mText := ClassUnit(Lines(['  public', '    procedure Run(N: Integer);']), Lines(['procedure TFoo.Run(N: Integer);',
    'var', '  LList: TObject;', 'begin', '  LList := TObject.Create;', '  try', '    if N > 0 then', '      Run(N - 1);',
    '  finally', '    LList.Free;', '  end;', 'end;']));
  Promoted(mText, 'LList:', mTarget, mPromote);
  Assert.AreEqual(2, Integer(Length(mPromote.Warnings)));
  Assert.IsTrue(ContainsText(mPromote.Warnings[0], 'freigegeben'), mPromote.Warnings[0]);
  Assert.IsTrue(ContainsText(mPromote.Warnings[1], 'selbst'), mPromote.Warnings[1]);
end;

procedure TPromoteVariableTests.FieldRefusals;
begin
  // Freie Routine, Parameter, Laufvariable, Klassenmethode, with, lokale Routine.
  Refused(Lines(['unit U;', 'interface', 'implementation', 'procedure Run;', 'var', '  L: Integer;', 'begin', '  L := 1;',
    'end;', 'end.']), 'L:');
  Refused(ClassUnit(Lines(['  public', '    procedure Run(AValue: Integer);']), Lines(['procedure TFoo.Run(AValue: Integer);',
    'begin', '  AValue := 1;', 'end;'])), 'AValue := 1');
  Refused(ClassUnit(Lines(['  public', '    procedure Run;']), Lines(['procedure TFoo.Run;', 'begin',
    '  for var I := 0 to 1 do ;', 'end;'])), 'I :=');
  Refused(ClassUnit(Lines(['  public', '    class procedure Run;']), Lines(['class procedure TFoo.Run;', 'var',
    '  L: Integer;', 'begin', '  L := 1;', 'end;'])), 'L:');
  Refused(ClassUnit(Lines(['  public', '    procedure Run;']), Lines(['procedure TFoo.Run;', 'var', '  L: Integer;',
    'begin', '  with Self do', '    L := 1;', 'end;'])), 'L:');
  Refused(ClassUnit(Lines(['  public', '    procedure Run;']), Lines(['procedure TFoo.Run;', '',
    '  procedure Inner;', '  var', '    L: Integer;', '  begin', '    L := 1;', '  end;', '', 'begin', '  Inner;',
    'end;'])), 'L:');
end;

procedure TPromoteVariableTests.FieldBecomesLocal;
var
  mText, mDone: string;
  mTarget: TPromoteTarget;
  mPromote: TPromoteResult;
begin
  mText := ClassUnit(Lines(['  private', '    FA, FLineNo: Integer;', '  public', '    procedure Run;',
    '    procedure Other;']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  I: Integer;',
    'begin',
    '  if FA > 0 then',
    '    FLineNo := 1',
    '  else',
    '    Self.FLineNo := 2;',
    '  I := FLineNo;',
    'end;',
    '',
    'procedure TFoo.Other;',
    'begin',
    '  FA := 1;',
    'end;']));
  mDone := Promoted(mText, 'FLineNo:', mTarget, mPromote);
  Assert.IsTrue(StartsStr(TPromoteVariable.ToLocalTitle + ' (FLineNo ', mTarget.Title), mTarget.Title);
  Assert.IsTrue(EndsStr(' LLineNo)', mTarget.Title), mTarget.Title);
  Assert.AreEqual(ClassUnit(Lines(['  private', '    FA: Integer;', '  public', '    procedure Run;',
    '    procedure Other;']), Lines([
    'procedure TFoo.Run;',
    'var',
    '  I: Integer;',
    '  LLineNo: Integer;',
    'begin',
    '  if FA > 0 then',
    '    LLineNo := 1',
    '  else',
    '    LLineNo := 2;',
    '  I := LLineNo;',
    'end;',
    '',
    'procedure TFoo.Other;',
    'begin',
    '  FA := 1;',
    'end;'])), mDone);
  // Ohne var-Abschnitt entsteht einer.
  mText := ClassUnit(Lines(['  private', '    FTemp: string;', '  public', '    procedure Run;']),
    Lines(['procedure TFoo.Run;', 'begin', '  FTemp := ''x'';', '  Writeln(FTemp);', 'end;']));
  Assert.AreEqual(ClassUnit(Lines(['  public', '    procedure Run;']), Lines(['procedure TFoo.Run;', 'var',
    '  LTemp: string;', 'begin', '  LTemp := ''x'';', '  Writeln(LTemp);', 'end;'])), PromotedText(mText, 'FTemp:'));
end;

procedure TPromoteVariableTests.LocalRefusals;
var
  mMembers, mRun: string;
begin
  mMembers := Lines(['  private', '    FTemp: Integer;', '  public', '    procedure Run;', '    procedure Other;']);
  mRun := Lines(['procedure TFoo.Run;', 'begin', '  FTemp := 1;', '  Other;', 'end;', '']);
  // Zweite Methode.
  Assert.IsTrue(ContainsText(Refused(ClassUnit(mMembers, mRun + Lines(['procedure TFoo.Other;', 'begin',
    '  FTemp := 2;', 'end;'])), 'FTemp:'), 'mehreren'));
  // Lesen vor Schreiben, nicht auf jedem Weg geschrieben.
  Assert.IsTrue(ContainsText(Refused(ClassUnit(mMembers, Lines(['procedure TFoo.Run;', 'begin', '  Inc(FTemp);', 'end;',
    '', 'procedure TFoo.Other;', 'begin', 'end;'])), 'FTemp:'), 'zuerst'));
  Assert.IsTrue(ContainsText(Refused(ClassUnit(mMembers, Lines(['procedure TFoo.Run;', 'begin', '  if Tag = 0 then',
    '    FTemp := 1;', '  Other(FTemp);', 'end;', '', 'procedure TFoo.Other;', 'begin', 'end;'])), 'FTemp:'), 'zuerst'));
  // Property, Formular, published, lokale Routine, nicht benutzt.
  Refused(ClassUnit(mMembers + Lines(['    property Temp: Integer read FTemp;']), mRun + Lines(['procedure TFoo.Other;',
    'begin', 'end;'])), 'FTemp:');
  Refused(ClassUnit(Lines(['  private', '    FForm: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;', 'begin', '  FForm := 1;', 'end;'])), 'FForm:');
  Refused(ClassUnit(Lines(['  published', '    FTemp: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;', 'begin', '  FTemp := 1;', 'end;'])), 'FTemp:');
  Refused(ClassUnit(Lines(['  private', '    FTemp: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;', '', '  procedure Inner;', '  begin', '    FTemp := 1;', '  end;', '', 'begin', '  Inner;',
    'end;'])), 'FTemp:');
  Refused(ClassUnit(mMembers, Lines(['procedure TFoo.Run;', 'begin', 'end;', '', 'procedure TFoo.Other;', 'begin',
    'end;'])), 'FTemp:');
  // Über ein anderes Objekt.
  Refused(ClassUnit(mMembers, Lines(['procedure TFoo.Run;', 'begin', '  FTemp := 1;', 'end;', '',
    'procedure TFoo.Other;', 'var', '  Foo: TFoo;', 'begin', '  Foo.FTemp := 1;', 'end;'])), 'FTemp:');
end;

procedure TPromoteVariableTests.TargetFromUsage;
var
  mText: string;
begin
  // Cursor auf der Verwendung eines Felds in der Methode.
  mText := ClassUnit(Lines(['  private', '    FTemp: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;', 'begin', '  FTemp := 1;', 'end;']));
  Assert.IsTrue(ContainsStr(PromotedText(mText, 'FTemp := 1'), '  LTemp := 1;'), mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TPromoteVariableTests);

end.
