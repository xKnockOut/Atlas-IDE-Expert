unit Shell.Workspace.RuleProjects;

// Internals-Rolle Shell: Projektkontext einer Datei für die Prüfregeln (#926, #943, #956, #1055, #1112), aus
// einem oder mehreren geladenen Projekten, und die Dienste eines Arbeitsbereichs für die Prüfregeln (#1112).

interface

uses
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.ProjectFiles,
  Shell.Workspace.Setup,
  Shell.Workspace.State;

type
  TShellRuleProjects = class
  public
    /// <summary>Anwendungsart, Projektname und automatisch erzeugte Formulare für AFileName aus AProject
    /// (#926, #943, #956, #1055); sonst nur der Dateiname. Liest die .dpr über AReadText.</summary>
    class function RuleProjectOf(const AProject: TProjectInfo; const AFileName: string;
      const AReadText: TRuleProjectReadText): TCheckProject; overload; static;
    /// <summary>RuleProjectOf über alle Projekte, die AFileName enthalten (#1112), das bevorzugte zuerst;
    /// zusammengeführt mit MergeRuleProjects.</summary>
    class function RuleProjectOf(const AProjects: TArray<TProjectInfo>; const AFileName: string;
      const AReadText: TRuleProjectReadText): TCheckProject; overload; static;
    /// <summary>Projektkontext einer Datei aus mehreren Projekten (#1112): Das erste Projekt, das die Datei
    /// enthält, liefert Name, Formulare und .dpr. Widersprechen sich die Anwendungsarten (eine Unit im
    /// Konsolen-Testprogramm und im IDE-Package), bleibt die Art Unknown: Art-abhängige Regeln dürfen nicht
    /// für ein Projekt melden, was im anderen richtig ist.</summary>
    class function MergeRuleProjects(const AProjects: TArray<TCheckProject>;
      const AFileName: string): TCheckProject; static;
    /// <summary>Gehört AFileName zu AProject (Hauptquelltext oder Unit)?</summary>
    class function IsMember(const AProject: TProjectInfo; const AFileName: string): Boolean; static;
    /// <summary>Wert von DCC_ConsoleTarget; '' ohne Angabe.</summary>
    class function ConsoleTargetOf(const AProject: TProjectInfo): string; static;
    /// <summary>Warnungen der .dproj (DCC_SYMBOL_PLATFORM, DCC_UNSAFE_CODE …) für die Regeln der Gruppe Compiler
    /// vorab (#1378).</summary>
    class function ProjectWarningsOf(const AProject: TProjectInfo): TArray<string>; static;
    /// <summary>Dienste des Projekts für die Prüfregeln (#1112): Symbolindex, Nachladen von Units über AEnsureUnit,
    /// Namespaces, Unit-Suche, Packages und die Namenskonvention aus dem Projektkontext der IDE. Ein Weg für
    /// LSP-Server, MCP und Linter; projektweite Dienste (ProjectFiles, Nachladen über alle Arbeitsbereiche)
    /// ergänzt, wer mehrere Arbeitsbereiche hält. Threadsicher.</summary>
    class function ServicesOf(AState: TShellProjectState; ASetup: TShellWorkspaceSetup; const AIndex: ISymbolIndex;
      const AEnsureUnit: TEnsureUnitFunc): TRuleServices; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Rules.WarnSwitches,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Builtin.FormFields,
  Shell.Workspace.Packages;

class function TShellRuleProjects.IsMember(const AProject: TProjectInfo; const AFileName: string): Boolean;
var
  mUnit: TProjectUnit;
begin
  Result := SameText(AProject.MainSource, AFileName);
  for mUnit in AProject.Units do
  begin
    Result := Result or SameText(mUnit.FileName, AFileName);
  end;
end;

class function TShellRuleProjects.ConsoleTargetOf(const AProject: TProjectInfo): string;
var
  mPair: TPair<string, string>;
begin
  Result := '';
  for mPair in AProject.Properties do
  begin
    if SameText(mPair.Key, 'DCC_ConsoleTarget') then
    begin
      Result := mPair.Value;
    end;
  end;
end;

class function TShellRuleProjects.RuleProjectOf(const AProject: TProjectInfo; const AFileName: string;
  const AReadText: TRuleProjectReadText): TCheckProject;
var
  mMainText: string;
begin
  Result := Default(TCheckProject);
  Result.FileName := AFileName;
  // Anwendungsart für writeln-in-gui-app (#926) und queue-nil-in-package (#943), nur für Dateien des Projekts.
  if (AProject.MainSource = '') or not IsMember(AProject, AFileName) or
    not AReadText(AProject.MainSource, mMainText) then
  begin
    Exit;
  end;
  Result.Application := TWritelnInGuiAppRule.ApplicationKind(ConsoleTargetOf(AProject), mMainText);
  Result.Name := ChangeFileExt(ExtractFileName(AProject.MainSource), '');
  // Reihenfolge von Application.CreateForm für form-access-before-create (#956).
  Result.AutoCreateForms := TFormAccessBeforeCreateRule.AutoCreatedForms(mMainText);
  // .dpr für die Korrektur von form-autocreate-and-manual (#1055).
  Result.ProjectMainSource := AProject.MainSource;
end;

class function TShellRuleProjects.RuleProjectOf(const AProjects: TArray<TProjectInfo>; const AFileName: string;
  const AReadText: TRuleProjectReadText): TCheckProject;
var
  mProjects: TArray<TCheckProject>;
  mProject: TProjectInfo;
begin
  mProjects := nil;
  for mProject in AProjects do
  begin
    mProjects := mProjects + [RuleProjectOf(mProject, AFileName, AReadText)];
  end;
  Result := MergeRuleProjects(mProjects, AFileName);
end;

class function TShellRuleProjects.MergeRuleProjects(const AProjects: TArray<TCheckProject>;
  const AFileName: string): TCheckProject;
var
  mProject: TCheckProject;
  mFound: Boolean;
begin
  Result := Default(TCheckProject);
  Result.FileName := AFileName;
  mFound := False;
  for mProject in AProjects do
  begin
    // Ohne .dpr gehört die Datei nicht zu diesem Projekt (RuleProjectOf).
    if mProject.ProjectMainSource = '' then
    begin
      Continue;
    end;
    if not mFound then
    begin
      Result := mProject;
      Result.FileName := AFileName;
      mFound := True;
    end
    else if mProject.Application <> Result.Application then
    begin
      Result.Application := TRuleApplicationKind.Unknown;
    end;
  end;
end;

class function TShellRuleProjects.ProjectWarningsOf(const AProject: TProjectInfo): TArray<string>;
var
  mPair: TPair<string, string>;
  mEntry: string;
begin
  Result := nil;
  for mPair in AProject.Properties do
  begin
    mEntry := TRuleWarnSwitches.ProjectEntry(mPair.Key, mPair.Value);
    if mEntry <> '' then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

class function TShellRuleProjects.ServicesOf(AState: TShellProjectState; ASetup: TShellWorkspaceSetup;
  const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc): TRuleServices;
var
  mHold: IPackageLocatorHold;
  mContext: TIdeProjectContext;
  mInfo: TProjectInfo;
begin
  Result := Default(TRuleServices);
  Result.Index := AIndex;
  Result.EnsureUnit := AEnsureUnit;
  Result.Namespaces := AState.Namespaces;
  // Unit-Suche wie beim Compiler für uses-unit-not-found (#1016).
  Result.Units := AState.UnitLookup;
  // Antworten zum Index (z. B. "Property Count ohne write?") über alle Units, statt je Unit neu.
  Result.NameFacts := AState.NameFacts;
  // requires-Packages für implicit-package-import (#46); der Halter hält den Locator, solange die Prüfung ihn
  // braucht, auch über einen Projektwechsel hinaus (#1220).
  mHold := AState.Packages;
  if mHold <> nil then
  begin
    Result.PackageProvides := TShellPackageLookups.Provides(mHold);
    Result.PackageRequires := TShellPackageLookups.RuleRequires(mHold);
  end;
  // Präfixe der Projektdatei .atlas für naming-prefix und die Korrektur von shadowed-name (#1111).
  if ASetup.IdeContext(AState.ProjectFileName, mContext) then
  begin
    Result.Naming := mContext.RuleNaming;
  end;
  if AState.Project(mInfo) then
  begin
    Result.ProjectWarnings := ProjectWarningsOf(mInfo);
  end;
end;

end.
