unit Shell.Composition.DfmPropertyRules;

// Befehl „Eigenschaftsregeln anwenden“ (#309) der Komposition: Units im Bereich form, project oder group und die
// Befunde nur der Regel dfm-property, daraus ein WorkspaceEdit über die Formulardateien.

interface

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Workspaces,
  Shell.Composition.RuleContext;

type
  /// <summary>Was der Befehl von der Komposition braucht.</summary>
  TShellDfmPropertyRulesServices = record
    Logger: ILogger;
    Workspaces: TShellWorkspaceRegistry;
    RuleContext: TShellRuleContext;
    ReadText: TReferenceReadText;
  end;

  /// <summary>Wendet die Eigenschaftsregeln auf Formulardateien an.</summary>
  TShellDfmPropertyRules = class
  public
    /// <summary>Meldet den Befehl an.</summary>
    class procedure Attach(ACommands: TLspCommands; const AServices: TShellDfmPropertyRulesServices); static;
    /// <summary>Argumente: URI der Unit oder Formulardatei, Bereich form (Vorgabe), project oder group.</summary>
    class function Apply(const AServices: TShellDfmPropertyRulesServices; const AArguments: TJSONArray): TJSONValue;
      static;
    /// <summary>Units im Bereich form, project oder group zur Unit AFileName.</summary>
    class function UnitsFor(const AServices: TShellDfmPropertyRulesServices; const AFileName, AScope: string):
      TArray<string>; static;
    /// <summary>Befunde nur der Regel dfm-property für eine Unit mit Formulardatei.</summary>
    class function FindingsFor(const AServices: TShellDfmPropertyRulesServices; const AFileName: string;
      out AFindings: TArray<TRuleFinding>): Boolean; static;
    /// <summary>Nur die Regeln mit der Kennung AId.</summary>
    class function RulesWithId(const ARules: TArray<IRule>; const AId: string): TArray<IRule>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Lsp.DfmPropertyRules,
  Shell.Workspace;

class procedure TShellDfmPropertyRules.Attach(ACommands: TLspCommands;
  const AServices: TShellDfmPropertyRulesServices);
var
  mServices: TShellDfmPropertyRulesServices;
begin
  mServices := AServices;
  ACommands.Register(TLspDfmPropertyRules.Command,
    function(const AArguments: TJSONArray): TJSONValue
    begin
      Result := Apply(mServices, AArguments);
    end);
end;

class function TShellDfmPropertyRules.Apply(const AServices: TShellDfmPropertyRulesServices;
  const AArguments: TJSONArray): TJSONValue;
var
  mServices: TShellDfmPropertyRulesServices;
  mScope: string;
  mFiles, mEdits: Integer;
begin
  if (AArguments = nil) or (AArguments.Count = 0) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Argument "uri" fehlt');
  end;
  mScope := TLspDfmPropertyRules.ScopeForm;
  if AArguments.Count > 1 then
  begin
    mScope := AArguments.Items[1].Value;
  end;
  mServices := AServices;
  Result := TLspDfmPropertyRules.BuildEdit(
    UnitsFor(AServices, TLspDfmPropertyRules.UnitOf(TDocumentUris.ToPath(AArguments.Items[0].Value)), mScope),
    function(const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean
    begin
      Result := FindingsFor(mServices, AFileName, AFindings);
    end, mFiles, mEdits);
  // Nur Zahlen ins Log, keine Pfade (#647).
  AServices.Logger.Info(Format('Eigenschaftsregeln: %d Änderungen in %d Formulardateien vorgeschlagen',
    [mEdits, mFiles]));
end;

class function TShellDfmPropertyRules.UnitsFor(const AServices: TShellDfmPropertyRulesServices;
  const AFileName, AScope: string): TArray<string>;
var
  mWorkspace, mPicked: TShellWorkspace;
begin
  if SameText(AScope, TLspDfmPropertyRules.ScopeForm) then
  begin
    Result := TArray<string>.Create(AFileName);
    Exit;
  end;
  Result := nil;
  System.TMonitor.Enter(AServices.Workspaces.Lock);
  try
    mPicked := AServices.Workspaces.Pick(AFileName);
    for mWorkspace in AServices.Workspaces.Items do
    begin
      if SameText(AScope, TLspDfmPropertyRules.ScopeGroup) or (mWorkspace = mPicked) then
      begin
        Result := Result + mWorkspace.State.ProjectFiles;
      end;
    end;
  finally
    System.TMonitor.Exit(AServices.Workspaces.Lock);
  end;
end;

class function TShellDfmPropertyRules.RulesWithId(const ARules: TArray<IRule>; const AId: string): TArray<IRule>;
var
  mRule: IRule;
begin
  Result := nil;
  for mRule in ARules do
  begin
    if SameText(mRule.Descriptor.Id, AId) then
    begin
      Result := Result + [mRule];
    end;
  end;
end;

class function TShellDfmPropertyRules.FindingsFor(const AServices: TShellDfmPropertyRulesServices;
  const AFileName: string; out AFindings: TArray<TRuleFinding>): Boolean;
var
  mContext: TRuleCheckContext;
  mText: string;
  mTree: TSyntaxTree;
begin
  AFindings := nil;
  Result := SameText(ExtractFileExt(AFileName), '.pas') and
    AServices.RuleContext.RuleContextFor(TDocumentUris.FromPath(AFileName), mContext) and
    (mContext.FormFile <> '') and AServices.ReadText(AFileName, mText);
  if not Result then
  begin
    Exit;
  end;
  // Nur dfm-property; RuleFindings zieht die Baseline nicht ab, der Befehl korrigiert alle Verstöße.
  mContext.Rules := RulesWithId(mContext.Rules, TLspDfmPropertyRules.RuleId);
  mTree := TSyntaxTreeCache.Parse(mText);
  try
    AFindings := TLspSyntaxDiagnostics.RuleFindings(mText, mTree, mContext);
  finally
    mTree.Free;
  end;
end;

end.
