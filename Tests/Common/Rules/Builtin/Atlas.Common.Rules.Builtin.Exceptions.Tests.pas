unit Atlas.Common.Rules.Builtin.Exceptions.Tests;

// Tests für die Exception-Regeln (#277): je Regel ein positiver und ein negativer Fall;
// exception-in-destructor (#927). reraise-outside-handler (#985): Beispiel aus dem Issue,
// lokale Prozedur, anonyme Methode, finally, stille Fälle, Abschalten, Gruppe und Ausnahmen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExceptionRulesTests = class
  public
    [Test]
    procedure GenericExceptionReported;
    [Test]
    procedure OwnExceptionClassSilent;
    [Test]
    procedure CatchAllWithoutRaiseReportedWhenEnabled;
    [Test]
    procedure CatchAllWithRaiseOrSpecificSilent;
    [Test]
    procedure FreedInHandlerReported;
    [Test]
    procedure FreedAfterRaiseReported;
    [Test]
    procedure NoDoubleFreeSilent;
    [Test]
    procedure ExceptionInDestructorIssueExample;
    [Test]
    procedure ExceptionInDestructorVariants;
    [Test]
    procedure ExceptionInDestructorSilentCases;
    [Test]
    procedure ExceptHandlerOrderIssueExample;
    [Test]
    procedure ExceptHandlerOrderVariants;
    [Test]
    procedure ExceptHandlerOrderSilentCases;
    [Test]
    procedure ExceptHandlerOrderOffAndExclude;
    [Test]
    procedure ReraiseIssueExample;
    [Test]
    procedure ReraiseVariants;
    [Test]
    procedure ReraiseSilentCases;
    [Test]
    procedure ReraiseOffAndExclude;
    [Test]
    procedure InheritedConstructorIssueExample;
    [Test]
    procedure InheritedConstructorVariants;
    [Test]
    procedure InheritedConstructorSilentCases;
    [Test]
    procedure InheritedConstructorOffAndExclude;
  end;

  [TestFixture]
  TReraiseOutsideHandlerTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure LocalRoutineAndAnonymousMethod;
    [Test]
    procedure HandlersAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Exceptions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

const
  CatchAllOn = '{ "rules": { "catch-all-without-raise": "warning" } }';

function InRoutine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TExceptionRulesTests.GenericExceptionReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TGenericExceptionRaisedRule.Create,
    InRoutine('  raise Exception.Create(''Kunde fehlt'');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  TRuleAssert.Reports(TGenericExceptionRaisedRule.Create,
    InRoutine('  raise System.SysUtils.Exception.CreateFmt(''%d'', [N]);'));
  // Gleich wieder gefangen, nur für den Stack im Protokoll (#1109).
  TRuleAssert.Silent(TGenericExceptionRaisedRule.Create, InRoutine('  try'#10 +
    '    raise Exception.Create(''Stack'');'#10'  except'#10'    on E: Exception do'#10'      Log(E.StackTrace);'#10 +
    '  end;'));
  // Ein except, der nur andere Klassen fängt, lässt sie durch.
  TRuleAssert.Reports(TGenericExceptionRaisedRule.Create, InRoutine('  try'#10 +
    '    raise Exception.Create(''x'');'#10'  except'#10'    on E: EConvertError do'#10'      Log(E.Message);'#10 +
    '  end;'));
end;

procedure TExceptionRulesTests.OwnExceptionClassSilent;
begin
  TRuleAssert.Silent(TGenericExceptionRaisedRule.Create,
    InRoutine('  raise EKundeFehlt.Create(''Kunde fehlt'');'#10 +
    '  raise EArgumentException.Create(''X'');'#10'  raise;'));
end;

procedure TExceptionRulesTests.CatchAllWithoutRaiseReportedWhenEnabled;
const
  Source = '  try'#10'    Save;'#10'  except'#10'    on E: Exception do'#10'      Log(E.Message);'#10'  end;';
var
  Findings: TArray<TRuleFinding>;
begin
  // Ohne Profil für Bibliothekscode aus.
  TRuleAssert.Silent(TCatchAllWithoutRaiseRule.Create, InRoutine(Source));
  Findings := TRuleAssert.Findings(TCatchAllWithoutRaiseRule.Create, InRoutine(Source), CatchAllOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
end;

procedure TExceptionRulesTests.CatchAllWithRaiseOrSpecificSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TCatchAllWithoutRaiseRule.Create,
    InRoutine('  try Save; except on E: Exception do begin Log(E.Message); raise; end; end;'#10 +
    '  try Save; except on E: EInOutError do Log(E.Message); end;'), CatchAllOn))));
end;

procedure TExceptionRulesTests.FreedInHandlerReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TExceptionFreedRule.Create,
    InRoutine('  try Save; except on E: Exception do begin Log(E.Message); E.Free; end; end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  TRuleAssert.Reports(TExceptionFreedRule.Create,
    InRoutine('  try Save; except on Fehler: EInOutError do FreeAndNil(Fehler); end;'));
end;

procedure TExceptionRulesTests.FreedAfterRaiseReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TExceptionFreedRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P;'#10'var'#10'  E: EKunde;'#10'begin'#10'  E := EKunde.Create(''X'');'#10'  try'#10 +
    '    raise E;'#10'  finally'#10'    E.Free;'#10'  end;'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
end;

procedure TExceptionRulesTests.NoDoubleFreeSilent;
begin
  TRuleAssert.Silent(TExceptionFreedRule.Create,
    InRoutine('  try Save; except on E: Exception do Log(E.Message); end;'#10 +
    '  Liste.Free;'#10'  raise EKunde.Create(''X'');'));
  TRuleAssert.Silent(TExceptionFreedRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure A;'#10'begin'#10'  raise E;'#10'end;'#10'procedure B;'#10'begin'#10'  E.Free;'#10'end;'#10'end.');
end;

function Sitzung(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TSitzung = class'#10'    FOffen: Boolean;'#10 +
    '    destructor Destroy; override;'#10'  end;'#10'implementation'#10'destructor TSitzung.Destroy;'#10 +
    'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TExceptionRulesTests.ExceptionInDestructorIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TExceptionInDestructorRule.Create, Sitzung('  if FOffen then'#10 +
    '    raise ESitzung.Create(''Sitzung noch offen'');'#10'  inherited;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('raise im Destruktor: inherited Destroy läuft nicht mehr, Felder bleiben liegen.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(4, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Korrigiert: Zustand protokollieren statt auslösen.
  TRuleAssert.Silent(TExceptionInDestructorRule.Create, Sitzung('  if FOffen then'#10 +
    '    Schliessen;'#10'  inherited;'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExceptionInDestructorRule.Create,
    Sitzung('  raise ESitzung.Create(''x'');'), '{"rules": {"exception-in-destructor": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExceptionInDestructorRule.Create,
    Sitzung('  raise ESitzung.Create(''x'');'), '{"rules": {"exception-in-destructor": {"exclude": ["Alt/*.pas"]}}}',
    'Alt/U.pas'))));
end;

procedure TExceptionRulesTests.ExceptionInDestructorVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Nach inherited, im finally, erneutes raise im except-Teil, class destructor.
  Findings := TRuleAssert.Findings(TExceptionInDestructorRule.Create, Sitzung('  try'#10'    Speichern;'#10 +
    '  finally'#10'    inherited;'#10'  end;'#10'  if FOffen then'#10'    raise ESitzung.Create(''x'');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('raise im Destruktor: die Ausnahme verlässt Destroy, der Aufrufer erwartet eine Freigabe ohne ' +
    'Ausnahme.', Findings[0].Message);
  TRuleAssert.Reports(TExceptionInDestructorRule.Create, Sitzung('  try'#10'    Speichern;'#10'  finally'#10 +
    '    raise ESitzung.Create(''x'');'#10'  end;'));
  TRuleAssert.Reports(TExceptionInDestructorRule.Create, Sitzung('  try'#10'    Speichern;'#10'  except'#10 +
    '    Protokoll;'#10'    raise;'#10'  end;'));
  TRuleAssert.Reports(TExceptionInDestructorRule.Create, 'unit U;'#10'interface'#10'type'#10'  TListe = class'#10 +
    '    class destructor Destroy;'#10'  end;'#10'implementation'#10'class destructor TListe.Destroy;'#10 +
    'begin'#10'  raise EListe.Create(''x'');'#10'end;'#10'end.');
end;

procedure TExceptionRulesTests.ExceptionInDestructorSilentCases;
begin
  // Abgefangen im try-Teil, andere Methode, eingebettete Routine und anonyme Methode.
  TRuleAssert.Silent(TExceptionInDestructorRule.Create, Sitzung('  try'#10'    if FOffen then'#10 +
    '      raise ESitzung.Create(''x'');'#10'  except'#10'    on E: ESitzung do'#10'      Protokoll(E);'#10'  end;'#10 +
    '  inherited;'));
  TRuleAssert.Silent(TExceptionInDestructorRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure TSitzung.Schliessen;'#10'begin'#10'  raise ESitzung.Create(''x'');'#10'end;'#10'end.');
  TRuleAssert.Silent(TExceptionInDestructorRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'destructor TSitzung.Destroy;'#10'  procedure Pruefen;'#10'  begin'#10'    raise ESitzung.Create(''x'');'#10 +
    '  end;'#10'begin'#10'  FAufgabe := procedure'#10'    begin'#10'      raise ESitzung.Create(''x'');'#10 +
    '    end;'#10'  inherited;'#10'end;'#10'end.');
end;

function Handler(const AHandlers: string): string;
begin
  Result := InRoutine('  try'#10'    Wert := StrToInt(Text);'#10'  except'#10 + AHandlers + '  end;');
end;

procedure TExceptionRulesTests.ExceptHandlerOrderIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Handler('    on E: Exception do'#10'      Protokoll(E.Message);'#10 +
    '    on E: EConvertError do'#10'      ShowMessage(''Ungültige Zahl'');'#10);
  Findings := TRuleAssert.Findings(TExceptHandlerOrderRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('except-handler-order', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('Nie erreicht: EConvertError ist ein Nachfahr von Exception, das schon in Zeile 9 behandelt wird.',
    Findings[0].Message);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('on EConvertError vor on Exception verschieben', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Handler('    on E: EConvertError do'#10'      ShowMessage(''Ungültige Zahl'');'#10 +
    '    on E: Exception do'#10'      Protokoll(E.Message);'#10), Fixed);
  TRuleAssert.Silent(TExceptHandlerOrderRule.Create, Fixed);
end;

procedure TExceptionRulesTests.ExceptHandlerOrderVariants;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Doppelter Handler: keine Korrektur.
  Findings := TRuleAssert.Findings(TExceptHandlerOrderRule.Create, Handler('    on E: EConvertError do'#10 +
    '      Protokoll(E.Message);'#10'    on EConvertError do'#10'      Abbrechen;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Nie erreicht: EConvertError wird schon in Zeile 9 behandelt.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Bekannte Hierarchie über zwei Stufen; letzter Handler ohne Semikolon, danach else.
  Source := Handler('    on E: EStreamError do'#10'      Protokoll(E.Message);'#10 +
    '    on E: EFOpenError do'#10'      begin'#10'        Abbrechen;'#10'      end'#10'  else'#10'    raise;'#10);
  Findings := TRuleAssert.Findings(TExceptHandlerOrderRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Nie erreicht: EFOpenError ist ein Nachfahr von EStreamError, das schon in Zeile 9 behandelt wird.',
    Findings[0].Message);
  Assert.AreEqual(Handler('    on E: EFOpenError do'#10'      begin'#10'        Abbrechen;'#10'      end;'#10 +
    '    on E: EStreamError do'#10'      Protokoll(E.Message);'#10'  else'#10'    raise;'#10),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  // Eigene Hierarchie aus der Unit, TObject, geschachteltes try.
  Findings := TRuleAssert.Findings(TExceptHandlerOrderRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  EBasis = class(Exception);'#10'  EKunde = class(EBasis);'#10'implementation'#10'procedure P;'#10'begin'#10 +
    '  try'#10'    try'#10'      Laden;'#10'    except'#10'      on EBasis do Abbrechen;'#10 +
    '      on E: EKunde do Melden(E);'#10'    end;'#10'  except'#10'    on TObject do Abbrechen;'#10 +
    '    on E: Exception do Melden(E);'#10'  end;'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Nie erreicht: Exception ist ein Nachfahr von TObject, das schon in Zeile 17 behandelt wird.',
    Findings[1].Message);
  Assert.AreEqual('Nie erreicht: EKunde ist ein Nachfahr von EBasis, das schon in Zeile 13 behandelt wird.',
    Findings[0].Message);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  // Beide Handler in einer Zeile: gemeldet, aber ohne Korrektur.
  Findings := TRuleAssert.Findings(TExceptHandlerOrderRule.Create, Handler(
    '    on Exception do Abbrechen; on SysUtils.EConvertError do Melden;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('EIntError', TExceptHandlerOrderRule.KnownParent('ERangeError'));
  Assert.AreEqual('', TExceptHandlerOrderRule.KnownParent('EFremd'));
end;

procedure TExceptionRulesTests.ExceptHandlerOrderSilentCases;
begin
  // Speziell vor allgemein, unverwandte Klassen, unbekannte Klassen untereinander, Exception nach TObject-fremdem.
  TRuleAssert.Silent(TExceptHandlerOrderRule.Create, Handler('    on E: EConvertError do'#10'      Melden;'#10 +
    '    on E: EInOutError do'#10'      Melden;'#10'    on E: EFremd do'#10'      Melden;'#10 +
    '    on E: EAnders do'#10'      Melden;'#10'    on E: Exception do'#10'      Protokoll(E.Message);'#10));
  TRuleAssert.Silent(TExceptHandlerOrderRule.Create, Handler('    on E: EDivByZero do Melden;'#10 +
    '    on E: EMathError do Melden;'#10'    on E: EIntError do Melden;'#10));
  TRuleAssert.Silent(TExceptHandlerOrderRule.Create, Handler('    Protokoll;'#10));
end;

procedure TExceptionRulesTests.ExceptHandlerOrderOffAndExclude;
var
  Source: string;
begin
  Source := Handler('    on Exception do Abbrechen;'#10'    on EConvertError do Melden;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExceptHandlerOrderRule.Create, Source,
    '{"rules": {"except-handler-order": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TExceptHandlerOrderRule.Create, Source,
    '{"rules": {"except-handler-order": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
end;

procedure TExceptionRulesTests.ReraiseIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Handler('    on E: EDatenbank do'#10'    begin'#10'      Protokoll(E.Message);'#10'      raise E;'#10 +
    '    end;'#10);
  Findings := TRuleAssert.Findings(TReraiseExceptionObjectRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('reraise-exception-object', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('raise E löst das Objekt neu aus: Absprungstelle (ExceptAddr) und Aufrufliste zeigen danach auf ' +
    'diesen Handler statt auf den ursprünglichen Fehler; raise; wirft die Exception unverändert weiter.',
    Findings[0].Message);
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(13, Findings[0].Range.EndPos.Character);
  Assert.AreEqual('raise E; durch raise; ersetzen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Handler('    on E: EDatenbank do'#10'    begin'#10'      Protokoll(E.Message);'#10 +
    '      raise;'#10'    end;'#10), Fixed);
  TRuleAssert.Silent(TReraiseExceptionObjectRule.Create, Fixed);
end;

procedure TExceptionRulesTests.ReraiseVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Ohne begin, vor else, im inneren try, mit at (ohne Korrektur), anderer Name.
  Findings := TRuleAssert.Findings(TReraiseExceptionObjectRule.Create, Handler(
    '    on Fehler: EConvertError do raise Fehler'#10'  else'#10'    raise;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Findings := TRuleAssert.Findings(TReraiseExceptionObjectRule.Create, Handler(
    '    on E: Exception do'#10'    begin'#10'      try'#10'        Aufraeumen;'#10'      except'#10 +
    '        on F: EInOutError do'#10'          raise E;'#10'      end;'#10'      raise E at ReturnAddress;'#10 +
    '    end;'#10));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
end;

procedure TExceptionRulesTests.ReraiseSilentCases;
begin
  // raise;, neue Exception, Handler ohne Namen, AcquireExceptionObject, neu zugewiesen, anonyme Methode, außerhalb.
  TRuleAssert.Silent(TReraiseExceptionObjectRule.Create, Handler('    on E: EDatenbank do'#10'      raise;'#10 +
    '    on E: EConvertError do'#10'      raise EEingabe.Create(E.Message);'#10'    on EInOutError do'#10 +
    '      raise E;'#10));
  TRuleAssert.Silent(TReraiseExceptionObjectRule.Create, Handler('    on E: EDatenbank do'#10'    begin'#10 +
    '      AcquireExceptionObject;'#10'      Merken(E);'#10'      raise E;'#10'    end;'#10));
  TRuleAssert.Silent(TReraiseExceptionObjectRule.Create, Handler('    on E: EDatenbank do'#10'    begin'#10 +
    '      E := EDatenbank.Create(''Neu'');'#10'      raise E;'#10'    end;'#10));
  TRuleAssert.Silent(TReraiseExceptionObjectRule.Create, Handler('    on E: EDatenbank do'#10 +
    '      TThread.Queue(nil, procedure begin raise E; end);'#10));
  TRuleAssert.Silent(TReraiseExceptionObjectRule.Create, InRoutine('  E := EDatenbank.Create(''x'');'#10 +
    '  raise E;'));
end;

procedure TExceptionRulesTests.ReraiseOffAndExclude;
var
  Source: string;
begin
  Source := Handler('    on E: EDatenbank do'#10'      raise E;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TReraiseExceptionObjectRule.Create, Source,
    '{"rules": {"reraise-exception-object": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TReraiseExceptionObjectRule.Create, Source,
    '{"rules": {"reraise-exception-object": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
end;

{ TReraiseOutsideHandlerTests }

function Import(const AStatements: string): string;
begin
  Result := 'unit Importe;'#10'interface'#10'implementation'#10'procedure TImport.Abbrechen;'#10'begin'#10 +
    AStatements + 'end;'#10'end.';
end;

procedure TReraiseOutsideHandlerTests.IssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TReraiseOutsideHandlerRule.Create,
    Import('  Protokoll.Fehler(''Import abgebrochen'');'#10'  raise;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('reraise-outside-handler', Findings[0].RuleId);
  Assert.AreEqual('raise ohne Argument ist nur in einem except-Block erlaubt (wie E2145).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(7, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TReraiseOutsideHandlerTests.LocalRoutineAndAnonymousMethod;
var
  Findings: TArray<TRuleFinding>;
begin
  // Lokale Prozedur, die aus dem Handler gerufen wird, raise im finally und in einer anonymen Methode.
  Findings := TRuleAssert.Findings(TReraiseOutsideHandlerRule.Create,
    'unit Importe;'#10'interface'#10'implementation'#10'procedure TImport.Laden;'#10 +
    '  procedure Weiterwerfen;'#10'  begin'#10'    raise;'#10'  end;'#10'begin'#10'  try'#10'    Lesen;'#10 +
    '  except'#10'    Weiterwerfen;'#10'  end;'#10'  try'#10'    Lesen;'#10'  finally'#10'    raise;'#10'  end;'#10 +
    '  Ausfuehren(procedure begin raise; end);'#10'end;'#10'end.');
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(17, Findings[1].Range.StartPos.Line);
  Assert.AreEqual(19, Findings[2].Range.StartPos.Line);
end;

procedure TReraiseOutsideHandlerTests.HandlersAreSilent;
begin
  // raise; in on-Handlern, im else-Teil, im except ohne Handler, verschachtelt in try und if, raise mit Objekt;
  // anonyme Methode im except (unklar) und Parserfehler.
  TRuleAssert.Silent(TReraiseOutsideHandlerRule.Create,
    Import('  try'#10'    Lesen;'#10'  except'#10'    on E: EDatenbank do'#10'      raise;'#10 +
    '    on E: EConvertError do'#10'    begin'#10'      Protokoll(E.Message);'#10'      raise;'#10'    end;'#10 +
    '  else'#10'    raise;'#10'  end;'#10'  try'#10'    Lesen;'#10'  except'#10'    try'#10'      Aufraeumen;'#10 +
    '    finally'#10'      if Fertig then'#10'        raise;'#10'    end;'#10'  end;'#10 +
    '  raise EImport.Create(''Abbruch'');'#10 +
    '  try'#10'    Lesen;'#10'  except'#10'    TThread.Synchronize(nil, procedure begin raise; end);'#10'  end;'#10));
  TRuleAssert.Silent(TReraiseOutsideHandlerRule.Create, Import('  if then'#10'  raise;'#10));
end;

procedure TReraiseOutsideHandlerTests.OffAndExclude;
const
  Statements = '  raise;'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TReraiseOutsideHandlerRule.Create, Import(Statements),
    '{"rules": {"reraise-outside-handler": "off"}}', 'Importe.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TReraiseOutsideHandlerRule.Create, Import(Statements),
    '{"rules": {"group:compiler": "off"}}', 'Importe.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TReraiseOutsideHandlerRule.Create, Import(Statements),
    '{"rules": {"reraise-outside-handler": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Importe.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TReraiseOutsideHandlerRule.Create, Import(Statements),
    '{"rules": {"reraise-outside-handler": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Importe.pas'))));
end;

function Dienst(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TDienst = class(TBasis)'#10'  private'#10 +
    '    FListe: TObject;'#10'  public'#10'    constructor Create;'#10'  end;'#10'implementation'#10 +
    'constructor TDienst.Create;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

procedure TExceptionRulesTests.InheritedConstructorIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Dienst('  try'#10'    inherited Create;'#10'    FListe := TObject.Create;'#10'  except'#10 +
    '    FListe.Free;'#10'    raise;'#10'  end;'#10);
  Findings := TRuleAssert.Findings(TInheritedConstructorAfterTryRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('inherited-constructor-after-try', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('try vor dem Aufruf des geerbten Konstruktors; Self ist noch nicht initialisiert (wie H2505).',
    Findings[0].Message);
  Assert.AreEqual(12, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(5, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('inherited Create vor try ziehen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  Fixed := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Dienst('  inherited Create;'#10'  try'#10'    FListe := TObject.Create;'#10'  except'#10 +
    '    FListe.Free;'#10'    raise;'#10'  end;'#10), Fixed);
  TRuleAssert.Silent(TInheritedConstructorAfterTryRule.Create, Fixed);
end;

procedure TExceptionRulesTests.InheritedConstructorVariants;
var
  Findings: TArray<TRuleFinding>;
  Fixed: string;
begin
  // inherited ohne Namen, auf derselben Zeile wie try.
  Findings := TRuleAssert.Findings(TInheritedConstructorAfterTryRule.Create,
    Dienst('  try inherited;'#10'    FListe := TObject.Create;'#10'  finally'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('inherited vor try ziehen', Findings[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Dienst('  try inherited;'#10'    FListe := TObject.Create;'#10 +
    '  finally'#10'  end;'#10), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Dienst('  inherited;'#10'  try'#10'    FListe := TObject.Create;'#10'  finally'#10'  end;'#10),
    Fixed);
  // Nicht die erste Anweisung: Meldung ohne Korrektur.
  Findings := TRuleAssert.Findings(TInheritedConstructorAfterTryRule.Create,
    Dienst('  try'#10'    FListe := nil;'#10'    inherited Create;'#10'  finally'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Mit Argumenten, CreateNeu; verschachtelt nur das äußere try.
  Findings := TRuleAssert.Findings(TInheritedConstructorAfterTryRule.Create,
    Dienst('  try'#10'    try'#10'      inherited CreateNeu(nil);'#10'    finally'#10'    end;'#10 +
    '  except'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(12, Findings[0].Range.StartPos.Line);
  // {$IFDEF}: Nur der Zweig, in dem inherited im try steht.
  Findings := TRuleAssert.Findings(TInheritedConstructorAfterTryRule.Create,
    Dienst('{$IFDEF ALT}'#10'  try'#10'    inherited Create;'#10'  finally'#10'  end;'#10'{$ELSE}'#10 +
    '  inherited Create;'#10'  try'#10'  finally'#10'  end;'#10'{$ENDIF}'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(13, Findings[0].Range.StartPos.Line);
end;

procedure TExceptionRulesTests.InheritedConstructorSilentCases;
begin
  // Korrekte Form, kein inherited, anderer geerbter Aufruf, inherited vor try im anderen Zweig.
  TRuleAssert.Silent(TInheritedConstructorAfterTryRule.Create, Dienst('  inherited Create;'#10'  try'#10 +
    '    FListe := TObject.Create;'#10'  except'#10'    raise;'#10'  end;'#10));
  TRuleAssert.Silent(TInheritedConstructorAfterTryRule.Create, Dienst('  try'#10 +
    '    FListe := TObject.Create;'#10'  finally'#10'  end;'#10));
  TRuleAssert.Silent(TInheritedConstructorAfterTryRule.Create, Dienst('  inherited Create;'#10'  try'#10 +
    '    inherited Laden;'#10'  finally'#10'  end;'#10));
  TRuleAssert.Silent(TInheritedConstructorAfterTryRule.Create, Dienst('{$IFDEF ALT}'#10 +
    '  inherited Create;'#10'{$ELSE}'#10'  inherited Create(nil);'#10'{$ENDIF}'#10'  try'#10 +
    '    inherited Laden;'#10'  finally'#10'  end;'#10));
  // try in eingebetteter Routine und anonymer Methode, Methode statt Konstruktor, class constructor.
  TRuleAssert.Silent(TInheritedConstructorAfterTryRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'constructor TDienst.Create;'#10'  procedure Pruefen;'#10'  begin'#10'    try'#10'    finally'#10'    end;'#10 +
    '  end;'#10'begin'#10'  FAufgabe := procedure'#10'    begin'#10'      try'#10'      finally'#10'      end;'#10 +
    '    end;'#10'  inherited Create;'#10'end;'#10'procedure TDienst.Neu;'#10'begin'#10'  try'#10 +
    '    inherited Create;'#10'  finally'#10'  end;'#10'end;'#10'class constructor TDienst.Create;'#10'begin'#10 +
    '  try'#10'    inherited;'#10'  finally'#10'  end;'#10'end;'#10'end.');
end;

procedure TExceptionRulesTests.InheritedConstructorOffAndExclude;
var
  Source: string;
begin
  Source := Dienst('  try'#10'    inherited Create;'#10'  finally'#10'  end;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedConstructorAfterTryRule.Create, Source,
    '{"rules": {"inherited-constructor-after-try": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInheritedConstructorAfterTryRule.Create, Source,
    '{"rules": {"inherited-constructor-after-try": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TExceptionRulesTests);
  TDUnitX.RegisterTestFixture(TReraiseOutsideHandlerTests);

end.
