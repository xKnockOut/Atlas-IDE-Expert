unit Shell.Composition.Mcp;

// Host-Adapter der MCP-Werkzeuge: verbindet die SPIs im Mcp-Contract (Atlas.Common.Mcp.Contract.*) mit den
// Schnittstellen der liefernden Features. Nur hier entstehen die Adapter.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Mcp.Contract.BulkFix,
  Atlas.Common.Mcp.Contract.CompilerFixes,
  Atlas.Common.Mcp.Contract.Conventions,
  Atlas.Common.Mcp.Contract.DeadCode,
  Atlas.Common.Mcp.Contract.Extract,
  Atlas.Common.Mcp.Contract.Formatting,
  Atlas.Common.Mcp.Contract.RuleDocs,
  Atlas.Common.Mcp.Contract.TextChecks,
  Atlas.Common.Checks.Contract;

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
    /// <summary>Prüfung von Texten aus Rules mit den eingebauten Regeln; AProject und ASource je Datei (nil = ohne
    /// Index bzw. Vordefinitionen).</summary>
    class function TextChecks(const AProject: TCheckProjectFunc; const ASource: TCheckSourceFunc): IMcpTextChecks;
      static;
    /// <summary>Wie TextChecks mit den Regeln ARules.</summary>
    class function TextChecksWith(const ARules: TArray<IRule>; const AProject: TCheckProjectFunc;
      const ASource: TCheckSourceFunc): IMcpTextChecks; static;
    /// <summary>Regeln für ungenutzten Code aus Rules mit den eingebauten Regeln, dem Index AIndex, den Projekten
    /// AProjectFiles (nil = keine Datei lesbar) und den Namensräumen ANamespaces.</summary>
    class function DeadCode(const AIndex: ISymbolIndex; const AProjectFiles: IRuleProjectFiles;
      const ANamespaces: TArray<string>): IMcpDeadCode; static;
    /// <summary>Projektkonventionen aus Rules mit den eingebauten Regeln.</summary>
    class function Conventions: IMcpConventions; static;
    /// <summary>Auftrag zu einem Befund aus Rules.</summary>
    class function FindingPrompts: IMcpFindingPrompts; static;
    /// <summary>Regelkatalog zum Nachschlagen aus Rules.</summary>
    class function RuleDocs: IMcpRuleDocs; static;
  end;

implementation

uses
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Providers.BulkFix,
  Atlas.Common.Rules.Providers.Conventions,
  Atlas.Common.Rules.Providers.DeadCode,
  Atlas.Common.Rules.Providers.FindingPrompts,
  Atlas.Common.Rules.Providers.RuleDocs,
  Atlas.Common.Rules.Providers.TextChecks,
  Atlas.Common.Editing.Composition,
  Adapters.Mcp.BulkFix,
  Adapters.Mcp.CompilerFixes,
  Adapters.Mcp.Conventions,
  Adapters.Mcp.DeadCode,
  Adapters.Mcp.Extract,
  Adapters.Mcp.Formatting,
  Adapters.Mcp.RuleDocs,
  Adapters.Mcp.TextChecks;

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

class function TMcpComposition.TextChecks(const AProject: TCheckProjectFunc;
  const ASource: TCheckSourceFunc): IMcpTextChecks;
begin
  Result := TextChecksWith(BuiltinRules, AProject, ASource);
end;

class function TMcpComposition.TextChecksWith(const ARules: TArray<IRule>; const AProject: TCheckProjectFunc;
  const ASource: TCheckSourceFunc): IMcpTextChecks;
var
  mChecks: IRuleTextChecks;
begin
  mChecks := TRuleTextChecksProvider.Create(ARules, AProject, ASource);
  Result := TMcpTextChecksAdapter.Create(mChecks);
end;

class function TMcpComposition.DeadCode(const AIndex: ISymbolIndex; const AProjectFiles: IRuleProjectFiles;
  const ANamespaces: TArray<string>): IMcpDeadCode;
var
  mDeadCode: IRuleDeadCode;
begin
  mDeadCode := TRuleDeadCodeProvider.Create(BuiltinRules, AIndex, AProjectFiles, ANamespaces);
  Result := TMcpDeadCodeAdapter.Create(mDeadCode);
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

class function TMcpComposition.RuleDocs: IMcpRuleDocs;
var
  mDocs: IRuleDocs;
begin
  mDocs := TRuleDocsProvider.Create;
  Result := TMcpRuleDocsAdapter.Create(mDocs);
end;

end.
