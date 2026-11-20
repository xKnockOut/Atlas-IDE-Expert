unit Shell.Mcp.QuestionTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Rückfragen von KI-Assistenten an den Menschen in der laufenden IDE
// (ask_user, #2620). Argumente, Auftrag und Antworttexte regelt Atlas.Common.Mcp.IdeQuestions, den Austausch mit dem
// Plugin Shell.Mcp.Ide.

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet ask_user an.</summary>
procedure RegisterQuestionTools(const AContext: TMcpToolContext);

implementation

uses
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IdeQuestions,
  Shell.Mcp.Ide;

function ToolAskUser(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AskInIde(AContext.Root, AContext.Group.ProcessIdentity.Client, AArguments);
end;

procedure RegisterQuestionTools(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool(TMcpIdeQuestions.cTool, TMcpIdeQuestions.ToolDescription, TMcpIdeQuestions.InputSchema,
    ContextTool(AContext, ToolAskUser), TMcpToolKind.Process);
end;

end.
