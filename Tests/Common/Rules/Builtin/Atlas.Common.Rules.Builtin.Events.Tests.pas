unit Atlas.Common.Rules.Builtin.Events.Tests;

// Tests der Regel event-call-without-assigned (#946): Aufruf ohne Prüfung,
// geschützte Formen, Properties und Self., Ereignistypen, Korrektur, Optionen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEventRulesTests = class
  public
    [Test]
    procedure IssueExampleReported;
    [Test]
    procedure FixWrapsCallInAssigned;
    [Test]
    procedure GuardedCallsAreSilent;
    [Test]
    procedure EarlyExitGuards;
    [Test]
    procedure PropertiesAndSelfAreFound;
    [Test]
    procedure OnlyEventTypesCount;
    [Test]
    procedure NoFixInsideExpression;
    [Test]
    procedure InjectedAndShadowedAreSilent;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure IsKnownEventType;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Events,
  Atlas.Tests.RuleAssert;

function Zaehler(const AMembers, ABody: string): string;
begin
  Result :=
    'unit Zaehler;'#10 +
    'interface'#10 +
    'uses System.Classes;'#10 +
    'type'#10 +
    '  TZaehler = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '    FOnChange: TNotifyEvent;'#10 +
    AMembers +
    '  public'#10 +
    '    procedure Erhoehen;'#10 +
    '    property OnChange: TNotifyEvent read FOnChange write FOnChange;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TZaehler.Erhoehen;'#10 +
    'begin'#10 +
    ABody +
    'end;'#10 +
    'end.';
end;

function Body(const ABody: string): string;
begin
  Result := Zaehler('', ABody);
end;

/// <summary>Wendet alle Änderungen der Korrektur an, von hinten nach vorn (Zeilen mit #10).</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index: Integer;
  Edit: TRuleEdit;

  function OffsetOf(const APosition: TTextPosition): Integer;
  var
    Line, Position: Integer;
  begin
    Position := 0;
    for Line := 1 to APosition.Line do
      Position := Pos(#10, AText, Position + 1);
    Result := Position + APosition.Character;
  end;

begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Result := Copy(Result, 1, OffsetOf(Edit.Range.StartPos)) + Edit.NewText +
      Copy(Result, OffsetOf(Edit.Range.EndPos) + 1, MaxInt);
  end;
end;

{ TEventRulesTests }

procedure TEventRulesTests.IssueExampleReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TEventCallWithoutAssignedRule.Create, Body('  Inc(FWert);'#10'  FOnChange(Self);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('event-call-without-assigned', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('FOnChange kann nil sein; ohne Assigned-Prüfung folgt eine Zugriffsverletzung.',
    Findings[0].Message);
  Assert.AreEqual(16, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(11, Findings[0].Range.EndPos.Character);
end;

procedure TEventRulesTests.FixWrapsCallInAssigned;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := Body('  Inc(FWert);'#10'  FOnChange(Self);'#10);
  Findings := TRuleAssert.Findings(TEventCallWithoutAssignedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('In if Assigned(FOnChange) then einschließen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)));
  Fixed := ApplyFix(Source, Findings[0].Fixes[0]);
  Assert.AreEqual(Body('  Inc(FWert);'#10'  if Assigned(FOnChange) then'#10'    FOnChange(Self);'#10), Fixed);
  Tree := TPascalParser.Parse(Fixed);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create, Fixed);
end;

procedure TEventRulesTests.GuardedCallsAreSilent;
begin
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Body('  if Assigned(FOnChange) then'#10'    FOnChange(Self);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Body('  if (FWert > 0) and Assigned(Self.FOnChange) then'#10'  begin'#10'    Inc(FWert);'#10 +
    '    Self.FOnChange(Self);'#10'  end;'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Body('  if FOnChange <> nil then'#10'    FOnChange(Self);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Body('  if not Assigned(FOnChange) then'#10'    Inc(FWert)'#10'  else'#10'    FOnChange(Self);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Body('  while Assigned(FOnChange) do'#10'    FOnChange(Self);'#10));
  // Kurzschluss im selben Ausdruck.
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FBusy: TFunc<Boolean>;'#10, '  if Assigned(FBusy) and FBusy() then'#10'    Inc(FWert);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FBusy: TFunc<Boolean>;'#10, '  Writeln(Assigned(FBusy) and FBusy());'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FBusy: TFunc<Boolean>;'#10, '  if not Assigned(FBusy) or not FBusy() then'#10'    Inc(FWert);'#10));
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FBusy: TFunc<Boolean>;'#10, '  if Assigned(FOnChange) and FBusy() then'#10'    Inc(FWert);'#10));
  // Falsche Richtung: gemeldet.
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create,
    Body('  if not Assigned(FOnChange) then'#10'    FOnChange(Self);'#10));
  // Prüfung auf ein anderes Ereignis schützt nicht.
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FOnReset: TNotifyEvent;'#10, '  if Assigned(FOnReset) then'#10'    FOnChange(Self);'#10));
end;

procedure TEventRulesTests.EarlyExitGuards;
begin
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Body('  if not Assigned(FOnChange) then'#10'    Exit;'#10'  FOnChange(Self);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Body('  if FOnChange = nil then'#10'    raise EInvalidOp.Create(''kein Handler'');'#10'  FOnChange(Self);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Body('  if not Assigned(FOnChange) then'#10'  begin'#10'    Inc(FWert);'#10'    Exit;'#10'  end;'#10 +
    '  FOnChange(Self);'#10));
  // Merker: "Ok := … and Assigned(F); if not Ok then Exit;".
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FOk: Boolean;'#10, '  FOk := (FWert > 0) and Assigned(FOnChange);'#10'  if not FOk then'#10 +
    '    Exit;'#10'  FOnChange(Self);'#10));
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FOk: Boolean;'#10, '  FOk := (FWert > 0) or Assigned(FOnChange);'#10'  if not FOk then'#10 +
    '    Exit;'#10'  FOnChange(Self);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FOk: Boolean;'#10, '  FOk := (FWert > 0) and Assigned(FOnChange);'#10'  if FOk then'#10 +
    '    FOnChange(Self);'#10));
  // Prüfende Methode ohne Parameter: "if not KannMelden then Exit;".
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create, StringReplace(
    Zaehler('    function KannMelden: Boolean;'#10, '  if not KannMelden then'#10'    Exit;'#10'  FOnChange(Self);'#10),
    'implementation'#10, 'implementation'#10'function TZaehler.KannMelden: Boolean;'#10'begin'#10 +
    '  Result := (FWert > 0) and Assigned(FOnChange);'#10'end;'#10, []));
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create, StringReplace(
    Zaehler('    function KannMelden: Boolean;'#10, '  if not KannMelden then'#10'    Exit;'#10'  FOnChange(Self);'#10),
    'implementation'#10, 'implementation'#10'function TZaehler.KannMelden: Boolean;'#10'begin'#10 +
    '  Result := FWert > 0;'#10'end;'#10, []));
  // Merker, der nur ohne Handler gesetzt wird: leerer Grund heißt zugewiesen (#1109).
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FGrund: string;'#10, '  if (FWert > 0) and not Assigned(FOnChange) then'#10'    FGrund := ''aus'';'#10 +
    '  if FGrund = '''' then'#10'    FOnChange(Self);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FAus: Boolean;'#10, '  if not Assigned(FOnChange) then'#10'    FAus := True;'#10 +
    '  if not FAus and (FWert > 0) then'#10'    FOnChange(Self);'#10));
  // Ein Merker, der auch ohne Handler leer bleibt, schützt nicht.
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FGrund: string;'#10, '  if not Assigned(FOnChange) then'#10'    FGrund := '''';'#10 +
    '  if FGrund = '''' then'#10'    FOnChange(Self);'#10));
  // Die Prüfung nach dem Aufruf schützt nicht.
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create,
    Body('  FOnChange(Self);'#10'  if not Assigned(FOnChange) then'#10'    Exit;'#10));
end;

procedure TEventRulesTests.PropertiesAndSelfAreFound;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TEventCallWithoutAssignedRule.Create, Body('  OnChange(Self);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('OnChange kann nil sein; ohne Assigned-Prüfung folgt eine Zugriffsverletzung.',
    Findings[0].Message);
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create, Body('  Self.FOnChange(Self);'#10));
  // Aufruf über ein anderes Objekt und Weitergabe als Argument bleiben still.
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create, Body('  Anderer.FOnChange(Self);'#10));
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create, Body('  Melden(FOnChange);'#10'  FOnChange := nil;'#10));
  // Ereignis ohne Argumente als eigene Anweisung.
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FOnIdle: TProc;'#10, '  FOnIdle;'#10));
end;

procedure TEventRulesTests.OnlyEventTypesCount;
const
  Source =
    'unit Zaehler;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TWertProc = reference to procedure(AWert: Integer);'#10 +
    '  TFormat = function(AWert: Integer): string of object;'#10 +
    '  TListe = array of Integer;'#10 +
    '  TZaehler = class'#10 +
    '  private'#10 +
    '    FMelden: TWertProc;'#10 +
    '    FFormat: TFormat;'#10 +
    '    FBerechnen: procedure(AWert: Integer) of object;'#10 +
    '    FAenderung: TZaehlerChangeEvent;'#10 +
    '    FListe: TListe;'#10 +
    '    function Wert(A: Integer): Integer;'#10 +
    '    procedure Erhoehen;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TZaehler.Wert(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A;'#10 +
    'end;'#10 +
    'procedure TZaehler.Erhoehen;'#10 +
    'begin'#10 +
    '  FMelden(1);'#10 +
    '  Writeln(FFormat(2));'#10 +
    '  FBerechnen(3);'#10 +
    '  FAenderung(Self, 4);'#10 +
    '  Writeln(Wert(5));'#10 +
    '  FListe[0] := 6;'#10 +
    'end;'#10 +
    'end.';
begin
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create, Source, 4);
end;

procedure TEventRulesTests.NoFixInsideExpression;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TEventCallWithoutAssignedRule.Create,
    Zaehler('    FOnText: TFunc<string>;'#10, '  Writeln(FOnText());'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Nach "then" in derselben Zeile ebenfalls keine Korrektur.
  Findings := TRuleAssert.Findings(TEventCallWithoutAssignedRule.Create,
    Body('  if FWert > 0 then FOnChange(Self);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TEventRulesTests.InjectedAndShadowedAreSilent;
const
  Source =
    'unit Leser;'#10 +
    'interface'#10 +
    'uses System.SysUtils;'#10 +
    'type'#10 +
    '  TLeser = class'#10 +
    '  private'#10 +
    '    FReadText: TFunc<string, string>;'#10 +
    '    FOnFertig: TProc;'#10 +
    '  public'#10 +
    '    constructor Create(const AReadText: TFunc<string, string>);'#10 +
    '    procedure Lesen;'#10 +
    '    property ReadText: TFunc<string, string> read FReadText;'#10 +
    '    property OnFertig: TProc read FOnFertig write FOnFertig;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TLeser.Create(const AReadText: TFunc<string, string>);'#10 +
    'begin'#10 +
    '  FReadText := AReadText;'#10 +
    '  FOnFertig := nil;'#10 +
    'end;'#10 +
    'procedure TLeser.Lesen;'#10 +
    'var'#10 +
    '  OnFertig: TProc;'#10 +
    'begin'#10 +
    '  Writeln(FReadText(''a.pas''));'#10 +
    '  Writeln(ReadText(''b.pas''));'#10 +
    '  OnFertig := procedure begin end;'#10 +
    '  OnFertig();'#10 +
    '  FOnFertig();'#10 +
    'end;'#10 +
    'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  // Der Konstruktor belegt FReadText: eine Abhängigkeit, kein Ereignis. FOnFertig := nil zählt nicht.
  Findings := TRuleAssert.Findings(TEventCallWithoutAssignedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('FOnFertig kann nil sein; ohne Assigned-Prüfung folgt eine Zugriffsverletzung.',
    Findings[0].Message);
  // Ohne schreibbare Property zählt jede Methode, die das Feld belegt (Starten(AOnDone)).
  TRuleAssert.Silent(TEventCallWithoutAssignedRule.Create, StringReplace(StringReplace(Source,
    '    property OnFertig: TProc read FOnFertig write FOnFertig;'#10, '', []), '  OnFertig := procedure',
    '  FOnFertig := procedure begin end;'#10'  OnFertig := procedure', []));
  // Mit schreibbarer Property nur der Konstruktor: eine andere Methode mit Zuweisung schützt nicht.
  TRuleAssert.Reports(TEventCallWithoutAssignedRule.Create, StringReplace(Source, '  OnFertig := procedure',
    '  FOnFertig := procedure begin end;'#10'  OnFertig := procedure', []), 1);
end;

procedure TEventRulesTests.OffAndExclude;
var
  Source: string;
begin
  Source := Body('  FOnChange(Self);'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEventCallWithoutAssignedRule.Create, Source,
    '{"rules": {"event-call-without-assigned": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEventCallWithoutAssignedRule.Create, Source,
    '{"rules": {"event-call-without-assigned": {"exclude": ["Source/*.pas"]}}}', 'Source/Zaehler.pas'))));
end;

procedure TEventRulesTests.IsKnownEventType;
begin
  Assert.IsTrue(TEventCallWithoutAssignedRule.IsKnownEventType('TNotifyEvent'));
  Assert.IsTrue(TEventCallWithoutAssignedRule.IsKnownEventType('System.Classes.TNotifyEvent'));
  Assert.IsTrue(TEventCallWithoutAssignedRule.IsKnownEventType('TFunc<Integer>'));
  Assert.IsTrue(TEventCallWithoutAssignedRule.IsKnownEventType('TKeyPressEvent'));
  Assert.IsTrue(TEventCallWithoutAssignedRule.IsKnownEventType('reference to procedure'));
  Assert.IsTrue(TEventCallWithoutAssignedRule.IsKnownEventType('procedure(A: Integer) of object'));
  Assert.IsFalse(TEventCallWithoutAssignedRule.IsKnownEventType('TEvent'));
  Assert.IsFalse(TEventCallWithoutAssignedRule.IsKnownEventType('TStringList'));
  Assert.IsFalse(TEventCallWithoutAssignedRule.IsKnownEventType('Integer'));
end;

initialization
  TDUnitX.RegisterTestFixture(TEventRulesTests);

end.
