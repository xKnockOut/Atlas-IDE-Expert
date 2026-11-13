unit Atlas.Common.Rules.Builtin.Ownership.MethodReferences.Tests;

// Tests von anonymous-method-self-cycle und event-handler-not-unhooked (#1876): Kreis über eine eingefangene
// Variable (auch Inline und rekursiv), Auflösen mit nil, Ereignisse fremder Objekte mit und ohne Zurücksetzen,
// Korrektur im Destruktor, Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAnonymousMethodSelfCycleTests = class
  public
    [Test]
    procedure CapturedVariableHoldsAnonymousMethod;
    [Test]
    procedure InlineAndRecursive;
    [Test]
    procedure SilentCases;
    [Test]
    procedure RuleCanBeTurnedOff;
  end;

  [TestFixture]
  TEventHandlerNotUnhookedTests = class
  public
    [Test]
    procedure FieldWithFix;
    [Test]
    procedure Parameter;
    [Test]
    procedure SilentCases;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Ownership.MethodReferences,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message + '|';
  end;
end;

/// <summary>Unit mit der Routine Lauf (Variablen AVars, Rumpf ABody).</summary>
function Source(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes;'#10'implementation'#10 +
    'procedure Lauf(Liste: TThreadList);'#10'var'#10 + AVars + 'begin'#10 + ABody + 'end;'#10'end.';
end;

{ TAnonymousMethodSelfCycleTests }

procedure TAnonymousMethodSelfCycleTests.CapturedVariableHoldsAnonymousMethod;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := TRuleAssert.Findings(TAnonymousMethodSelfCycleRule.Create, Source('  Schritt: TProc;'#10,
    '  Schritt := procedure'#10'    begin'#10'    end;'#10'  TThread.Queue(nil,'#10'    procedure'#10 +
    '    begin'#10'      Schritt();'#10'    end);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(cAnonymousMethodSelfCycleRuleId, mFound[0].RuleId);
  Assert.AreEqual(9, mFound[0].Range.StartPos.Line);
  Assert.Contains(mFound[0].Message, 'Schritt hält eine anonyme Methode dieser Routine');
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TAnonymousMethodSelfCycleTests.InlineAndRecursive;
begin
  TRuleAssert.Reports(TAnonymousMethodSelfCycleRule.Create, Source('',
    '  var Schritt: TProc := procedure'#10'    begin'#10'    end;'#10 +
    '  TThread.Queue(nil, procedure begin Schritt(); end);'#10));
  // Rekursion über die Variable: dieselbe anonyme Methode fängt sie ein.
  TRuleAssert.Reports(TAnonymousMethodSelfCycleRule.Create, Source('  Zaehle: TProc<Integer>;'#10,
    '  Zaehle := procedure(N: Integer)'#10'    begin'#10'      if N > 0 then'#10'        Zaehle(N - 1);'#10 +
    '    end;'#10'  Zaehle(3);'#10));
end;

procedure TAnonymousMethodSelfCycleTests.SilentCases;
begin
  // Auf nil gesetzt, nicht eingefangen, keine anonyme Methode in der Variablen.
  TRuleAssert.Silent(TAnonymousMethodSelfCycleRule.Create, Source('  Zaehle: TProc<Integer>;'#10,
    '  Zaehle := procedure(N: Integer)'#10'    begin'#10'      if N > 0 then'#10'        Zaehle(N - 1);'#10 +
    '    end;'#10'  Zaehle(3);'#10'  Zaehle := nil;'#10));
  TRuleAssert.Silent(TAnonymousMethodSelfCycleRule.Create, Source('  Schritt: TProc;'#10,
    '  Schritt := procedure'#10'    begin'#10'    end;'#10'  Schritt();'#10));
  TRuleAssert.Silent(TAnonymousMethodSelfCycleRule.Create, Source('  Text: string;'#10,
    '  Text := ''a'';'#10'  TThread.Queue(nil, procedure begin Text := Text + ''b''; end);'#10));
end;

procedure TAnonymousMethodSelfCycleTests.RuleCanBeTurnedOff;
var
  mSource: string;
begin
  mSource := Source('  Zaehle: TProc;'#10, '  Zaehle := procedure begin Zaehle(); end;'#10);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TAnonymousMethodSelfCycleRule.Create, mSource))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAnonymousMethodSelfCycleRule.Create, mSource,
    '{"rules": {"anonymous-method-self-cycle": "off"}}'))));
end;

{ TEventHandlerNotUnhookedTests }

/// <summary>Klasse TBeobachter mit Feld FQuelle (gesetzt im Konstruktor) und Destruktor mit ADestroyBody.</summary>
function Observer(const AConstructorBody, ADestroyBody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'uses'#10'  System.Classes;'#10'type'#10'  TBeobachter = class'#10 +
    '  private'#10'    FQuelle: TStringList;'#10'    procedure Geaendert(Sender: TObject);'#10'  public'#10 +
    '    constructor Create(AQuelle: TStringList);'#10'    destructor Destroy; override;'#10'  end;'#10 +
    'implementation'#10'constructor TBeobachter.Create(AQuelle: TStringList);'#10'begin'#10'  inherited Create;'#10 +
    '  FQuelle := AQuelle;'#10 + AConstructorBody + 'end;'#10'destructor TBeobachter.Destroy;'#10'begin'#10 +
    ADestroyBody + '  inherited;'#10'end;'#10'procedure TBeobachter.Geaendert(Sender: TObject);'#10'begin'#10 +
    'end;'#10'end.';
end;

procedure TEventHandlerNotUnhookedTests.FieldWithFix;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Observer('  FQuelle.OnChange := Geaendert;'#10, '');
  mFound := TRuleAssert.Findings(TEventHandlerNotUnhookedRule.Create, mSource);
  Assert.AreEqual('18: FQuelle.OnChange zeigt auf Geaendert, wird beim Freigeben von TBeobachter aber nicht ' +
    'zurückgesetzt; lebt FQuelle länger, ruft es die Methode eines freigegebenen Objekts auf.|', Messages(mFound));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFound[0].Severity));
  Assert.AreEqual('Im Destruktor FQuelle.OnChange := nil setzen', mFound[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFound[0].Fixes[0].Edits);
  Assert.AreEqual(Observer('  FQuelle.OnChange := Geaendert;'#10,
    '  if Assigned(FQuelle) then'#10'    FQuelle.OnChange := nil;'#10), mFixed);
  TRuleAssert.Silent(TEventHandlerNotUnhookedRule.Create, mFixed);
end;

procedure TEventHandlerNotUnhookedTests.Parameter;
var
  mFound: TArray<TRuleFinding>;
begin
  // Self.Handler, Parameter ohne Feld: kein Destruktor kann ihn erreichen, also ohne Korrektur.
  mFound := TRuleAssert.Findings(TEventHandlerNotUnhookedRule.Create,
    Observer('  AQuelle.OnChanging := Self.Geaendert;'#10, ''));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TEventHandlerNotUnhookedTests.SilentCases;
begin
  // Zurückgesetzt im Destruktor, eigenes Ereignis, fremde Methode, selbst erzeugtes Feld, Feld aus einer
  // Hilfsfunktion (meist ein eigenes Steuerelement), published-Feld.
  TRuleAssert.Silent(TEventHandlerNotUnhookedRule.Create, Observer('  FQuelle.OnChange := Geaendert;'#10,
    '  FQuelle.OnChange := nil;'#10));
  TRuleAssert.Silent(TEventHandlerNotUnhookedRule.Create, Observer('  OnChange := Geaendert;'#10, ''));
  TRuleAssert.Silent(TEventHandlerNotUnhookedRule.Create, Observer('  FQuelle.OnChange := AQuelle.OnChange;'#10,
    ''));
  TRuleAssert.Silent(TEventHandlerNotUnhookedRule.Create, Observer('  FQuelle := TStringList.Create;'#10 +
    '  FQuelle.OnChange := Geaendert;'#10, '  FQuelle.Free;'#10));
  TRuleAssert.Silent(TEventHandlerNotUnhookedRule.Create, Observer('  FQuelle.OnChange := Geaendert;'#10, '').Replace(
    'FQuelle := AQuelle;', 'FQuelle := TStringList(AQuelle.Objects[0]);'));
  TRuleAssert.Silent(TEventHandlerNotUnhookedRule.Create, 'unit U;'#10'interface'#10'uses'#10 +
    '  Vcl.Forms, Vcl.StdCtrls;'#10'type'#10'  TForm1 = class(TForm)'#10'    Button1: TButton;'#10 +
    '    procedure Klick(Sender: TObject);'#10'    procedure FormCreate(Sender: TObject);'#10'  end;'#10 +
    'implementation'#10'procedure TForm1.FormCreate(Sender: TObject);'#10'begin'#10 +
    '  Button1.OnClick := Klick;'#10'end;'#10'procedure TForm1.Klick(Sender: TObject);'#10'begin'#10'end;'#10 +
    'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TAnonymousMethodSelfCycleTests);
  TDUnitX.RegisterTestFixture(TEventHandlerNotUnhookedTests);

end.
