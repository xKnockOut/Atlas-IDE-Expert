unit BDLsp.Common.Rules.Engine;

// Führt Prüfregeln auf einer Datei aus. Beachtet aus delphi-lsp.json den
// Schweregrad je Regel ("off" schaltet ab), den globalen Ausschluss und die
// Ausnahmen je Regel in den Optionen:
//   "rules": { "empty-except": { "severity": "hint", "exclude": ["Legacy/**", "Alt.Unit"] } }
// Muster in "exclude" gelten für den relativen Pfad (Glob) oder den Unit-Namen.
// Danach filtert sie Treffer, die per Kommentar unterdrückt sind.
//
// Konfidenzpolitik (#144): Fehler nur bei hoher Konfidenz, mittlere höchstens
// Warnung, niedrige höchstens Hinweis. Treffer unter "minConfidence" (Vorgabe
// medium) entfallen. Experimentelle Regeln laufen nur, wenn sie in "rules"
// stehen.
//
// Unterdrückungskommentare, die nichts unterdrücken, meldet die Engine als
// Hinweis "unused-suppression" mit Korrektur zum Entfernen (#147); nur wenn
// alle genannten Regeln gelaufen sind, damit Kommentare für abgeschaltete
// oder unbekannte Regeln nicht stören.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract;

const
  UnusedSuppressionRuleId = 'unused-suppression';

type
  TRuleEngine = class
  public
    /// <summary>Wirksamer Schweregrad einer Regel; Off = nicht ausführen.</summary>
    class function EffectiveSeverity(const ARule: TRuleDescriptor;
      const ASettings: TServerSettings): TRuleSeverity; static;
    /// <summary>Optionen der Regel als JSON-Text, sonst ''.</summary>
    class function RuleOptions(const ARuleId: string; const ASettings: TServerSettings): string; static;
    /// <summary>True, wenn "exclude" in AOptions den Pfad oder die Unit trifft.</summary>
    /// <summary>ASeverity begrenzt nach Konfidenz.</summary>
    class function CapSeverity(ASeverity: TRuleSeverity; AConfidence: TRuleConfidence): TRuleSeverity; static;
    class function IsExceptedByOptions(const AOptions, ARelativePath, AUnitName: string): Boolean; static;
    /// <summary>Alle Treffer der Regeln auf AContext, nach Zeile sortiert.</summary>
    class function Run(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const AContext: TRuleContext): TArray<TRuleFinding>; static;
  end;

implementation

uses
  System.JSON,
  System.Generics.Defaults,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Rules.Suppressions;

type
  TRuleReport = class(TInterfacedObject, IRuleReport)
  private
    FRuleId: string;
    FSeverity: TRuleSeverity;
    FFindings: TList<TRuleFinding>;
  public
    constructor Create(const ARuleId: string; ASeverity: TRuleSeverity; AFindings: TList<TRuleFinding>);
    procedure Add(const ARange: TTextRange; const AMessage: string); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
      const AFixes: TArray<TRuleFix>); overload;
  end;

function CompareFindings(const A, B: TRuleFinding): Integer;
begin
  Result := A.Range.StartPos.Line - B.Range.StartPos.Line;
  if Result = 0 then
    Result := A.Range.StartPos.Character - B.Range.StartPos.Character;
  if Result = 0 then
    Result := CompareText(A.RuleId, B.RuleId);
end;

{ TRuleReport }

constructor TRuleReport.Create(const ARuleId: string; ASeverity: TRuleSeverity; AFindings: TList<TRuleFinding>);
begin
  inherited Create;
  FRuleId := ARuleId;
  FSeverity := ASeverity;
  FFindings := AFindings;
end;

procedure TRuleReport.Add(const ARange: TTextRange; const AMessage: string);
begin
  Add(ARange, AMessage, nil);
end;

procedure TRuleReport.Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>);
begin
  Add(ARange, AMessage, TRuleConfidence.High, AFixes);
end;

procedure TRuleReport.Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence);
begin
  Add(ARange, AMessage, AConfidence, nil);
end;

procedure TRuleReport.Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
  const AFixes: TArray<TRuleFix>);
var
  Finding: TRuleFinding;
begin
  Finding.RuleId := FRuleId;
  Finding.Range := ARange;
  Finding.Message := AMessage;
  Finding.Severity := TRuleEngine.CapSeverity(FSeverity, AConfidence);
  Finding.Confidence := AConfidence;
  Finding.Fixes := AFixes;
  FFindings.Add(Finding);
end;

{ TRuleEngine }

class function TRuleEngine.EffectiveSeverity(const ARule: TRuleDescriptor;
  const ASettings: TServerSettings): TRuleSeverity;
begin
  Result := ASettings.RuleSeverity(ARule.Id, ARule.DefaultSeverity);
  if Result = TRuleSeverity.Default then
    Result := TRuleSeverity.Warning;
end;

class function TRuleEngine.CapSeverity(ASeverity: TRuleSeverity; AConfidence: TRuleConfidence): TRuleSeverity;
var
  Limit: TRuleSeverity;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Limit := TRuleSeverity.Hint;
    TRuleConfidence.Medium:
      Limit := TRuleSeverity.Warning;
  else
    Limit := TRuleSeverity.Error;
  end;
  if Ord(ASeverity) > Ord(Limit) then
    Result := Limit
  else
    Result := ASeverity;
end;

class function TRuleEngine.RuleOptions(const ARuleId: string; const ASettings: TServerSettings): string;
var
  Rule: TRuleSetting;
begin
  for Rule in ASettings.Rules do
    if SameText(Rule.Id, ARuleId) then
      Exit(Rule.Options);
  Result := '';
end;

class function TRuleEngine.IsExceptedByOptions(const AOptions, ARelativePath, AUnitName: string): Boolean;
var
  Value: TJSONValue;
  Exclude: TJSONValue;
  Item: TJSONValue;
  Pattern: string;
begin
  Result := False;
  if AOptions = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    Exclude := TJSONObject(Value).GetValue('exclude');
    if not (Exclude is TJSONArray) then
      Exit;
    for Item in TJSONArray(Exclude) do
    begin
      if not (Item is TJSONString) then
        Continue;
      Pattern := Item.Value;
      if ((AUnitName <> '') and SameText(Pattern, AUnitName)) or
        ((ARelativePath <> '') and MatchesGlob(Pattern, ARelativePath)) then
        Exit(True);
    end;
  finally
    Value.Free;
  end;
end;

class function TRuleEngine.Run(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const AContext: TRuleContext): TArray<TRuleFinding>;
var
  Findings: TList<TRuleFinding>;
  Kept: TList<TRuleFinding>;
  Suppressions: TSuppressions;
  Rule: IRule;
  Report: IRuleReport;
  Descriptor: TRuleDescriptor;
  Severity: TRuleSeverity;
  Context: TRuleContext;
  Finding: TRuleFinding;
  RanIds: TList<string>;
  Entry: TSuppressionEntry;
  Id: string;
  AllRan: Boolean;
  Removal: TTextRange;
begin
  if (AContext.RelativePath <> '') and ASettings.IsExcluded(AContext.RelativePath) then
    Exit(nil);
  Findings := TList<TRuleFinding>.Create;
  Kept := TList<TRuleFinding>.Create;
  Suppressions := nil;
  RanIds := TList<string>.Create;
  try
    for Rule in ARules do
    begin
      Descriptor := Rule.Descriptor;
      Severity := EffectiveSeverity(Descriptor, ASettings);
      if Severity = TRuleSeverity.Off then
        Continue;
      if Descriptor.Experimental and not ASettings.IsRuleEnabledExplicitly(Descriptor.Id) then
        Continue;
      Context := AContext;
      Context.Options := RuleOptions(Descriptor.Id, ASettings);
      if IsExceptedByOptions(Context.Options, Context.RelativePath, Context.UnitName) then
        Continue;
      // Erst in einer Interface-Variablen halten: Check nimmt den Report als
      // const; ohne gezählte Referenz würde er nie freigegeben (Speicherleck).
      Report := TRuleReport.Create(Descriptor.Id, Severity, Findings);
      Rule.Check(Context, Report);
      Report := nil;
      RanIds.Add(LowerCase(Descriptor.Id));
    end;

    if AContext.Tree <> nil then
      Suppressions := TSuppressions.Create(AContext.Tree.Tokens);
    // Erst unterdrücken, dann filtern: Auch ausgeblendete Treffer machen einen Kommentar wirksam.
    for Finding in Findings do
      if ((Suppressions = nil) or not Suppressions.IsSuppressed(Finding.RuleId, Finding.Range.StartPos.Line)) and
        (Ord(Finding.Confidence) >= Ord(ASettings.MinConfidence)) then
        Kept.Add(Finding);

    if (Suppressions <> nil) and
      (ASettings.RuleSeverity(UnusedSuppressionRuleId, TRuleSeverity.Hint) <> TRuleSeverity.Off) then
      for Entry in Suppressions.UnusedEntries do
      begin
        AllRan := Length(Entry.Ids) > 0;
        for Id in Entry.Ids do
          if (Id <> '*') and not RanIds.Contains(Id) then
            AllRan := False;
        if not AllRan then
          Continue;
        if Entry.OwnLine then
          Removal := TTextRange.Create(Entry.Range.StartPos.Line, 0, Entry.Range.EndPos.Line + 1, 0)
        else
          Removal := Entry.Range;
        Finding := Default(TRuleFinding);
        Finding.RuleId := UnusedSuppressionRuleId;
        Finding.Range := Entry.Range;
        Finding.Message := 'Unterdrückung ohne Wirkung: hier meldet keine der genannten Regeln etwas';
        Finding.Severity := ASettings.RuleSeverity(UnusedSuppressionRuleId, TRuleSeverity.Hint);
        Finding.Confidence := TRuleConfidence.High;
        Finding.Fixes := [TRuleFix.Create('Unterdrückung entfernen', [TRuleEdit.Create(Removal, '')])];
        Kept.Add(Finding);
      end;

    Kept.Sort(TComparer<TRuleFinding>.Construct(CompareFindings));
    Result := Kept.ToArray;
  finally
    RanIds.Free;
    Suppressions.Free;
    Kept.Free;
    Findings.Free;
  end;
end;

end.
