unit Core.Mcp.BuildTestTools;

// Host-Rolle Core: MCP-Modus (--mcp, #48), meldet die Werkzeuge für Builds und Tests in der Reihenfolge von
// tools/list an; die Werkzeuge selbst stehen in Core.Mcp.BuildTools, Core.Mcp.TestRunTools und
// Core.Mcp.TestDesignTools.

interface

uses
  Core.Mcp.Context;

/// <summary>Meldet get_last_build, get_last_tests, build_project, run_tests, get_profile, get_mutants,
/// suggest_test_cases und explain_compiler_message an.</summary>
procedure RegisterBuildTestTools(const AContext: TMcpToolContext);

implementation

uses
  Core.Mcp.BuildTools,
  Core.Mcp.TestRunTools,
  Core.Mcp.TestDesignTools;

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
