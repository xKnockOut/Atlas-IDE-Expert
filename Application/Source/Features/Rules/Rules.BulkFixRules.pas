unit Rules.BulkFixRules;

// Regelseite der Sammelkorrektur (TBulkFix, Atlas.Common.Findings.BulkFix): welche Regeln eine sichere Korrektur
// haben, welche Regeln je Durchgang laufen und die Prüfung je Durchgang mit TFileChecker.

interface

uses
  Atlas.Common.Configuration.Contract,
  Rules.Contract,
  Rules.Catalog,
  Rules.Checker,
  Atlas.Common.Checks.Contract,
  Atlas.Common.Findings.Baseline,
  Atlas.Common.Findings.BulkFix,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Regeln und Prüfung für TBulkFix.</summary>
  TRuleBulkFix = class
  public
    /// <summary>Kennungen (klein) der Regeln mit "safeFix" in ACatalog (ASafeRules von TBulkFixOptions.Create).</summary>
    class function SafeRulesOf(const ACatalog: TArray<TRuleCatalogEntry>): TArray<string>; static;
    /// <summary>Regeln für die Durchgänge: nur die aus AFixRules, damit jeder Durchgang schnell bleibt. Mit "all"
    /// oder einer Kennung, die keine Regel aus AAll ist (syntax, unused-suppression, unknown-rule-id entstehen in
    /// Checker bzw. Engine und brauchen die übrigen Regeln), alle.</summary>
    class function RulesFor(const AAll: TArray<IRule>; const AFixRules: TArray<string>): TArray<IRule>; static;
    /// <summary>Prüfung je Durchgang ohne weitere Filter (MCP, Plugin): Regeln, Einstellungen, Projekt und Symbole
    /// wie TFileChecker.CheckText.</summary>
    class function CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath: string; const AProject: TCheckProject; const ASource: TPascalSource): TBulkFixCheck;
      overload; static;
    /// <summary>Wie oben ohne die Treffer aus ABaseline (#97): Was festgehalten ist, bleibt unverändert.</summary>
    class function CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARelativePath: string; const AProject: TCheckProject; const ASource: TPascalSource;
      const ABaseline: IRuleBaseline): TBulkFixCheck; overload; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Findings.Scopes;

{ TRuleBulkFix }

class function TRuleBulkFix.SafeRulesOf(const ACatalog: TArray<TRuleCatalogEntry>): TArray<string>;
var
  mEntry: TRuleCatalogEntry;
begin
  Result := nil;
  for mEntry in ACatalog do
  begin
    if mEntry.SafeFix then
    begin
      Result := Result + [LowerCase(mEntry.Id)];
    end;
  end;
end;

class function TRuleBulkFix.RulesFor(const AAll: TArray<IRule>; const AFixRules: TArray<string>): TArray<IRule>;
var
  mRule: IRule;
  mId: string;
  mFound: Boolean;
begin
  Result := nil;
  for mId in AFixRules do
  begin
    if SameText(Trim(mId), TBulkFixOptions.cAll) then
    begin
      Exit(AAll);
    end;
    mFound := False;
    for mRule in AAll do
    begin
      if SameText(mRule.Descriptor.Id, Trim(mId)) then
      begin
        Result := Result + [mRule];
        mFound := True;
      end;
    end;
    if not mFound then
    begin
      Exit(AAll);
    end;
  end;
end;

class function TRuleBulkFix.CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath: string; const AProject: TCheckProject; const ASource: TPascalSource): TBulkFixCheck;
begin
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    var
      mScopes: TFindingScopes;
    begin
      Result := TFileChecker.CheckText(ARules, ASettings, ARelativePath, AText,
        TCheckOrigin.Make(AProject, ASource), mScopes);
    end;
end;

class function TRuleBulkFix.CheckWith(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARelativePath: string; const AProject: TCheckProject; const ASource: TPascalSource;
  const ABaseline: IRuleBaseline): TBulkFixCheck;
begin
  if ABaseline = nil then
  begin
    Exit(CheckWith(ARules, ASettings, ARelativePath, AProject, ASource));
  end;
  Result :=
    function(const AText: string; const ALines: TBulkFixLineMap): TArray<TRuleFinding>
    var
      mScopes: TFindingScopes;
    begin
      Result := TFileChecker.CheckText(ARules, ASettings, ARelativePath, AText,
        TCheckOrigin.Make(AProject, ASource), mScopes);
      Result := ABaseline.Filter(ARelativePath, AText, mScopes, Result);
    end;
end;

end.
