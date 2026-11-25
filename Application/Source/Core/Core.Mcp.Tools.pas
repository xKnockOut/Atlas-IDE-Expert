unit Core.Mcp.Tools;

// Host-Rolle Core: MCP-Modus (--mcp, #48), meldet alle Werkzeuge in der Reihenfolge von tools/list an.

interface

uses
  Core.Mcp.Context;

/// <summary>Meldet alle Werkzeuge mit Kontext an; CheckSource kommt aus AContext.Group.</summary>
procedure RegisterContextTools(const AContext: TMcpToolContext);

implementation

uses
  Core.Mcp.NavigationTools,
  Core.Mcp.BuildTestTools,
  Core.Mcp.DebugTools,
  Core.Mcp.IdeContextTools,
  Core.Mcp.QuestionTools,
  Core.Mcp.ReportTools,
  Core.Mcp.CheckTools,
  Core.Mcp.ArchitectureTools,
  Core.Mcp.EditingTools,
  Core.Mcp.ProjectTools,
  Core.Mcp.ChangeTools,
  Core.Mcp.HistoryTools,
  Core.Mcp.IssueTools;

procedure RegisterContextTools(const AContext: TMcpToolContext);
var
  mContext: TMcpToolContext;
begin
  mContext := AContext;
  // Symbole und Include-Dateien der Gruppe wie im Server (#860).
  mContext.CheckSource := CheckSourceOf(mContext.Group);
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
