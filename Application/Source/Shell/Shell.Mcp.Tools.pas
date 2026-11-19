unit Shell.Mcp.Tools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), meldet alle Werkzeuge in der Reihenfolge von tools/list an.

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet alle Werkzeuge mit Kontext an; CheckSource und CheckProject kommen aus AContext.Group.</summary>
procedure RegisterContextTools(const AContext: TMcpToolContext);

implementation

uses
  Shell.Mcp.NavigationTools,
  Shell.Mcp.BuildTestTools,
  Shell.Mcp.DebugTools,
  Shell.Mcp.IdeContextTools,
  Shell.Mcp.ReportTools,
  Shell.Mcp.CheckTools,
  Shell.Mcp.ArchitectureTools,
  Shell.Mcp.EditingTools,
  Shell.Mcp.ProjectTools,
  Shell.Mcp.ChangeTools,
  Shell.Mcp.IssueTools;

procedure RegisterContextTools(const AContext: TMcpToolContext);
var
  mContext: TMcpToolContext;
begin
  mContext := AContext;
  // Symbolindex und Projektdienste für die Prüfregeln wie im Server (#1112).
  mContext.CheckSource := CheckSourceOf(mContext.Group);
  mContext.CheckProject := CheckProjectOf(mContext.Group);
  RegisterNavigationTools(mContext);
  RegisterBuildTestTools(mContext);
  RegisterDebugTools(mContext);
  RegisterIdeContextTools(mContext);
  RegisterReportTools(mContext);
  RegisterCheckTools(mContext);
  RegisterArchitectureTools(mContext);
  RegisterEditingTools(mContext);
  RegisterDeadCodeTools(mContext);
  RegisterAffectedTestsTool(mContext);
  RegisterQueryTools(mContext);
  RegisterHotspotTools(mContext);
  RegisterStatusTools(mContext);
  RegisterIssueTools(mContext);
end;

end.
