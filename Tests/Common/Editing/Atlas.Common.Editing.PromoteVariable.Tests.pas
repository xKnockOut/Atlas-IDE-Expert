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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.PromoteVariable,
  Atlas.Text.Lines;

const
  LF = #10;

function Lines(const ALines: array of string): string;
var
  Line: string;
begin
  Result := '';
  for Line in ALines do
    Result := Result + Line + LF;
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

/// <summary>Umwandlung an AMarker mit AName ('' = Vorschlag); AResult ist der Text, der fehlerfrei parsen muss.
/// </summary>
function Run(const AText, AMarker, AName: string; out ATarget: TPromoteTarget; out APromoted: TPromoteResult;
  out AReason, AResult: string): Boolean;
var
  Tree, Check: TSyntaxTree;
  Name: string;
begin
  AResult := '';
  APromoted := Default(TPromoteResult);
  Tree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Quelle parst nicht: ' + AText);
    Result := TPromoteVariable.Target(AText, Tree, PositionOf(AText, AMarker), TestLookup(Tree), ATarget, AReason);
    if not Result then
      Exit;
    Name := AName;
    if Name = '' then
      Name := ATarget.Suggested;
    Result := TPromoteVariable.Execute(AText, Tree, PositionOf(AText, AMarker), TestLookup(Tree),
      TFormatStyle.Default, Name, APromoted, AReason);
    if Result then
    begin
      AResult := TChangeSignature.ApplyEdits(AText, APromoted.Edits);
      Check := TPascalParser.Parse(AResult);
      try
        Assert.AreEqual(0, Integer(Length(Check.Diagnostics)), 'Ergebnis parst nicht: ' + AResult);
      finally
        Check.Free;
      end;
    end;
  finally
    Tree.Free;
  end;
end;

function Promoted(const AText, AMarker: string; out ATarget: TPromoteTarget; out AResult: TPromoteResult): string;
var
  Reason: string;
begin
  Assert.IsTrue(Run(AText, AMarker, '', ATarget, AResult, Reason, Result), 'Aktion fehlt (' + Reason + '): ' + AText);
end;

function PromotedText(const AText, AMarker: string): string;
var
  Target: TPromoteTarget;
  Promote: TPromoteResult;
begin
  Result := Promoted(AText, AMarker, Target, Promote);
end;

function Refused(const AText, AMarker: string): string;
var
  Target: TPromoteTarget;
  Promote: TPromoteResult;
  Text: string;
begin
  Assert.IsFalse(Run(AText, AMarker, '', Target, Promote, Result, Text), 'Aktion unerwartet: ' + Text);
  Assert.AreNotEqual('', Result);
end;

/// <summary>Grund, aus dem die Umwandlung mit dem Namen AName scheitert (die Aktion wird angeboten).</summary>
function RefusedName(const AText, AMarker, AName: string): string;
var
  Target: TPromoteTarget;
  Promote: TPromoteResult;
  Text: string;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Assert.IsTrue(TPromoteVariable.Target(AText, Tree, PositionOf(AText, AMarker), TestLookup(Tree), Target, Result),
      Result);
  finally
    Tree.Free;
  end;
  Assert.IsFalse(Run(AText, AMarker, AName, Target, Promote, Result, Text), 'Aktion unerwartet: ' + Text);
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
  Text, Done: string;
  Target: TPromoteTarget;
  Promote: TPromoteResult;
begin
  Text := ClassUnit(Lines(['  private', '    FCount: Integer;', '    procedure Show;', '  public',
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
  Done := Promoted(Text, 'LLineNo:', Target, Promote);
  // Der Pfeil steht zwischen den Namen (ohne ihn zu vergleichen: der FPC-Lauf liest ihn anders).
  Assert.IsTrue(StartsStr(TPromoteVariable.ToFieldTitle + ' (LLineNo ', Target.Title), Target.Title);
  Assert.IsTrue(EndsStr(' FLineNo)', Target.Title), Target.Title);
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
    'end;'])), Done);
  Assert.AreEqual(5, Promote.Places);
  Assert.AreEqual(0, Integer(Length(Promote.Warnings)));
  // Auch von einer Verwendung aus; der einzige Eintrag nimmt var mit.
  Text := ClassUnit(Lines(['  private', '    procedure Run;']), Lines(['procedure TFoo.Run;', 'var', '  Total: Integer;',
    'begin', '  Total := 1;', 'end;']));
  Assert.AreEqual(ClassUnit(Lines(['  private', '    FTotal: Integer;', '    procedure Run;']),
    Lines(['procedure TFoo.Run;', 'begin', '  FTotal := 1;', 'end;'])), PromotedText(Text, 'Total := 1'));
end;

procedure TPromoteVariableTests.InlineVariableKeepsAssignment;
var
  Text: string;
begin
  Text := ClassUnit(Lines(['  private', '    FCount: Integer;', '  public', '    procedure Run;']), Lines([
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
    'end;'])), PromotedText(Text, 'LSum:'));
  // Ohne Typangabe: Typ aus der Ableitung.
  Assert.IsTrue(ContainsStr(PromotedText(Text, 'LNext :='), '    FNext: Integer;' + LF), Text);
  Assert.IsTrue(ContainsStr(PromotedText(Text, 'LNext :='), '  FNext := LSum + 1;' + LF), Text);
  // Ohne Startwert verschwindet die Zeile.
  Assert.IsTrue(ContainsStr(PromotedText(Text, 'LText:'), 'begin' + LF + '  var LSum: Integer := 0;' + LF +
    '  var LNext := LSum + 1;' + LF + '  FText := ''a'';' + LF), PromotedText(Text, 'LText:'));
  Assert.IsTrue(ContainsStr(PromotedText(Text, 'LText:'), '    FText: string;' + LF), Text);
end;

procedure TPromoteVariableTests.NewPrivateSectionAndRecord;
var
  Text: string;
begin
  // Kein private-Abschnitt: ein neuer vor end.
  Text := ClassUnit(Lines(['  public', '    procedure Run;']), Lines(['procedure TFoo.Run;', 'var', '  LValue: Double;',
    'begin', '  LValue := 1.5;', 'end;']));
  Assert.AreEqual(ClassUnit(Lines(['  public', '    procedure Run;', '  private', '    FValue: Double;']),
    Lines(['procedure TFoo.Run;', 'begin', '  FValue := 1.5;', 'end;'])), PromotedText(Text, 'LValue:'));
  // Record mit Methode: entsprechend.
  Text := Lines(['unit U;', '', 'interface', '', 'type', '  TPoint3 = record', '  private', '    FX: Integer;',
    '  public', '    procedure Reset;', '  end;', '', 'implementation', '', 'procedure TPoint3.Reset;', 'var',
    '  LY: Integer;', 'begin', '  LY := 0;', '  FX := LY;', 'end;', '', 'end.']);
  Assert.AreEqual(Lines(['unit U;', '', 'interface', '', 'type', '  TPoint3 = record', '  private', '    FX: Integer;',
    '    FY: Integer;', '  public', '    procedure Reset;', '  end;', '', 'implementation', '',
    'procedure TPoint3.Reset;', 'begin', '  FY := 0;', '  FX := FY;', 'end;', '', 'end.']), PromotedText(Text, 'LY:'));
end;

procedure TPromoteVariableTests.FieldNameConflicts;
var
  Text: string;
begin
  Text := ClassUnit(Lines(['  private', '    FTotal: Integer;', '  public', '    procedure Run;', '    procedure Other;']),
    Lines(['procedure TFoo.Run;', 'var', '  LSum, LTemp: Integer;', 'begin', '  LSum := FTotal;', '  LTemp := 0;',
    'end;', '', 'procedure TFoo.Other;', 'begin', '  Global := 1;', 'end;']));
  // Vorhandenes und geerbtes Mitglied, lokaler Name, anderer Bezeichner in einer Methode der Klasse, ungültig.
  Assert.IsTrue(ContainsText(RefusedName(Text, 'LSum,', 'FTotal'), 'Mitglied'));
  Assert.IsTrue(ContainsText(RefusedName(Text, 'LSum,', 'FBase'), 'erbt'));
  Assert.IsTrue(ContainsText(RefusedName(Text, 'LSum,', 'LTemp'), 'deklariert'));
  Assert.IsTrue(ContainsText(RefusedName(Text, 'LSum,', 'Global'), 'anderes'));
  Assert.IsTrue(ContainsText(RefusedName(Text, 'LSum,', 'begin'), 'Name'));
  Assert.IsTrue(ContainsText(RefusedName(Text, 'LSum,', '1X'), 'Name'));
  // Ein freier, selbst gewählter Name geht.
  Assert.IsTrue(ContainsStr(PromotedText(Text, 'LSum,'), '  FSum := FTotal;'), Text);
end;

procedure TPromoteVariableTests.FieldWarnings;
var
  Text: string;
  Target: TPromoteTarget;
  Promote: TPromoteResult;
begin
  Text := ClassUnit(Lines(['  public', '    procedure Run(N: Integer);']), Lines(['procedure TFoo.Run(N: Integer);',
    'var', '  LList: TObject;', 'begin', '  LList := TObject.Create;', '  try', '    if N > 0 then', '      Run(N - 1);',
    '  finally', '    LList.Free;', '  end;', 'end;']));
  Promoted(Text, 'LList:', Target, Promote);
  Assert.AreEqual(2, Integer(Length(Promote.Warnings)));
  Assert.IsTrue(ContainsText(Promote.Warnings[0], 'freigegeben'), Promote.Warnings[0]);
  Assert.IsTrue(ContainsText(Promote.Warnings[1], 'selbst'), Promote.Warnings[1]);
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
  Text, Done: string;
  Target: TPromoteTarget;
  Promote: TPromoteResult;
begin
  Text := ClassUnit(Lines(['  private', '    FA, FLineNo: Integer;', '  public', '    procedure Run;',
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
  Done := Promoted(Text, 'FLineNo:', Target, Promote);
  Assert.IsTrue(StartsStr(TPromoteVariable.ToLocalTitle + ' (FLineNo ', Target.Title), Target.Title);
  Assert.IsTrue(EndsStr(' LLineNo)', Target.Title), Target.Title);
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
    'end;'])), Done);
  // Ohne var-Abschnitt entsteht einer.
  Text := ClassUnit(Lines(['  private', '    FTemp: string;', '  public', '    procedure Run;']),
    Lines(['procedure TFoo.Run;', 'begin', '  FTemp := ''x'';', '  Writeln(FTemp);', 'end;']));
  Assert.AreEqual(ClassUnit(Lines(['  public', '    procedure Run;']), Lines(['procedure TFoo.Run;', 'var',
    '  LTemp: string;', 'begin', '  LTemp := ''x'';', '  Writeln(LTemp);', 'end;'])), PromotedText(Text, 'FTemp:'));
end;

procedure TPromoteVariableTests.LocalRefusals;
var
  Members, Run: string;
begin
  Members := Lines(['  private', '    FTemp: Integer;', '  public', '    procedure Run;', '    procedure Other;']);
  Run := Lines(['procedure TFoo.Run;', 'begin', '  FTemp := 1;', '  Other;', 'end;', '']);
  // Zweite Methode.
  Assert.IsTrue(ContainsText(Refused(ClassUnit(Members, Run + Lines(['procedure TFoo.Other;', 'begin',
    '  FTemp := 2;', 'end;'])), 'FTemp:'), 'mehreren'));
  // Lesen vor Schreiben, nicht auf jedem Weg geschrieben.
  Assert.IsTrue(ContainsText(Refused(ClassUnit(Members, Lines(['procedure TFoo.Run;', 'begin', '  Inc(FTemp);', 'end;',
    '', 'procedure TFoo.Other;', 'begin', 'end;'])), 'FTemp:'), 'zuerst'));
  Assert.IsTrue(ContainsText(Refused(ClassUnit(Members, Lines(['procedure TFoo.Run;', 'begin', '  if Tag = 0 then',
    '    FTemp := 1;', '  Other(FTemp);', 'end;', '', 'procedure TFoo.Other;', 'begin', 'end;'])), 'FTemp:'), 'zuerst'));
  // Property, Formular, published, lokale Routine, nicht benutzt.
  Refused(ClassUnit(Members + Lines(['    property Temp: Integer read FTemp;']), Run + Lines(['procedure TFoo.Other;',
    'begin', 'end;'])), 'FTemp:');
  Refused(ClassUnit(Lines(['  private', '    FForm: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;', 'begin', '  FForm := 1;', 'end;'])), 'FForm:');
  Refused(ClassUnit(Lines(['  published', '    FTemp: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;', 'begin', '  FTemp := 1;', 'end;'])), 'FTemp:');
  Refused(ClassUnit(Lines(['  private', '    FTemp: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;', '', '  procedure Inner;', '  begin', '    FTemp := 1;', '  end;', '', 'begin', '  Inner;',
    'end;'])), 'FTemp:');
  Refused(ClassUnit(Members, Lines(['procedure TFoo.Run;', 'begin', 'end;', '', 'procedure TFoo.Other;', 'begin',
    'end;'])), 'FTemp:');
  // Über ein anderes Objekt.
  Refused(ClassUnit(Members, Lines(['procedure TFoo.Run;', 'begin', '  FTemp := 1;', 'end;', '',
    'procedure TFoo.Other;', 'var', '  Foo: TFoo;', 'begin', '  Foo.FTemp := 1;', 'end;'])), 'FTemp:');
end;

procedure TPromoteVariableTests.TargetFromUsage;
var
  Text: string;
begin
  // Cursor auf der Verwendung eines Felds in der Methode.
  Text := ClassUnit(Lines(['  private', '    FTemp: Integer;', '  public', '    procedure Run;']), Lines([
    'procedure TFoo.Run;', 'begin', '  FTemp := 1;', 'end;']));
  Assert.IsTrue(ContainsStr(PromotedText(Text, 'FTemp := 1'), '  LTemp := 1;'), Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TPromoteVariableTests);

end.
