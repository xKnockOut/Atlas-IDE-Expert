unit Atlas.Common.Rules.Builtin.Tests;

// Tests für alle eingebauten Regeln zusammen (Bericht M1): Sie laufen auch
// auf sehr tiefen Syntaxbäumen ohne Stapelüberlauf. Tiefe Bäume entstehen aus
// langen Ketten wie 1 - 1 - … - 1, die der Parser linkslastig baut. Die Kette
// steht an vielen Stellen einer Unit (Thread-Klasse, case, try, anonyme
// Methoden, Konstanten), damit jede Regel und jeder Dienst sie durchläuft.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBuiltinRulesTests = class
  public
    /// <summary>Jede eingebaute Regel prüft Units mit Ketten von 5000 Gliedern in 128 KB Stapel. Ein
    /// rekursiver Läufer bräuchte dafür mehr als 25 Byte je Ebene und liefe über.</summary>
    [Test]
    procedure AllRulesHandleDeepTrees;
    /// <summary>Die Engine prüft solche Units vollständig, statt sie zu überspringen.</summary>
    [Test]
    procedure EngineChecksDeepUnit;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Tests.SmallStack;

const
  /// <summary>Glieder je Kette.</summary>
  ChainLength = 5000;
  StackKb = 128;
  // § steht für die Kette.
  RichUnit = 'unit U;'#10 +
    'interface'#10 +
    'uses System.Classes, System.SysUtils, System.SyncObjs, Vcl.Forms, Vcl.Dialogs;'#10 +
    'const'#10 +
    '  C = §;'#10 +
    'type'#10 +
    '  TWorker = class(TThread)'#10 +
    '  private'#10 +
    '    FLock: TCriticalSection;'#10 +
    '    FValue: Integer;'#10 +
    '    procedure Melde;'#10 +
    '  protected'#10 +
    '    procedure Execute; override;'#10 +
    '  public'#10 +
    '    destructor Destroy; override;'#10 +
    '    function Wert(A: Integer; const B: string): Integer;'#10 +
    '  end;'#10 +
    '  TBox = class(TCustomControl)'#10 +
    '  private'#10 +
    '    FColor: Integer;'#10 +
    '    procedure SetColor(AValue: Integer);'#10 +
    '  protected'#10 +
    '    procedure Paint; override;'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10 +
    '  published'#10 +
    '    property Color: Integer read FColor write SetColor default 3;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TWorker.Melde;'#10 +
    'begin'#10 +
    '  Synchronize(procedure begin Application.Title := IntToStr(§); end);'#10 +
    'end;'#10 +
    'procedure TWorker.Execute;'#10 +
    'var'#10 +
    '  X, Y, Z: Integer;'#10 +
    '  F: Double;'#10 +
    '  S: string;'#10 +
    'begin'#10 +
    '  X := §;'#10 +
    '  Y := §;'#10 +
    '  Application.Title := IntToStr(§);'#10 +
    '  ShowMessage(IntToStr(§));'#10 +
    '  if (§) > Z then Melde else if F = § then Exit;'#10 +
    '  FLock.Enter;'#10 +
    '  FValue := §;'#10 +
    '  FLock.Leave;'#10 +
    '  case § of 1: X := §; else Y := §; end;'#10 +
    '  for X := § to § do Y := §;'#10 +
    '  while § > X do X := §;'#10 +
    '  with Self do FValue := §;'#10 +
    '  try X := § finally Y := § end;'#10 +
    '  try X := § except on E: Exception do raise Exception.Create(IntToStr(§)); end;'#10 +
    '  S := ''a'' + IntToStr(§) + ''b'';'#10 +
    '  Self.Resume;'#10 +
    '  Self.Suspend;'#10 +
    '  TThread.CreateAnonymousThread(procedure begin X := §; ShowMessage(IntToStr(§)); end).Start;'#10 +
    '  TThread.Queue(nil, procedure begin Application.Title := IntToStr(§); end);'#10 +
    '  Exit;'#10 +
    '  X := §;'#10 +
    'end;'#10 +
    'destructor TWorker.Destroy;'#10 +
    'begin'#10 +
    '  Synchronize(Melde);'#10 +
    '  FValue := §;'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    'function TWorker.Wert(A: Integer; const B: string): Integer;'#10 +
    'var'#10 +
    '  Q: Integer;'#10 +
    '  W: TWorker;'#10 +
    'begin'#10 +
    '  W := TWorker.Create(True);'#10 +
    '  W.FreeOnTerminate := True;'#10 +
    '  W.Start;'#10 +
    '  W.FValue := §;'#10 +
    '  W.Free;'#10 +
    '  Q := §;'#10 +
    '  if Q > § then Result := § else Exit(§);'#10 +
    'end;'#10 +
    'constructor TBox.Create(AOwner: TComponent);'#10 +
    'begin'#10 +
    '  FColor := §;'#10 +
    'end;'#10 +
    'procedure TBox.SetColor(AValue: Integer);'#10 +
    'begin'#10 +
    '  FColor := AValue + §;'#10 +
    'end;'#10 +
    'procedure TBox.Paint;'#10 +
    'begin'#10 +
    '  Canvas.Brush.Color := §;'#10 +
    '  Canvas.Rectangle(0, 0, 16, §);'#10 +
    'end;'#10 +
    'end.';

type
  TCountingReport = class(TInterfacedObject, IRuleReport)
  public
    Count: Integer;
    procedure Add(const ARange: TTextRange; const AMessage: string); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
      const AFixes: TArray<TRuleFix>); overload;
    procedure AddWithSeverity(const ARange: TTextRange; const AMessage: string; ASeverity: TRuleSeverity;
      const AFixes: TArray<TRuleFix>);
    procedure AddWithDetails(const ARange: TTextRange; const AMessage, ADetails: string;
      AConfidence: TRuleConfidence; const AFixes: TArray<TRuleFix>);
  end;

procedure TCountingReport.Add(const ARange: TTextRange; const AMessage: string);
begin
  Inc(Count);
end;

procedure TCountingReport.Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>);
begin
  Inc(Count);
end;

procedure TCountingReport.Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence);
begin
  Inc(Count);
end;

procedure TCountingReport.Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
  const AFixes: TArray<TRuleFix>);
begin
  Inc(Count);
end;

procedure TCountingReport.AddWithSeverity(const ARange: TTextRange; const AMessage: string;
  ASeverity: TRuleSeverity; const AFixes: TArray<TRuleFix>);
begin
  Inc(Count);
end;

procedure TCountingReport.AddWithDetails(const ARange: TTextRange; const AMessage, ADetails: string;
  AConfidence: TRuleConfidence; const AFixes: TArray<TRuleFix>);
begin
  Inc(Count);
end;

/// <summary>Linkslastige Kette aus ACount Gliedern; AOperators wechseln reihum.</summary>
function Chain(ACount: Integer; const AOperators: array of string): string;
var
  Builder: TStringBuilder;
  Index: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('1');
    for Index := 1 to ACount do
      Builder.Append(' ').Append(AOperators[Index mod Length(AOperators)]).Append(' 1');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

/// <summary>Die Unit mit der Kette an allen Stellen; AShape 0 mit -, 1 mit abwechselnd + und - (wechselnde
/// Operatoren gleicht der Parser nicht aus).</summary>
function DeepUnit(AShape: Integer): string;
begin
  if AShape = 0 then
    Result := StringReplace(RichUnit, '§', Chain(ChainLength, ['-']), [rfReplaceAll])
  else
    Result := StringReplace(RichUnit, '§', Chain(ChainLength, ['+', '-']), [rfReplaceAll]);
end;

procedure TBuiltinRulesTests.AllRulesHandleDeepTrees;
var
  Rules: TArray<IRule>;
  Shape: Integer;
  Text, Failure, Running: string;
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Counter: TCountingReport;
  Report: IRuleReport;
begin
  Rules := BuiltinRules;
  for Shape := 0 to 1 do
  begin
    Text := DeepUnit(Shape);
    Tree := TPascalParser.Parse(Text);
    try
      Assert.IsTrue(Tree.Depth > ChainLength, 'Kette bleibt linkslastig, Tiefe ' + IntToStr(Tree.Depth));
      Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Unit fehlerfrei gelesen');
      Context := Default(TRuleContext);
      Context.Text := Text;
      Context.Tree := Tree;
      Context.Derived := TRuleDerivedCache.Create;
      Counter := TCountingReport.Create;
      Report := Counter;
      Running := '';
      // Alle Regeln in einem Thread; Running nennt bei einem Überlauf die Regel.
      Failure := TSmallStack.Run(StackKb,
        procedure
        var
          Rule: IRule;
        begin
          for Rule in Rules do
          begin
            Running := Rule.Descriptor.Id;
            Rule.Check(Context, Report);
          end;
          Running := '';
        end);
      // Der Ableitungscache hält Verweise in den Baum: vor ihm leeren.
      Context.Derived := nil;
    finally
      Tree.Free;
    end;
    Assert.AreEqual('', Failure, Format('Form %d, Regel %s', [Shape, Running]));
    Assert.IsTrue(Counter.Count > 0, 'Regeln melden Treffer');
    Report := nil;
  end;
  Rules := nil;
end;

procedure TBuiltinRulesTests.EngineChecksDeepUnit;
var
  Text: string;
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Findings: TArray<TRuleFinding>;
  Finding: TRuleFinding;
  Ids: string;
begin
  Text := DeepUnit(0);
  Tree := TPascalParser.Parse(Text);
  try
    Context := Default(TRuleContext);
    Context.Text := Text;
    Context.Tree := Tree;
    Findings := TRuleEngine.Run(BuiltinRules, TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
  Ids := ' ';
  for Finding in Findings do
    Ids := Ids + Finding.RuleId + ' ';
  Assert.IsFalse(Pos(' ' + UnitTooDeepRuleId + ' ', Ids) > 0, 'nicht übersprungen');
  Assert.IsTrue(Pos(' thread-resume-suspend ', Ids) > 0, Ids);
  Assert.IsTrue(Pos(' thread-vcl-access ', Ids) > 0, Ids);
  Findings := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TBuiltinRulesTests);

end.
