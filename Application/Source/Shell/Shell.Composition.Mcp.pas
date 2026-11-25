unit Shell.Composition.Mcp;

// Host-Adapter der MCP-Werkzeuge: verbindet die SPIs im Mcp-Contract (Atlas.Common.Mcp.Contract.*) mit den
// Schnittstellen der liefernden Features. Nur hier entstehen die Adapter.

interface

uses
  Atlas.Common.Rules.Checker,
  Atlas.Common.Mcp.Contract.BulkFix,
  Atlas.Common.Mcp.Contract.CompilerFixes,
  Atlas.Common.Mcp.Contract.Conventions,
  Atlas.Common.Mcp.Contract.Extract,
  Atlas.Common.Mcp.Contract.Formatting;

type
  TMcpComposition = record
    /// <summary>„Methode extrahieren“ aus Editing.</summary>
    class function Extract: IMcpExtract; static;
    /// <summary>Formatierer aus Editing.</summary>
    class function Formatting: IMcpFormatting; static;
    /// <summary>Schnellkorrekturen für Compilermeldungen aus Editing.</summary>
    class function CompilerFixes: IMcpCompilerFixes; static;
    /// <summary>Sammelkorrektur aus Rules mit den eingebauten Regeln; AProject und ASource wie bei der Prüfung der
    /// MCP-Werkzeuge (nil = ohne Index bzw. Vordefinitionen).</summary>
    class function BulkFix(const AProject: TCheckProjectFunc; const ASource: TCheckSourceFunc): IMcpBulkFix; static;
    /// <summary>Projektkonventionen aus Rules mit den eingebauten Regeln.</summary>
    class function Conventions: IMcpConventions; static;
    /// <summary>Auftrag zu einem Befund aus Rules.</summary>
    class function FindingPrompts: IMcpFindingPrompts; static;
  end;

implementation

uses
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Providers.BulkFix,
  Atlas.Common.Rules.Providers.Conventions,
  Atlas.Common.Rules.Providers.FindingPrompts,
  Atlas.Common.Editing.Composition,
  Adapters.Mcp.BulkFix,
  Adapters.Mcp.CompilerFixes,
  Adapters.Mcp.Conventions,
  Adapters.Mcp.Extract,
  Adapters.Mcp.Formatting;

{ TMcpComposition }

class function TMcpComposition.Extract: IMcpExtract;
begin
  Result := TMcpExtractAdapter.Create(TEditingComposition.Extract);
end;

class function TMcpComposition.Formatting: IMcpFormatting;
begin
  Result := TMcpFormattingAdapter.Create(TEditingComposition.Formatting);
end;

class function TMcpComposition.CompilerFixes: IMcpCompilerFixes;
begin
  Result := TMcpCompilerFixesAdapter.Create(TEditingComposition.CompilerFixes);
end;

class function TMcpComposition.BulkFix(const AProject: TCheckProjectFunc;
  const ASource: TCheckSourceFunc): IMcpBulkFix;
var
  mBulkFix: IRuleBulkFix;
begin
  mBulkFix := TRuleBulkFixProvider.Create(BuiltinRules, AProject, ASource);
  Result := TMcpBulkFixAdapter.Create(mBulkFix);
end;

class function TMcpComposition.Conventions: IMcpConventions;
var
  mConventions: IRuleConventions;
begin
  mConventions := TRuleConventionsProvider.Create(BuiltinRules);
  Result := TMcpConventionsAdapter.Create(mConventions);
end;

class function TMcpComposition.FindingPrompts: IMcpFindingPrompts;
var
  mPrompts: IRuleFindingPrompts;
begin
  mPrompts := TRuleFindingPromptsProvider.Create;
  Result := TMcpFindingPromptsAdapter.Create(mPrompts);
end;

end.
