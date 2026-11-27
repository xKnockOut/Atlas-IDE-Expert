unit Mcp.Tools.BuildTest;

// Hosted-Feature Mcp: MCP-Modus (--mcp, #48), meldet die Werkzeuge für Builds und Tests in der Reihenfolge von
// tools/list an; die Werkzeuge selbst stehen in Mcp.Tools.Build, Mcp.Tools.TestRun und
// Mcp.Tools.TestDesign.

interface

uses
  Mcp.Tools.Context;

/// <summary>Meldet get_last_build, get_last_tests, build_project, run_tests, get_profile, get_mutants,
/// suggest_test_cases und explain_compiler_message an.</summary>
procedure RegisterBuildTestTools(const AContext: TMcpToolContext);

implementation

uses
  Mcp.Tools.Build,
  Mcp.Tools.TestRun,
  Mcp.Tools.TestDesign;

procedure RegisterBuildTestTools(const AContext: TMcpToolContext);
begin
  AddGetLastBuild(AContext);
  AddGetLastTests(AContext);
  AddBuildProject(AContext);
  AddRunTests(AContext);
  AddGetProfile(AContext);
  AddGetMutants(AContext);
  AddSuggestTestCases(AContext);
  AddExplainCompilerMessage(AContext);
end;


end.
