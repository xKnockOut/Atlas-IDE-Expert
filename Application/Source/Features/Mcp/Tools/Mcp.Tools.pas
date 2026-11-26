unit Mcp.Tools;

// Host-Rolle Core: MCP-Modus (--mcp, #48), meldet alle Werkzeuge in der Reihenfolge von tools/list an.

interface

uses
  Mcp.Tools.Context;

/// <summary>Meldet alle Werkzeuge mit Kontext an; CheckSource kommt aus AContext.Workspace.</summary>
procedure RegisterContextTools(const AContext: TMcpToolContext);

implementation

uses
  Mcp.Tools.Navigation,
  Mcp.Tools.BuildTest,
  Mcp.Tools.Debug,
  Mcp.Tools.IdeContext,
  Mcp.Tools.Question,
  Mcp.Tools.Report,
  Mcp.Tools.Check,
  Mcp.Tools.Architecture,
  Mcp.Tools.Editing,
  Mcp.Tools.Project,
  Mcp.Tools.Change,
  Mcp.Tools.History,
  Mcp.Tools.Issue;

procedure RegisterContextTools(const AContext: TMcpToolContext);
var
  mContext: TMcpToolContext;
begin
  mContext := AContext;
  // Symbole und Include-Dateien der Gruppe wie im Server (#860).
  mContext.CheckSource := CheckSourceOf(mContext.Workspace);
  RegisterNavigationTools(mContext);
  RegisterBuildTestTools(mContext);
  RegisterDebugTools(mContext);
  RegisterIdeContextTools(mContext);
  RegisterQuestionTools(mContext);
  RegisterReportTools(mContext);
  RegisterCheckTools(mContext);
  RegisterArchitectureTools(mContext);
  RegisterEditingTools(mContext);
  RegisterDeadCodeTools(mContext);
  RegisterAffectedTestsTool(mContext);
  RegisterQueryTools(mContext);
  RegisterHotspotTools(mContext);
  RegisterSymbolHistoryTool(mContext);
  RegisterStatusTools(mContext);
  RegisterIssueTools(mContext);
end;

end.
