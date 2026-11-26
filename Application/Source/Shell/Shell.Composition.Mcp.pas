unit Shell.Composition.Mcp;

// Host-Adapter der MCP-Werkzeuge: verbindet die SPIs im Mcp-Contract (Mcp.Contract.*) mit den
// Schnittstellen der liefernden Features. Nur hier entstehen die Adapter.

interface

uses
  Atlas.Common.Index.Contract,
  Rules.Contract,
  Rules.Checker,
  Mcp.Contract.BoundaryCases,
  Mcp.Contract.BulkFix,
  Mcp.Contract.CompilerFixes,
  Mcp.Contract.Conventions,
  Mcp.Contract.DeadCode,
  Mcp.Contract.Extract,
  Mcp.Contract.Formatting,
  Mcp.Contract.RuleDocs,
  Mcp.Contract.TextChecks,
  Atlas.Common.Checks.Contract,
  Atlas.Common.Projects.Contract.Group,
  Atlas.Common.Pascal.Contract;

type
  TMcpComposition = record
    /// <summary>„Methode extrahieren“ aus Editing.</summary>
    class function Extract: IMcpExtract; static;
    /// <summary>Formatierer aus Editing.</summary>
    class function Formatting: IMcpFormatting; static;
    /// <summary>Schnellkorrekturen für Compilermeldungen aus Editing.</summary>
    class function CompilerFixes: IMcpCompilerFixes; static;
    /// <summary>Grenzfälle einer Routine aus Editing.</summary>
    class function BoundaryCases: IMcpBoundaryCases; static;
    /// <summary>Sammelkorrektur aus Rules mit den eingebauten Regeln; AProject und ASource wie bei der Prüfung der
    /// MCP-Werkzeuge (nil = ohne Index bzw. Vordefinitionen).</summary>
    class function BulkFix(const AProject: TCheckProjectFunc; const ASource: TPascalSourceFunc): IMcpBulkFix; static;
    /// <summary>Prüfung von Texten aus Rules mit den eingebauten Regeln; AProject und ASource je Datei (nil = ohne
    /// Index bzw. Vordefinitionen).</summary>
    class function TextChecks(const AProject: TCheckProjectFunc; const ASource: TPascalSourceFunc): IMcpTextChecks;
      static;
    /// <summary>Wie TextChecks mit den Regeln ARules.</summary>
    class function TextChecksWith(const ARules: TArray<IRule>; const AProject: TCheckProjectFunc;
      const ASource: TPascalSourceFunc): IMcpTextChecks; static;
    /// <summary>Regeln für ungenutzten Code aus Rules mit den eingebauten Regeln, dem Index AIndex, den Projekten
    /// AProjectFiles (nil = keine Datei lesbar) und den Namensräumen ANamespaces.</summary>
    class function DeadCode(const AIndex: ISymbolIndex; const AProjectFiles: IProjectGroupFiles;
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
  Rules.Contract.Api,
  Rules.Builtin,
  Rules.Providers.BulkFix,
  Rules.Providers.Conventions,
  Rules.Providers.DeadCode,
  Rules.Providers.FindingPrompts,
  Rules.Providers.RuleDocs,
  Rules.Providers.TextChecks,
  Editing.Composition,
  Adapters.Mcp.BoundaryCases,
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

class function TMcpComposition.BoundaryCases: IMcpBoundaryCases;
begin
  Result := TMcpBoundaryCasesAdapter.Create(TEditingComposition.BoundaryCases);
end;

class function TMcpComposition.BulkFix(const AProject: TCheckProjectFunc;
  const ASource: TPascalSourceFunc): IMcpBulkFix;
var
  mBulkFix: IRuleBulkFix;
begin
  mBulkFix := TRuleBulkFixProvider.Create(BuiltinRules, AProject, ASource);
  Result := TMcpBulkFixAdapter.Create(mBulkFix);
end;

class function TMcpComposition.TextChecks(const AProject: TCheckProjectFunc;
  const ASource: TPascalSourceFunc): IMcpTextChecks;
begin
  Result := TextChecksWith(BuiltinRules, AProject, ASource);
end;

class function TMcpComposition.TextChecksWith(const ARules: TArray<IRule>; const AProject: TCheckProjectFunc;
  const ASource: TPascalSourceFunc): IMcpTextChecks;
var
  mChecks: IRuleTextChecks;
begin
  mChecks := TRuleTextChecksProvider.Create(ARules, AProject, ASource);
  Result := TMcpTextChecksAdapter.Create(mChecks);
end;

class function TMcpComposition.DeadCode(const AIndex: ISymbolIndex; const AProjectFiles: IProjectGroupFiles;
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
