unit Atlas.IDE.CodeInsight.Composition.Navigation;

// Ergebnisfenster (#400), Editorbefehle (#399) mit ihren Haken, Auswirkungsanalyse (#1120), Testunit-Lens (#189),
// Aktionen und Werte im Tooltip (#621, #835, #909) und das Erzeugen-Menü (#719). Teil „Commands“; die Haken
// verbinden Features, die einander nicht importieren.

interface

/// <summary>Ergebnisfenster, Editorbefehle, Auswirkungsanalyse, Tooltip und Erzeugen-Menü anmelden.</summary>
procedure InstallNavigation;
/// <summary>Erzeugen-Menü, Haken von Lens und Tooltip, Editorbefehle, Auswirkungsanalyse und Ergebnisfenster
/// abmelden (umgekehrt zu InstallNavigation).</summary>
procedure UninstallNavigation;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Results.Impact,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Editor.TestUnitLens,
  Atlas.IDE.Hover.Editor,
  Atlas.IDE.Generate.Commands,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Problems.RuleActions,
  Atlas.IDE.CodeInsight.Composition.Session;

const
  /// <summary>Befehl des Moduls Analyse (#1455): Abhängigkeiten der Unit im Editor (#554, #593).</summary>
  cUnitDependenciesCommandId = 'Atlas.UnitDependencies';
  cRelatedTag = 'related:';
  /// <summary>Regel-Aktionen im Tooltip (TAtlasEditorHoverActions.TipProblemAction).</summary>
  cConfigureTag = 'rule.configure';
  cSuppressLineTag = 'rule.suppressLine';

procedure SwitchTestUnit;
begin
  TAtlasIdeEditorCommands.SwitchTestUnit;
end;

/// <summary>Unit-Zyklus (#896): Unit im Pfad springt an ihren uses-Eintrag.</summary>
procedure GoToRelated(const AProblem: TAtlasProblem; const ATag: string);
var
  mItem: Integer;
begin
  mItem := StrToIntDef(Copy(ATag, Length(cRelatedTag) + 1, MaxInt), -1);
  if (mItem >= 0) and (mItem <= High(AProblem.Related)) then
  begin
    TAtlasIdeNavigation.GoToLocation(TLspSession.UriToPath(AProblem.Related[mItem].Uri),
      AProblem.Related[mItem].Line, AProblem.Related[mItem].Character);
  end;
end;

/// <summary>Aktionen unter uses-Hinweisen (#621) und Regelbefunden (#909) im Tooltip: über die Code-Aktionen mit
/// Kennung; „Regel einstellen…“ und „Für diese Zeile unterdrücken“ übernimmt das Modul Prüfregeln (#1755),
/// „Graph zeigen“ zeigt die Unit-Beziehungen der Unit im Editor.</summary>
procedure ProblemAction(const AProblem: TAtlasProblem; const ATag: string);
begin
  if ATag = cConfigureTag then
  begin
    TAtlasRuleActions.Configure(AProblem.Code);
  end
  else if ATag = cSuppressLineTag then
  begin
    // Der Befund steht im oberen Editor: ohne Datei, kein Sprung.
    TAtlasRuleActions.Suppress(TAtlasRuleActions.Place('', AProblem));
  end
  else if StartsStr(cRelatedTag, ATag) then
  begin
    GoToRelated(AProblem, ATag);
  end
  else if ATag = 'cycle.showGraph' then
  begin
    RunModuleCommand(cUnitDependenciesCommandId);
  end
  else
  begin
    TAtlasIdeEditorCommands.ApplyTagged(TLspRange.Create(AProblem.StartLine, AProblem.StartCharacter,
      AProblem.EndLine, AProblem.EndCharacter), ATag);
  end;
end;

/// <summary>Werte im Tooltip (#835, #854): Beiträge der Module (IAtlasHoverValueSource, z. B. Darstellungen und
/// Visualisierer des Debuggers); '' ohne. Der Tooltip kennt die Module nicht (#1455).</summary>
function HoverValue(const AExpression: string; const ATypeChain: TArray<string>; const AText: string): string;
begin
  Result := TAtlasModuleContributions.HoverValue(AtlasModuleRegistry, AExpression, ATypeChain, AText);
end;

/// <summary>Nächster/vorheriger Befund (#509): alle Befunde der Datei aus dem Problemspeicher.</summary>
function ProblemsOf(const AFileName: string): TArray<TAtlasProblem>;
begin
  Result := nil;
  if TAtlasProblemsController.Current <> nil then
  begin
    Result := TAtlasProblemsController.Current.ForFile(AFileName);
  end;
end;

procedure UnitRelations;
begin
  RunModuleCommand(cUnitDependenciesCommandId);
end;

/// <summary>Schnellkorrektur „Signaturhilfe öffnen“ (#1007): nach dem Sprung der Parameter-Hint wie mit der Taste.
/// </summary>
procedure SignatureHelp;
begin
  if Manager <> nil then
  begin
    Manager.OpenSignature;
  end;
end;

/// <summary>///-Gerüst (#88): Tab springt durch die Beschreibungen, wie bei Code-Vorlagen.</summary>
procedure Placeholders(const AView: IOTAEditView; const ABefore: string; AOffset: Integer;
  const AExpansion: TAtlasSnippetExpansion);
begin
  if (Manager <> nil) and (Manager.Completion <> nil) then
  begin
    Manager.Completion.StartPlaceholders(AView, ABefore, AOffset, AExpansion);
  end;
end;

/// <summary>Haken der Editorbefehle zu Problemspeicher, Modulen und Vervollständigung.</summary>
procedure InstallEditorCommandHooks;
begin
  TAtlasIdeEditorCommands.OnProblemsOf := ProblemsOf;
  // „Graph zeigen“ als Code-Aktion an einem Unit-Zyklus (#896, atlas.showUnitRelations).
  TAtlasIdeEditorCommands.OnUnitRelations := UnitRelations;
  TAtlasIdeEditorCommands.OnSignatureHelp := SignatureHelp;
  TAtlasIdeEditorCommands.OnPlaceholders := Placeholders;
end;

function Snippets: TAtlasSnippetList;
begin
  Result := nil;
  if Manager <> nil then
  begin
    Result := Manager.Completion.Snippets;
  end;
end;

/// <summary>Erzeugen-Menü (#719): Vorlagen und ihr Einsetzen mit Platzhaltern kommen aus der Vervollständigung.
/// </summary>
procedure InstallGenerate;
begin
  TAtlasIdeGenerate.Install(ActiveSession, Warnings(), Snippets,
    procedure(AView: IOTAEditView; ASnippet: TAtlasSnippet)
    begin
      if Manager <> nil then
      begin
        Manager.Completion.InsertSnippet(AView, ASnippet);
      end;
    end,
    procedure(AAction: TLspCodeAction)
    begin
      TAtlasIdeEditorCommands.ApplyAction(AAction);
    end);
end;

procedure InstallNavigation;
begin
  TAtlasIdeResults.Install(ActiveSession, Warnings());
  TAtlasIdeEditorCommands.Install(ActiveSession, Warnings());
  // Auswirkungsanalyse (#1120): „Betroffene Tests ausführen“ über den Testläufer des Moduls Tests (#69, #1455).
  TAtlasIdeImpact.Install(RunTestsOfModule);
  // Klick auf die Testunit-Lens (#189); die Lens kennt die Editorbefehle nicht.
  TAtlasEditorTestUnitLens.OnSwitchTestUnit := SwitchTestUnit;
  TAtlasEditorHover.OnProblemAction := ProblemAction;
  TAtlasEditorHover.OnVisualize := HoverValue;
  InstallEditorCommandHooks;
  InstallGenerate;
end;

procedure UninstallNavigation;
begin
  TAtlasIdeGenerate.Uninstall;
  TAtlasEditorTestUnitLens.OnSwitchTestUnit := nil;
  TAtlasEditorHover.OnProblemAction := nil;
  TAtlasEditorHover.OnVisualize := nil;
  TAtlasIdeEditorCommands.Uninstall;
  TAtlasIdeImpact.Uninstall;
  TAtlasIdeResults.Uninstall;
end;

end.
