unit Atlas.Common.Rules.Engine;

// Führt Prüfregeln auf einer Datei aus. Beachtet aus atlas.json den
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
//
// Eine Kennung im Unterdrückungskommentar, die weder im Regelkatalog noch
// unter den übergebenen Regeln steht, meldet die Engine als Hinweis
// "unknown-rule-id" mit Tippfehler-Vorschlag und Korrektur (#41). Ein solcher
// Kommentar zählt nicht zusätzlich als "unused-suppression".
//
// Hauptschalter je Gruppe (#909): "rules": { "group:threads": "off" } schaltet
// alle Regeln der Gruppe ab, auch einzeln eingestellte; die Gruppe steht im
// Regelkatalog.
//
// Regelprofile, Pfadregeln und das Ausnehmen von Test-Units (#146) wertet
// TRuleProfiles aus; maßgeblich ist das Profil in ASettings.Profile, für
// Test-Units und Testprojekte ASettings.TestProfile, falls gesetzt.
//
// Laufzeit (Diagnoselog 15.10.2026): Vor jeder Regel fragt die Engine
// AContext.Cancelled und bricht mit ERuleCheckCancelled ab. Früher lief eine
// abgebrochene oder überholte Prüfung bis zum Ende weiter (bis 240 s). Die
// langsamste Regel ab SlowRuleMs geht als slowRule/slowRuleMs ins Diagnoselog.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract;

const
  UnusedSuppressionRuleId = 'unused-suppression';
  UnknownRuleIdRuleId = 'unknown-rule-id';

type
  TRuleEngine = class
  public const
    /// <summary>Ab dieser Dauer nennt das Diagnoselog die Regel.</summary>
    SlowRuleMs = 100;
  public
    /// <summary>Wirksamer Schweregrad einer Regel; Off = nicht ausführen.</summary>
    class function EffectiveSeverity(const ARule: TRuleDescriptor;
      const ASettings: TServerSettings; const ARelativePath: string = ''): TRuleSeverity; overload; static;
    class function EffectiveSeverity(const ARule: TRuleDescriptor; const ASettings: TServerSettings;
      const ARelativePath: string; out AEnabled: Boolean): TRuleSeverity; overload; static;
    /// <summary>Ist die Gruppe der Regel über "group:&lt;gruppe&gt;": "off" abgeschaltet (#909)?</summary>
    class function GroupOff(const ARuleId: string; const ASettings: TServerSettings): Boolean; static;
    /// <summary>Optionen der Regel als JSON-Text, sonst ''.</summary>
    class function RuleOptions(const ARuleId: string; const ASettings: TServerSettings): string; static;
    /// <summary>ASeverity begrenzt nach Konfidenz.</summary>
    class function CapSeverity(ASeverity: TRuleSeverity; AConfidence: TRuleConfidence): TRuleSeverity; static;
    /// <summary>True, wenn "exclude" in AOptions den Pfad oder die Unit trifft.</summary>
    class function IsExceptedByOptions(const AOptions, ARelativePath, AUnitName: string): Boolean; static;
    /// <summary>Alle Treffer der Regeln auf AContext, nach Zeile sortiert.</summary>
    class function Run(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const AContext: TRuleContext): TArray<TRuleFinding>; static;
  end;

implementation

uses
  System.JSON,
  System.StrUtils,
  System.Diagnostics,
  System.Generics.Defaults,
  Atlas.Common.Diagnostics.RequestScope,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Profiles,
  Atlas.Common.Rules.Suppressions;

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
    procedure AddWithSeverity(const ARange: TTextRange; const AMessage: string; ASeverity: TRuleSeverity;
      const AFixes: TArray<TRuleFix>);
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

procedure TRuleReport.AddWithSeverity(const ARange: TTextRange; const AMessage: string; ASeverity: TRuleSeverity;
  const AFixes: TArray<TRuleFix>);
var
  Finding: TRuleFinding;
begin
  if ASeverity = TRuleSeverity.Off then
    Exit;
  Finding.RuleId := FRuleId;
  Finding.Range := ARange;
  Finding.Message := AMessage;
  if ASeverity = TRuleSeverity.Default then
    Finding.Severity := FSeverity
  else
    Finding.Severity := ASeverity;
  Finding.Confidence := TRuleConfidence.High;
  Finding.Fixes := AFixes;
  FFindings.Add(Finding);
end;

{ TRuleEngine }

class function TRuleEngine.EffectiveSeverity(const ARule: TRuleDescriptor;
  const ASettings: TServerSettings; const ARelativePath: string): TRuleSeverity;
var
  Enabled: Boolean;
begin
  Result := EffectiveSeverity(ARule, ASettings, ARelativePath, Enabled);
end;

class function TRuleEngine.EffectiveSeverity(const ARule: TRuleDescriptor; const ASettings: TServerSettings;
  const ARelativePath: string; out AEnabled: Boolean): TRuleSeverity;
begin
  if GroupOff(ARule.Id, ASettings) then
  begin
    AEnabled := False;
    Exit(TRuleSeverity.Off);
  end;
  // Kennzahlen global aus ("metrics": false): metric-* schweigen, außer das Projekt setzt die Regel selbst.
  if not ASettings.Metrics and SameText(Copy(ARule.Id, 1, 7), 'metric-') and
    (ASettings.RuleSeverity(ARule.Id, TRuleSeverity.Default) = TRuleSeverity.Default) then
  begin
    AEnabled := False;
    Exit(TRuleSeverity.Off);
  end;
  Result := TRuleProfiles.Severity(ASettings, ASettings.Profile, ARule, TRuleProfiles.CategoryOf(ARule.Id),
    ARelativePath, AEnabled);
  if Result = TRuleSeverity.Default then
    Result := TRuleSeverity.Warning;
end;

class function TRuleEngine.GroupOff(const ARuleId: string; const ASettings: TServerSettings): Boolean;
var
  Entry: TRuleCatalogEntry;
begin
  Result := (Length(ASettings.Rules) > 0) and TRuleCatalog.Shared.TryFind(ARuleId, Entry) and
    (ASettings.RuleSeverity(TRuleCatalog.GroupKey(Entry.Group), TRuleSeverity.Default) = TRuleSeverity.Off);
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
  Enabled: Boolean;
  Settings: TServerSettings;
  MinConfidence: TRuleConfidence;
  Watch: TStopwatch;
  Elapsed: Int64;
  Shared: TRuleContext;
  OwnCache: IRuleDerivedCache;
  Known: TArray<string>;
  Index: Integer;
  Suggestion: string;
  After: IRuleAfterFindings;
  Afters: TList<IRuleAfterFindings>;
  AfterIds: TList<string>;
  AfterSeverities: TList<TRuleSeverity>;
  AfterContexts: TList<TRuleContext>;
begin
  if (AContext.RelativePath <> '') and ASettings.IsExcluded(AContext.RelativePath) then
    Exit(nil);
  Settings := ASettings;
  if (ASettings.ExcludeTests or (ASettings.TestProfile <> '')) and (AContext.Tree <> nil) and
    TRuleProfiles.IsTestUnit(AContext.Tree.Tokens) then
  begin
    if ASettings.ExcludeTests then
      Exit(nil);
    Settings.Profile := ASettings.TestProfile;
  end;
  MinConfidence := TRuleProfiles.MinConfidence(Settings, Settings.Profile);
  // Ein Ableitungscache für alle Regeln des Laufs (Review P-03); ein vom Aufrufer
  // gesetzter Cache gehört dem Aufrufer und bleibt gefüllt.
  Shared := AContext;
  OwnCache := nil;
  if Shared.Derived = nil then
  begin
    OwnCache := TRuleDerivedCache.Create;
    Shared.Derived := OwnCache;
  end;
  Findings := TList<TRuleFinding>.Create;
  Kept := TList<TRuleFinding>.Create;
  Suppressions := nil;
  RanIds := TList<string>.Create;
  Afters := TList<IRuleAfterFindings>.Create;
  AfterIds := TList<string>.Create;
  AfterSeverities := TList<TRuleSeverity>.Create;
  AfterContexts := TList<TRuleContext>.Create;
  try
    for Rule in ARules do
    begin
      Descriptor := Rule.Descriptor;
      Severity := EffectiveSeverity(Descriptor, Settings, AContext.RelativePath, Enabled);
      if Severity = TRuleSeverity.Off then
        Continue;
      if Descriptor.Experimental and not Enabled then
        Continue;
      Context := Shared;
      if Context.DelphiVersion = '' then
        Context.DelphiVersion := Settings.DelphiVersion;
      Context.Options := RuleOptions(Descriptor.Id, Settings);
      Context.DfmPropertyRules := Settings.DfmPropertyRules;
      Context.NoSignatureSync := not Settings.Refactoring.SyncSignatures;
      Context.NoForwardDeclaration := not Settings.Refactoring.ForwardDeclaration;
      Context.NoFreeFields := not Settings.Refactoring.FreeFields;
      Context.FreeFieldsFreeAndNil := SameText(Settings.Refactoring.FreeFieldsStyle, 'freeAndNil');
      Context.Formatting := Settings.Formatting;
      if IsExceptedByOptions(Context.Options, Context.RelativePath, Context.UnitName) then
        Continue;
      // Erst in einer Interface-Variablen halten: Check nimmt den Report als
      // const; ohne gezählte Referenz würde er nie freigegeben (Speicherleck).
      if Assigned(AContext.Cancelled) and AContext.Cancelled() then
        raise ERuleCheckCancelled.Create('Prüfung abgebrochen');
      Report := TRuleReport.Create(Descriptor.Id, Severity, Findings);
      Watch := TStopwatch.StartNew;
      Rule.Check(Context, Report);
      Report := nil;
      Elapsed := Watch.ElapsedMilliseconds;
      if Elapsed >= SlowRuleMs then
        TRequestDiagnostics.Slowest('slowRule', Descriptor.Id, Integer(Elapsed));
      RanIds.Add(LowerCase(Descriptor.Id));
      if Supports(Rule, IRuleAfterFindings, After) then
      begin
        Afters.Add(After);
        AfterIds.Add(Descriptor.Id);
        AfterSeverities.Add(Severity);
        AfterContexts.Add(Context);
      end;
      After := nil;
    end;
    // Nach allen Regeln, mit den rohen Treffern (#297).
    for Index := 0 to Afters.Count - 1 do
    begin
      Report := TRuleReport.Create(AfterIds[Index], AfterSeverities[Index], Findings);
      Afters[Index].CheckFindings(AfterContexts[Index], Findings.ToArray, RanIds.ToArray, Report);
      Report := nil;
    end;

    if AContext.Tree <> nil then
      Suppressions := TSuppressions.Create(AContext.Tree.Tokens);
    // Erst unterdrücken, dann filtern: Auch ausgeblendete Treffer machen einen Kommentar wirksam.
    for Finding in Findings do
      if ((Suppressions = nil) or not Suppressions.IsSuppressed(Finding.RuleId, Finding.Range.StartPos.Line)) and
        (Ord(Finding.Confidence) >= Ord(MinConfidence)) then
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
        Finding.Fixes := [TRuleFix.Create('Unterdrückung entfernen', [TRuleEdit.Create(Removal, '')], True)];
        Kept.Add(Finding);
      end;

    if (Suppressions <> nil) and (Length(Suppressions.Entries) > 0) and
      (ASettings.RuleSeverity(UnknownRuleIdRuleId, TRuleSeverity.Hint) <> TRuleSeverity.Off) then
    begin
      Known := TRuleProfiles.KnownRuleIds;
      for Rule in ARules do
        Known := Known + [LowerCase(Rule.Descriptor.Id)];
      for Entry in Suppressions.Entries do
        for Index := 0 to High(Entry.Ids) do
        begin
          Id := Entry.Ids[Index];
          if (Id = '*') or (IndexText(TRuleIdAliases.Current(Id), Known) >= 0) then
            Continue;
          Suggestion := TSuppressions.Suggest(Id, Known);
          Finding := Default(TRuleFinding);
          Finding.RuleId := UnknownRuleIdRuleId;
          Finding.Range := Entry.IdRanges[Index];
          Finding.Severity := ASettings.RuleSeverity(UnknownRuleIdRuleId, TRuleSeverity.Hint);
          Finding.Confidence := TRuleConfidence.High;
          if Suggestion = '' then
            Finding.Message := Format('Unbekannte Regelkennung "%s"; die Unterdrückung wirkt nicht', [Id])
          else
          begin
            Finding.Message := Format('Unbekannte Regelkennung "%s"; gemeint ist vermutlich "%s"', [Id, Suggestion]);
            // Nur genau markierte Kennungen ersetzen, nicht den ganzen Kommentar.
            if Entry.IdRanges[Index].StartPos.Line = Entry.IdRanges[Index].EndPos.Line then
              Finding.Fixes := [TRuleFix.Create(Format('Durch "%s" ersetzen', [Suggestion]),
                [TRuleEdit.Create(Entry.IdRanges[Index], Suggestion)], True)];
          end;
          Kept.Add(Finding);
        end;
    end;

    Kept.Sort(TComparer<TRuleFinding>.Construct(CompareFindings));
    Result := Kept.ToArray;
  finally
    // Gibt Graphen und Modelle frei, bevor der Aufrufer den Baum freigibt, und bricht
    // Referenzzyklen über Kontextkopien in abgelegten Objekten.
    if OwnCache <> nil then
      OwnCache.Clear;
    AfterContexts.Free;
    AfterSeverities.Free;
    AfterIds.Free;
    Afters.Free;
    RanIds.Free;
    Suppressions.Free;
    Kept.Free;
    Findings.Free;
  end;
end;

end.
