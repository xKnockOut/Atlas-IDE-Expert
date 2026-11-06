unit Shell.Composition.Capabilities;

// Capabilities, die der Server auf initialize meldet: Anbieter je Feature und die Befehle für
// workspace/executeCommand. Pull-Diagnosen trägt die Teilwurzel Diagnosen je nach Client nach (#82).

interface

uses
  System.JSON;

type
  /// <summary>Baut die Capabilities für initialize.</summary>
  TShellCapabilities = class
  public
    /// <summary>Neue Capabilities; der Aufrufer gibt sie frei.</summary>
    class function Build: TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Lsp.TextDocumentSync,
  Atlas.Common.Lsp.Formatting,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.SignatureHelp,
  Atlas.Common.Lsp.CodeLens,
  Atlas.Common.Lsp.SemanticTokens,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.DocumentLinks,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Lsp.Processes,
  Atlas.Common.Lsp.PullDiagnostics,
  Atlas.Common.Lsp.QualifiedNames,
  Atlas.Common.Lsp.EnumValueCommands,
  Atlas.Common.Lsp.StringLiteralCommands,
  Atlas.Common.Lsp.Baseline,
  Atlas.Common.Lsp.WorkspaceFolders,
  Atlas.Common.Diagnostics.BugReport,
  Atlas.Common.Diagnostics.ServerPackage,
  Shell.CrashCases,
  Shell.Composition.ServerCommands;

class function TShellCapabilities.Build: TJSONObject;
var
  mCommands: TJSONArray;
begin
  // Die Features tragen ihre Capabilities hier ein, sobald sie umgesetzt sind.
  Result := TJSONObject.Create;
  Result.AddPair('textDocumentSync', TLspTextDocumentSync.Capability);
  Result.AddPair('documentSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('foldingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('linkedEditingRangeProvider', TJSONBool.Create(True));
  Result.AddPair('documentFormattingProvider', TJSONBool.Create(True));
  // Nur für den Schnellbefehl /uses (#254); Blockabschluss (#179) übernimmt die IDE.
  Result.AddPair('documentOnTypeFormattingProvider', TLspFormatting.OnTypeCapability);
  Result.AddPair('documentRangeFormattingProvider', TJSONBool.Create(True));
  Result.AddPair('selectionRangeProvider', TJSONBool.Create(True));
  Result.AddPair('definitionProvider', TJSONBool.Create(True));
  Result.AddPair('declarationProvider', TJSONBool.Create(True));
  Result.AddPair('typeDefinitionProvider', TJSONBool.Create(True));
  Result.AddPair('hoverProvider', TJSONBool.Create(True));
  Result.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('documentHighlightProvider', TJSONBool.Create(True));
  Result.AddPair('referencesProvider', TJSONBool.Create(True));
  Result.AddPair('renameProvider', TLspRename.Capability);
  Result.AddPair('completionProvider', TLspCompletion.Capability);
  Result.AddPair('signatureHelpProvider', TLspSignatureHelp.Capability);
  Result.AddPair('typeHierarchyProvider', TJSONBool.Create(True));
  Result.AddPair('callHierarchyProvider', TJSONBool.Create(True));
  Result.AddPair('implementationProvider', TJSONBool.Create(True));
  Result.AddPair('inlayHintProvider', TJSONBool.Create(True));
  Result.AddPair('inlineValueProvider', TJSONBool.Create(True));
  Result.AddPair('codeLensProvider', TLspCodeLens.Capability);
  Result.AddPair('semanticTokensProvider', TLspSemanticTokens.Capability);
  Result.AddPair('codeActionProvider', TLspCodeActions.Capability);
  Result.AddPair('documentLinkProvider', TLspDocumentLinks.Capability);
  Result.AddPair('colorProvider', TJSONBool.Create(True));
  mCommands := TJSONArray.Create;
  mCommands.Add(cStatusCommand);
  mCommands.Add(TShellCrashCases.RetryCommand);
  mCommands.Add(cProcessesCommand);
  mCommands.Add(TShellServerCommands.CompileCommand);
  mCommands.Add(TShellServerCommands.SelectBuildCommand);
  mCommands.Add(TShellServerCommands.SelectProjectCommand);
  mCommands.Add(TShellServerCommands.RebuildIndexCommand);
  mCommands.Add(cClearIndexCommand);
  mCommands.Add(TLspPullDiagnostics.cRecheckCommand);
  mCommands.Add(TBugReport.cCommand);
  mCommands.Add(TServerPackage.cCommand);
  mCommands.Add(TQualifiedNames.cCommand);
  mCommands.Add(TEnumValueCommands.cCommand);
  mCommands.Add(TStringLiteralCommands.cPlainTextCommand);
  mCommands.Add(TStringLiteralCommands.cToLiteralCommand);
  // Editor-Befehl (#97): Clients wie VS Code bieten ihn damit an.
  mCommands.Add(TLspBaseline.cCommand);
  Result.AddPair('executeCommandProvider', TJSONObject.Create(TJSONPair.Create('commands', mCommands)));
  Result.AddPair('workspace', TLspWorkspaceFolders.Capability);
end;

end.
