unit Core.Mcp.QuestionTools;

// Host-Rolle Core: MCP-Modus (--mcp, #48), Rückfragen von KI-Assistenten an den Menschen in der laufenden IDE
// (ask_user, #2620). Argumente, Auftrag und Antworttexte regelt Atlas.Common.Mcp.IdeQuestions, den Austausch mit dem
// Plugin Core.Mcp.Ide. Dazu die Rückfragen schreibender Werkzeuge (Stufe 2): zuerst über den Client
// (elicitation/create), sonst in der IDE, sonst ohne Rückfrage (Atlas.Common.Mcp.Confirm). Derselbe Weg fragt, ob
// debug_start und build_project ein Projekt öffnen dürfen, das in keiner IDE offen ist (mcp.openProjects, #2895).

interface

uses
  Core.Mcp.Context,
  Core.Mcp.Ide;

/// <summary>Meldet ask_user an und gibt den schreibenden Werkzeugen den Weg für Rückfragen.</summary>
procedure RegisterQuestionTools(const AContext: TMcpToolContext);
/// <summary>Öffnen nicht offener Projekte für debug_start und build_project nach mcp.openProjects (#2895):
/// Projektdateien unter dem Arbeitsordner, gefragt über den Client oder die IDE.</summary>
function IdeOpenOf(const AContext: TMcpToolContext): TMcpIdeOpen;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IdeQuestions,
  Atlas.Common.Mcp.IdeBuilds,
  Atlas.Common.Mcp.Confirm,
  Atlas.Common.Mcp.Contract.Workspace;

function ToolAskUser(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
begin
  Result := TMcpIde.Create(AContext.Adapters.Process).AskInIde(AContext.Root, AContext.Workspace.Client, AArguments);
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

function IdeAsk(const AIde: TMcpIde; const ARoot: string): TMcpAskFunc;
begin
  Result :=
    function(const AQuestion: TMcpIdeQuestion; out AAnswer: string): TMcpQuestionOutcome
    begin
      Result := AIde.AskQuestionInIde(ARoot, AQuestion, AAnswer);
    end;
end;

/// <summary>Fragt den Menschen: über den Client, wenn er Rückfragen anbietet, sonst in der IDE. AGate: nur fragen,
/// wenn die Einstellung es erlaubt (nil = immer).</summary>
function HumanChooser(const AContext: TMcpToolContext; const AGate: TFunc<IMcpWorkspace, Boolean>):
  TMcpChooseFunc;
var
  mServer: TMcpServer;
  mWorkspace: IMcpWorkspace;
  mClient, mIde: TMcpAskFunc;
begin
  mServer := AContext.Server;
  mWorkspace := AContext.Workspace;
  mClient := ClientAsk(mServer);
  mIde := IdeAsk(TMcpIde.Create(AContext.Adapters.Process), AContext.Root);
  Result :=
    function(const AText: string; const AOptions: TArray<string>): Integer
    var
      mViaClient: TMcpAskFunc;
    begin
      if (mWorkspace = nil) or (Assigned(AGate) and not AGate(mWorkspace)) then
      begin
        Exit(TMcpConfirm.cNotAsked);
      end;
      mViaClient := nil;
      if mServer.ClientElicits and (mServer.Outgoing <> nil) then
      begin
        mViaClient := mClient;
      end;
      Result := TMcpConfirm.Choose(mViaClient, mIde,
        TMcpConfirm.Question(AText, AOptions, mWorkspace.Client));
    end;
end;

/// <summary>mcp.confirm erlaubt Rückfragen der schreibenden Werkzeuge.</summary>
function ConfirmAllowed: TFunc<IMcpWorkspace, Boolean>;
begin
  Result :=
    function(AWorkspace: IMcpWorkspace): Boolean
    begin
      Result := AWorkspace.Settings.McpConfirm;
    end;
end;

function ConfirmChooser(const AContext: TMcpToolContext): TMcpChooseFunc;
begin
  Result := HumanChooser(AContext, ConfirmAllowed());
end;

/// <summary>Zustimmung nach mcp.openProjects; liest die Einstellung bei jedem Aufruf.</summary>
function OpenConsent(const AWorkspace: IMcpWorkspace; const AChoose: TMcpChooseFunc): TMcpMayOpenFunc;
begin
  Result :=
    function(const AProjectFile: string; out AReason: string): Boolean
    var
      mPolicy: TMcpOpenProjects;
    begin
      mPolicy := TMcpOpenProjects.Ask;
      if AWorkspace <> nil then
      begin
        mPolicy := TMcpIdeBuilds.OpenPolicyOf(AWorkspace.Settings.McpOpenProjects);
      end;
      Result := TMcpIdeBuilds.MayOpen(mPolicy, AProjectFile, AChoose, AReason);
    end;
end;

/// <summary>Projektdateien unter ARoot, erst beim Aufruf gesucht.</summary>
function ProjectCandidates(const ARoot: string): TFunc<TArray<string>>;
begin
  Result :=
    function: TArray<string>
    begin
      Result := ProjectFilesUnder(ARoot);
    end;
end;

function IdeOpenOf(const AContext: TMcpToolContext): TMcpIdeOpen;
begin
  Result := Default(TMcpIdeOpen);
  Result.Candidates := ProjectCandidates(AContext.Root);
  Result.MayOpen := OpenConsent(AContext.Workspace, HumanChooser(AContext, nil));
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
