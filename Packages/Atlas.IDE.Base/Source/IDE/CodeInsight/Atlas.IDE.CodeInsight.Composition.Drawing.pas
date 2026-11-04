unit Atlas.IDE.CodeInsight.Composition.Drawing;

// Was Atlas in den Editor zeichnet: farbige Klammerpaare (#514), gezeichnete Elemente und Ausblenden am Element
// (#628), Rinne mit Rekursionssymbolen (#623) und den Schichten der Module, Atlas-Spalte (#768), gleicher Text wie
// die Markierung (#709), Austrittspunkte (#698), neu zugewiesene Variablen (#712) und das Fenster „Atlas-Prüfung“
// (#909).

interface

uses
  System.Types;

procedure StartPairs;
procedure StopPairs;
function PairsStarted: Boolean;
/// <summary>Gezeichnete Elemente und Ausblenden am Element (#628); „Einstellungen dazu …“ öffnet die
/// Optionsseite.</summary>
procedure StartHide;
procedure StopHide;
function HideStarted: Boolean;
/// <summary>Einstellung AKey am Punkt APoint ausblenden (Kontextmenü #628); False, solange Hide nicht läuft.</summary>
function HideSetting(const AKey: string; APoint: TPoint): Boolean;
/// <summary>Fenster „Atlas-Prüfung“ (#909): Code-Aktionen, Optionsseite, Serverbefehle und Meldungen über Haken;
/// F8/Umschalt+F8 gehen bei sichtbarem Fenster durch dessen Liste.</summary>
procedure StartProblemsWindow;
procedure StopProblemsWindow;
function ProblemsWindowStarted: Boolean;
procedure StartGutterMarks;
procedure StopGutterMarks;
function GutterMarksStarted: Boolean;
procedure StartGutterColumn;
procedure StopGutterColumn;
function GutterColumnStarted: Boolean;
procedure StartSelectionMatches;
procedure StopSelectionMatches;
function SelectionMatchesStarted: Boolean;
procedure StartExitPoints;
procedure StopExitPoints;
procedure StartReassigned;
procedure StopReassigned;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Editor.Pairs,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Editor.Hide,
  Atlas.IDE.Editor.RecursionGutter,
  Atlas.IDE.Editor.GutterColumn,
  Atlas.IDE.Editor.SelectionMatches,
  Atlas.IDE.Editor.ExitPoints,
  Atlas.IDE.Editor.Reassigned,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.CodeInsight.Composition.Session;

var
  Pairs: TAtlasEditorPairs;
  // Markierungen in der Rinne: Rekursionssymbole (#623) und die Schichten der Module (#545, #622).
  GutterMarks: TAtlasIdeGutterMarks;
  // Atlas-Spalte in der Zeilenleiste (#768).
  GutterColumn: TAtlasIdeGutterColumn;
  // Gleichen Text wie die Markierung hervorheben (#709).
  SelectionMatches: TAtlasIdeSelectionMatches;
  ProblemsWindowRunning: Boolean;
  HideRunning: Boolean;

procedure StartPairs;
begin
  Pairs := TAtlasEditorPairs.Create;
end;

procedure StopPairs;
begin
  FreeAndNil(Pairs);
end;

function PairsStarted: Boolean;
begin
  Result := Pairs <> nil;
end;

/// <summary>Einstellung AKey auf der Optionsseite zeigen.</summary>
procedure ShowSetting(AKey: string);
var
  mKey: string;
begin
  mKey := AKey;
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasOptionsRegistration.ShowSetting(mKey);
    end);
end;

/// <summary>Regel ARule auf der Optionsseite zeigen.</summary>
procedure ShowRule(ARule: string);
var
  mRule: string;
begin
  mRule := ARule;
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasOptionsRegistration.ShowRule(mRule);
    end);
end;

procedure StartHide;
begin
  TAtlasIdeElements.Start;
  TAtlasIdeHide.Start;
  TAtlasIdeHide.OnShowSetting := ShowSetting;
  HideRunning := True;
end;

procedure StopHide;
begin
  TAtlasIdeHide.OnShowSetting := nil;
  TAtlasIdeHide.Stop;
  TAtlasIdeElements.Stop;
  HideRunning := False;
end;

function HideStarted: Boolean;
begin
  Result := HideRunning;
end;

function HideSetting(const AKey: string; APoint: TPoint): Boolean;
begin
  Result := HideRunning and TAtlasIdeHide.HideSetting(AKey, APoint);
end;

/// <summary>Code-Aktion mit Kennung ATag am Befund AProblem.</summary>
procedure ApplyTagged(AProblem: TAtlasProblem; ATag: string);
begin
  TAtlasIdeEditorCommands.ApplyTagged(TLspRange.Create(AProblem.StartLine, AProblem.StartCharacter,
    AProblem.EndLine, AProblem.EndCharacter), ATag);
end;

/// <summary>„Für diesen Befund ein Issue anlegen …“ (#1268): über IAtlasIssueCreation des Moduls Tracker.</summary>
procedure CreateIssue(AFindings: TArray<TAtlasFinding>);
var
  mItems: TArray<TAtlasIssueFinding>;
begin
  mItems := IssueFindings(AFindings);
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      CreateIssueFromFindings(mItems);
    end);
end;

function StepWindow(AForward: Boolean): Boolean;
begin
  Result := TAtlasIdeProblems.StepWindow(AForward);
end;

procedure StartProblemsWindow;
var
  mHooks: TAtlasIdeProblemsHooks;
begin
  mHooks.ApplyTagged := ApplyTagged;
  mHooks.ConfigureRule := ShowRule;
  mHooks.Command :=
    procedure(const ACommand, AArgumentsJson: string; const ADone: TProc<TJSONValue>)
    begin
      // Im Hintergrund (#874).
      RunServerCommand(ACommand, AArgumentsJson, 10000, ADone);
    end;
  mHooks.Message := MessageLines();
  mHooks.Indexing := ServerIndexing;
  mHooks.CreateIssue := CreateIssue;
  mHooks.CanCreateIssue := CanCreateIssue;
  TAtlasIdeProblems.Start(mHooks);
  TAtlasIdeEditorCommands.OnStepList := StepWindow;
  ProblemsWindowRunning := True;
end;

procedure StopProblemsWindow;
begin
  TAtlasIdeEditorCommands.OnStepList := nil;
  TAtlasIdeProblems.Release;
  ProblemsWindowRunning := False;
end;

function ProblemsWindowStarted: Boolean;
begin
  Result := ProblemsWindowRunning;
end;

procedure StartGutterMarks;
begin
  GutterMarks := TAtlasIdeGutterMarks.Create;
  // Rekursionssymbole (#623); fragt den Server nur, wenn er ohnehin läuft.
  GutterMarks.Add(TAtlasIdeRecursionGutter.Create(RunningSession));
end;

procedure StopGutterMarks;
begin
  FreeAndNil(GutterMarks);
end;

function GutterMarksStarted: Boolean;
begin
  Result := GutterMarks <> nil;
end;

procedure OpenCodeActions;
begin
  TAtlasIdeEditorCommands.CodeActions;
end;

procedure StartGutterColumn;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  GutterColumn := TAtlasIdeGutterColumn.Create(RunningSession, OpenCodeActions,
    procedure(const AAction: TLspCodeAction)
    begin
      TAtlasIdeEditorCommands.ApplyAction(AAction);
    end);
end;

procedure StopGutterColumn;
begin
  FreeAndNil(GutterColumn);
end;

function GutterColumnStarted: Boolean;
begin
  Result := GutterColumn <> nil;
end;

procedure StartSelectionMatches;
begin
  SelectionMatches := TAtlasIdeSelectionMatches.Create;
end;

procedure StopSelectionMatches;
begin
  FreeAndNil(SelectionMatches);
end;

function SelectionMatchesStarted: Boolean;
begin
  Result := SelectionMatches <> nil;
end;

procedure StartExitPoints;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeExitPoints.Install(RunningSession);
end;

procedure StopExitPoints;
begin
  TAtlasIdeExitPoints.Uninstall;
end;

procedure StartReassigned;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeReassigned.Install(RunningSession);
end;

procedure StopReassigned;
begin
  TAtlasIdeReassigned.Uninstall;
end;

end.
