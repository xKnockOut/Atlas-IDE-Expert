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
  Lsp.TextDocumentSync,
  Editing.Formatting.Protocol,
  Atlas.Common.Semantics.Renames,
  Lsp.Completion,
  Lsp.SignatureHelp,
  Lsp.CodeLens,
  Lsp.SemanticTokens,
  Lsp.CodeActions,
  Editing.DocumentLinks.Protocol,
  Atlas.Common.JsonRpc.ServerStatus,
  Lsp.Processes,
  Lsp.PullDiagnostics,
  Atlas.Common.Semantics.QualifiedNames,
  Lsp.EnumValueCommands,
  Lsp.StringLiteralCommands,
  Lsp.Baseline,
  Lsp.WorkspaceFolders,
  Atlas.Common.Diagnostics.BugReport,
  Atlas.Common.Diagnostics.ServerPackage,
  Core.CrashCases,
  Shell.Composition.ServerCommands;

{ TShellCapabilities }

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
  Result.AddPair('documentOnTypeFormattingProvider', TFormattingProtocol.OnTypeCapability);
  Result.AddPair('documentRangeFormattingProvider', TJSONBool.Create(True));
  Result.AddPair('selectionRangeProvider', TJSONBool.Create(True));
  Result.AddPair('definitionProvider', TJSONBool.Create(True));
  Result.AddPair('declarationProvider', TJSONBool.Create(True));
  Result.AddPair('typeDefinitionProvider', TJSONBool.Create(True));
  Result.AddPair('hoverProvider', TJSONBool.Create(True));
  Result.AddPair('workspaceSymbolProvider', TJSONBool.Create(True));
  Result.AddPair('documentHighlightProvider', TJSONBool.Create(True));
  Result.AddPair('referencesProvider', TJSONBool.Create(True));
  Result.AddPair('renameProvider', TRenames.Capability);
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
  Result.AddPair('documentLinkProvider', TDocumentLinksProtocol.Capability);
  Result.AddPair('colorProvider', TJSONBool.Create(True));
  mCommands := TJSONArray.Create;
  mCommands.Add(cStatusCommand);
  mCommands.Add(TCoreCrashCases.cRetryCommand);
  mCommands.Add(cProcessesCommand);
  mCommands.Add(TShellServerCommands.cCompileCommand);
  mCommands.Add(TShellServerCommands.cSelectBuildCommand);
  mCommands.Add(TShellServerCommands.cSelectProjectCommand);
  mCommands.Add(TShellServerCommands.cRebuildIndexCommand);
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
