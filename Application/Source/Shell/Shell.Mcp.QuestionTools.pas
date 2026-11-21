unit Shell.Mcp.QuestionTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Rückfragen von KI-Assistenten an den Menschen in der laufenden IDE
// (ask_user, #2620). Argumente, Auftrag und Antworttexte regelt Atlas.Common.Mcp.IdeQuestions, den Austausch mit dem
// Plugin Shell.Mcp.Ide. Dazu die Rückfragen schreibender Werkzeuge (Stufe 2): zuerst über den Client
// (elicitation/create), sonst in der IDE, sonst ohne Rückfrage (Atlas.Common.Mcp.Confirm).

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet ask_user an und gibt den schreibenden Werkzeugen den Weg für Rückfragen.</summary>
procedure RegisterQuestionTools(const AContext: TMcpToolContext);

implementation

uses
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IdeQuestions,
  Atlas.Common.Mcp.Confirm,
  Core.WorkspaceGroup,
  Shell.Mcp.Ide;

function ToolAskUser(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := AskInIde(AContext.Root, AContext.Group.ProcessIdentity.Client, AArguments);
end;

// Jede Frage-Funktion in eigener Routine: Fingen sich anonyme Methoden derselben Routine gegenseitig ein, hielte
// der gemeinsame Rahmen sich selbst fest.
function ClientAsk(AServer: TMcpServer): TMcpAskFunc;
begin
  Result :=
    function(const AQuestion: TMcpIdeQuestion; out AAnswer: string): TMcpQuestionOutcome
    begin
      Result := TMcpConfirm.AskClient(AServer.Outgoing, AQuestion, AAnswer);
    end;
end;

function IdeAsk(const ARoot: string): TMcpAskFunc;
begin
  Result :=
    function(const AQuestion: TMcpIdeQuestion; out AAnswer: string): TMcpQuestionOutcome
    begin
      Result := AskQuestionInIde(ARoot, AQuestion, AAnswer);
    end;
end;

function ConfirmChooser(const AContext: TMcpToolContext): TMcpChooseFunc;
var
  mServer: TMcpServer;
  mGroup: TCoreWorkspaceGroup;
  mClient, mIde: TMcpAskFunc;
begin
  mServer := AContext.Server;
  mGroup := AContext.Group;
  mClient := ClientAsk(mServer);
  mIde := IdeAsk(AContext.Root);
  Result :=
    function(const AText: string; const AOptions: TArray<string>): Integer
    var
      mViaClient: TMcpAskFunc;
    begin
      if (mGroup = nil) or not mGroup.Main.Configuration.Settings.McpConfirm then
      begin
        Exit(TMcpConfirm.cNotAsked);
      end;
      mViaClient := nil;
      if mServer.ClientElicits and (mServer.Outgoing <> nil) then
      begin
        mViaClient := mClient;
      end;
      Result := TMcpConfirm.Choose(mViaClient, mIde,
        TMcpConfirm.Question(AText, AOptions, mGroup.ProcessIdentity.Client));
    end;
end;

procedure RegisterQuestionTools(const AContext: TMcpToolContext);
begin
  if AContext.Edit <> nil then
  begin
    AContext.Edit.Choose := ConfirmChooser(AContext);
  end;
  AContext.Server.AddTool(TMcpIdeQuestions.cTool, TMcpIdeQuestions.ToolDescription, TMcpIdeQuestions.InputSchema,
    ContextTool(AContext, ToolAskUser), TMcpToolKind.Process);
end;

end.
