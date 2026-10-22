unit Atlas.Tests.RuleAssert;

// Testhilfe für Prüfregeln: parst einen Quelltext, führt eine Regel über die
// Engine aus und prüft Treffer. Jede Regel braucht mindestens einen
// positiven (Treffer) und einen negativen Testfall (kein Treffer).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract;

type
  // ARule ohne const: Tests übergeben TXyzRule.Create direkt. Bei const zählt
  // niemand die Referenz, und das temporäre Array in TRuleEngine.Run gibt die
  // Regel frei, bevor sie hier weiter benutzt wird (Zugriffsverletzung).
  TRuleAssert = class
  public
    /// <summary>Treffer von ARule auf ASource mit Einstellungen aus AConfigJson ('' = Vorgaben).</summary>
    class function Findings(ARule: IRule; const ASource: string;
      const AConfigJson: string = ''; const ARelativePath: string = ''): TArray<TRuleFinding>; static;
    /// <summary>Treffer von ARule auf ASource in einem Projekt der Anwendungsart AApplication (#926).</summary>
    class function ApplicationFindings(ARule: IRule; const ASource: string;
      AApplication: TRuleApplicationKind): TArray<TRuleFinding>; static;
    /// <summary>Treffer von ARule auf ASource mit der Formulardatei AFormText daneben (#123).</summary>
    class function FormFindings(const ARule: IRule; const ASource, AFormText: string): TArray<TRuleFinding>; static;
    /// <summary>Positiver Testfall: genau ACount Treffer.</summary>
    class procedure Reports(ARule: IRule; const ASource: string; ACount: Integer = 1); static;
    /// <summary>Negativer Testfall: kein Treffer.</summary>
    class procedure Silent(ARule: IRule; const ASource: string); static;
    /// <summary>Treffer aller ARules in einem Lauf der Engine (gemeinsamer Ableitungscache, Review P-03).</summary>
    class function FindingsOfAll(const ARules: TArray<IRule>; const ASource, AConfigJson: string):
      TArray<TRuleFinding>; static;
    /// <summary>
    ///   Ein gemeinsamer Lauf aller ARules liefert dieselben Treffer (Regel, Bereich, Meldung, Korrekturen)
    ///   wie je ein Lauf je Regel; Ergebnis ist die Trefferzahl. Prüft, dass der geteilte
    ///   Ableitungscache das Verhalten nicht ändert.
    /// </summary>
    class function SameAsSeparateRuns(const ARules: TArray<IRule>; const ASource, AConfigJson: string): Integer; overload;
      static;
    class function SameAsSeparateRuns(const ARules: TArray<IRule>; const ASource: string): Integer; overload; static;
  end;

  /// <summary>Testregel ohne Treffer: ruft beim Prüfen AOnCheck auf (zählen, warten, abbrechen).</summary>
  TCallbackRule = class(TInterfacedObject, IRule)
  private
    FId: string;
    FOnCheck: TProc;
  public
    constructor Create(const AId: string; const AOnCheck: TProc);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Engine;

class function TRuleAssert.Findings(ARule: IRule; const ASource, AConfigJson,
  ARelativePath: string): TArray<TRuleFinding>;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  if AConfigJson = '' then
    Settings := TServerSettings.Default
  else
    Settings := TConfigurationParser.Parse(AConfigJson, Issues);
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := ARelativePath;
    // Wie Rules.Checker: relative Pfade haben '/', ExtractFileName kennt unter Windows nur '\'.
    Context.UnitName := ChangeFileExt(ExtractFileName(StringReplace(ARelativePath, '/', '\', [rfReplaceAll])), '');
    Context.Text := ASource;
    Context.Tree := Tree;
    Result := TRuleEngine.Run([ARule], Settings, Context);
  finally
    Tree.Free;
  end;
end;

class function TRuleAssert.ApplicationFindings(ARule: IRule; const ASource: string;
  AApplication: TRuleApplicationKind): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.Text := ASource;
    Context.Tree := Tree;
    Context.Application := AApplication;
    Result := TRuleEngine.Run([ARule], TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
end;

class function TRuleAssert.FormFindings(const ARule: IRule; const ASource, AFormText: string): TArray<TRuleFinding>;
var
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.Text := ASource;
    Context.Tree := Tree;
    Context.FormText := AFormText;
    Result := TRuleEngine.Run([ARule], TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
end;

class procedure TRuleAssert.Reports(ARule: IRule; const ASource: string; ACount: Integer);
begin
  Assert.AreEqual(ACount, Integer(Length(Findings(ARule, ASource))),
    'Treffer von ' + ARule.Descriptor.Id);
end;

class procedure TRuleAssert.Silent(ARule: IRule; const ASource: string);
begin
  Reports(ARule, ASource, 0);
end;

class function TRuleAssert.FindingsOfAll(const ARules: TArray<IRule>; const ASource,
  AConfigJson: string): TArray<TRuleFinding>;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Tree: TSyntaxTree;
begin
  if AConfigJson = '' then
    Settings := TServerSettings.Default
  else
    Settings := TConfigurationParser.Parse(AConfigJson, Issues);
  Tree := TPascalParser.Parse(ASource);
  try
    Context := Default(TRuleContext);
    Context.Text := ASource;
    Context.Tree := Tree;
    Result := TRuleEngine.Run(ARules, Settings, Context);
  finally
    Tree.Free;
  end;
end;

/// <summary>Vergleichbarer Text eines Treffers mit Bereich, Meldung und Korrekturen.</summary>
function FindingKey(const AFinding: TRuleFinding): string;

  function RangeText(const ARange: TTextRange): string;
  begin
    Result := Format('%d:%d-%d:%d', [ARange.StartPos.Line, ARange.StartPos.Character, ARange.EndPos.Line,
      ARange.EndPos.Character]);
  end;

var
  Fix: TRuleFix;
  Edit: TRuleEdit;
begin
  Result := AFinding.RuleId + '@' + RangeText(AFinding.Range) + ' ' + AFinding.Message;
  for Fix in AFinding.Fixes do
  begin
    Result := Result + ' | ' + Fix.Title;
    for Edit in Fix.Edits do
      Result := Result + ' [' + RangeText(Edit.Range) + '=' + Edit.NewText + ']';
  end;
end;

class function TRuleAssert.SameAsSeparateRuns(const ARules: TArray<IRule>; const ASource,
  AConfigJson: string): Integer;
var
  Combined, Separate: TList<string>;
  Finding: TRuleFinding;
  Rule: IRule;
  Index: Integer;
begin
  Combined := TList<string>.Create;
  Separate := TList<string>.Create;
  try
    for Finding in FindingsOfAll(ARules, ASource, AConfigJson) do
      Combined.Add(FindingKey(Finding));
    for Rule in ARules do
      for Finding in FindingsOfAll([Rule], ASource, AConfigJson) do
        Separate.Add(FindingKey(Finding));
    Combined.Sort;
    Separate.Sort;
    Assert.AreEqual(Separate.Count, Combined.Count, 'Trefferzahl gemeinsam/einzeln');
    for Index := 0 to Combined.Count - 1 do
      Assert.AreEqual(Separate[Index], Combined[Index]);
    Result := Combined.Count;
  finally
    Separate.Free;
    Combined.Free;
  end;
end;

class function TRuleAssert.SameAsSeparateRuns(const ARules: TArray<IRule>; const ASource: string): Integer;
begin
  Result := SameAsSeparateRuns(ARules, ASource, '');
end;

{ TCallbackRule }

constructor TCallbackRule.Create(const AId: string; const AOnCheck: TProc);
begin
  inherited Create;
  FId := AId;
  FOnCheck := AOnCheck;
end;

function TCallbackRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FId, TRuleSeverity.Warning, 'Testregel');
end;

procedure TCallbackRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  FOnCheck();
end;

end.
