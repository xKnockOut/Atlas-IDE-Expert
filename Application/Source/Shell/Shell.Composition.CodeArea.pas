unit Shell.Composition.CodeArea;

// Teilwurzel Code der Komposition: Navigation, Refactorings, Vervollständigung, Code-Aktionen und Testunits. Sie
// bekommt den Kern, den Editor und die wenigen Dienste, die nur die Komposition kennt (Compilermeldungen,
// Projektkontext der IDE, Schnellbefehle, Meldungen an den Client).

interface

uses
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Editing.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Index.IdeProject,
  Lsp.Completion,
  Editing.Refactorings,
  Core.Workspace,
  Shell.Composition.Contract,
  Shell.Composition.Core,
  Shell.Composition.Editing,
  Shell.Composition.Navigation,
  Shell.Composition.Refactorings.Services,
  Shell.Composition.Refactorings,
  Shell.Composition.Completion,
  Shell.Composition.CodeActions,
  Shell.Composition.TestUnits,
  Atlas.Common.Semantics.Contract;

type
  /// <summary>Projektkontext der IDE zur Projektdatei AProjectFile (#396).</summary>
  TShellCodeIdeProjectFunc = reference to function(const AProjectFile: string;
    out AContext: TIdeProjectContext): Boolean;

  /// <summary>Was die Teilwurzel Code außer dem Kern von der Komposition braucht.</summary>
  TShellCodeAreaServices = record
    Logger: ILogger;
    Dispatcher: TJsonRpcDispatcher;
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    /// <summary>Gemeinsamer Index samt Ersatz-Units der IDE für Hover, Vervollständigung und Parameterhilfe.
    /// </summary>
    EditorIndex: ISymbolIndex;
    /// <summary>Editor: Host der Schnellbefehle und „Interface implementieren“ im Erzeugen-Menü.</summary>
    Editing: TShellEditing;
    RuleIdsFor: TSlashRuleIdsFunc;
    MessagesFor: TShellCompilerMessagesFunc;
    IdeProjectFor: TShellCodeIdeProjectFunc;
    /// <summary>Typen aus den Packages der IDE (atlas/ideTypes) für die Vervollständigung.</summary>
    IdeTypesFor: TShellCompletionIdeTypesFunc;
    VisitWorkspaces: TShellVisitWorkspacesProc;
    Notify: TCompletionNotifyProc;
    Log: TCompletionLogProc;
  end;

  /// <summary>Hält Navigation, Refactorings, Vervollständigung, Code-Aktionen und Testunits.</summary>
  TShellCodeArea = class
  private
    FCore: TShellCore;
    FServices: TShellCodeAreaServices;
    /// <summary>Testunit anlegen und wechseln (#274, #189).</summary>
    FTestUnits: TShellTestUnits;
    /// <summary>Navigation: Definition, Hover, Symbolsuche mit Lesezeichen, Hervorhebungen, verknüpftes
    /// Bearbeiten, Werte beim Debuggen, Compilerschalter, Referenzen und Umbenennen.</summary>
    FNavigation: TShellNavigation;
    FRefactorings: TShellRefactorings;
    /// <summary>Vervollständigung im Editor und in den Debug-Dialogen (#538).</summary>
    FCompletion: TShellCompletion;
    /// <summary>Code-Aktionen, Dokumentlinks und Farben.</summary>
    FCodeActions: TShellCodeActions;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function ProjectFiles: TArray<string>;
    function Namespaces: TArray<string>;
    function PickWorkspace(const AFileName: string): TCoreWorkspace;
    function RefactoringContextFor(const AUri: string): TRefactoringContext;
    function TestUnitServices: TShellTestUnitServices;
    function NavigationServices: TShellNavigationServices;
    function RefactoringServices: TShellRefactoringServices;
    function CompletionServices: TShellCompletionServices;
    function CodeActionServices: TShellCodeActionServices;
    /// <summary>Präfix der Namensvorschläge (#452): Vorgabe der Projektdatei .atlas, sonst die Zählung im
    /// Index.</summary>
    function NamingPrefixFor(const AUri: string; AKind: TNamingKind): string;
    /// <summary>Einstellungen und Projektdaten des Arbeitsbereichs von AUri für Code-Aktionen.</summary>
    function CodeActionWorkspaceOf(const AUri: string): TShellCodeActionWorkspace;
    /// <summary>Code-Aktionen der Testunits und der Refactorings auf ARange.</summary>
    function ExtraCodeActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
    /// <summary>Projekt des Arbeitsbereichs von AFileName für die Refactorings.</summary>
    function RefactoringProject(const AFileName: string; out AProject: TProjectInfo): Boolean;
    /// <summary>Was „Fehlende Unit hinzufügen“ über Projekt, Gruppe und Index wissen muss (#1247).</summary>
    function MissingUnitSetupFor(const AFileName, AUnitName: string; out ASetup: TMissingUnitSetup): Boolean;
    /// <summary>Die anderen Projekte der Gruppe; nur unter FCore.Workspaces.Lock.</summary>
    function GroupMembersOf(AWorkspace: TCoreWorkspace): TArray<TMissingUnitProject>;
    /// <summary>Datei der Unit AName laut Index; '' = unbekannt.</summary>
    function IndexUnitFile(AName: string): string;
  public
    /// <summary>Legt Testunits, Navigation, Refactorings, Vervollständigung und Code-Aktionen an und meldet sie an
    /// AServices.Dispatcher an; ACore und AServices.Editing müssen bestehen.</summary>
    constructor Create(ACore: TShellCore; const AServices: TShellCodeAreaServices);
    /// <summary>Gibt die Teile frei.</summary>
    destructor Destroy; override;
    /// <summary>uses-Kontext von AUri aus den Code-Aktionen.</summary>
    function UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
    property TestUnits: TShellTestUnits read FTestUnits;
    property Navigation: TShellNavigation read FNavigation;
    property Refactorings: TShellRefactorings read FRefactorings;
    property Completion: TShellCompletion read FCompletion;
    property CodeActions: TShellCodeActions read FCodeActions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Rules.CheckContext,
  Lsp.Completion.Names,
  Rules.Engine,
  Rules.Builtin.DeadCode,
  Atlas.Common.Pascal.UsesGroups,
  Shell.Composition.Workspaces,
  Core.Workspace.Jobs;

/// <summary>Fundort einer Unit-Datei aus Sicht von AUri (#2794): eigenes Projekt samt Suchpfad, ein anderes
/// Projekt der Gruppe, die Delphi-Installation oder sonst der Bibliothekspfad.</summary>
function UsesUnitFileFunc(AWorkspaces: TShellWorkspaceRegistry): TShellUsesUnitFileFunc;
begin
  Result :=
    function(const AUri, AFileName: string): TUsesUnitFile
    var
      mOwn, mOther: TCoreWorkspace;
      mInstallPath: string;
    begin
      Result := Default(TUsesUnitFile);
      System.TMonitor.Enter(AWorkspaces.Lock);
      try
        mOwn := AWorkspaces.Pick(TDocumentUris.ToPath(AUri));
        if (mOwn = nil) or (AFileName = '') then
        begin
          Exit;
        end;
        // Die Installation zuerst: Viele Projekte haben $(BDS)\source\rtl\... im Suchpfad, dann gehörten
        // System.Classes & Co. sonst zum eigenen Projekt oder (über ein anderes Projekt) zu den Packages.
        if TUsesGroups.InstallPathOf(AFileName, mOwn.State.BdsRoot, mInstallPath) then
        begin
          Result.Origin := TUsesFileOrigin.Installation;
          Result.InstallPath := mInstallPath;
          Exit;
        end;
        if mOwn.State.ContainsFile(AFileName) then
        begin
          Result.Origin := TUsesFileOrigin.OwnProject;
          Exit;
        end;
        for mOther in AWorkspaces.Items do
        begin
          if (mOther <> mOwn) and mOther.State.ContainsFile(AFileName) then
          begin
            Result.Origin := TUsesFileOrigin.ProjectGroup;
            Exit;
          end;
        end;
        Result.Origin := TUsesFileOrigin.LibraryPath;
      finally
        System.TMonitor.Exit(AWorkspaces.Lock);
      end;
    end;
end;

{ TShellCodeArea }

constructor TShellCodeArea.Create(ACore: TShellCore; const AServices: TShellCodeAreaServices);
begin
  inherited Create;
  FCore := ACore;
  FServices := AServices;
  FTestUnits := TShellTestUnits.Create(TestUnitServices);
  FNavigation := TShellNavigation.Create(NavigationServices);
  FNavigation.Attach(FServices.Dispatcher);
  FRefactorings := TShellRefactorings.Create(RefactoringServices);
  FCompletion := TShellCompletion.Create(CompletionServices);
  FCompletion.Attach(FServices.Dispatcher);
  // „Interface implementieren“ im Erzeugen-Menü (#719, #466) wie in der Vervollständigung.
  FServices.Editing.UseCompletion(FCompletion.Completion);
  FCodeActions := TShellCodeActions.Create(CodeActionServices);
  FCodeActions.Attach(FServices.Dispatcher);
end;

destructor TShellCodeArea.Destroy;
begin
  FreeAndNil(FCompletion);
  FreeAndNil(FRefactorings);
  FreeAndNil(FNavigation);
  FreeAndNil(FCodeActions);
  FreeAndNil(FTestUnits);
  inherited;
end;

function TShellCodeArea.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FCore.ReadText(AFileName, AText);
end;

function TShellCodeArea.ProjectFiles: TArray<string>;
begin
  Result := FCore.ProjectFiles;
end;

function TShellCodeArea.Namespaces: TArray<string>;
begin
  Result := FNavigation.Namespaces;
end;

function TShellCodeArea.PickWorkspace(const AFileName: string): TCoreWorkspace;
begin
  Result := FCore.Workspaces.Pick(AFileName);
end;

function TShellCodeArea.RefactoringContextFor(const AUri: string): TRefactoringContext;
begin
  Result := FRefactorings.ContextFor(AUri);
end;

function TShellCodeArea.TestUnitServices: TShellTestUnitServices;
begin
  Result := Default(TShellTestUnitServices);
  Result.Logger := FServices.Logger;
  Result.Documents := FServices.Documents;
  Result.Index := FServices.Index;
  Result.ReadText := ReadText;
  Result.VisitWorkspaces := FServices.VisitWorkspaces;
  Result.PickWorkspace := PickWorkspace;
end;

function TShellCodeArea.NavigationServices: TShellNavigationServices;
var
  mCore: TShellCore;
begin
  mCore := FCore;
  Result := Default(TShellNavigationServices);
  Result.Documents := FServices.Documents;
  Result.Index := FServices.Index;
  Result.EditorIndex := FServices.EditorIndex;
  Result.ReadText := ReadText;
  Result.ProjectFiles := ProjectFiles;
  Result.EnsureUnit := mCore.Folders.EnsureUnitFunc();
  Result.DelphiVersionFor :=
    function(const AUri: string): string
    begin
      Result := mCore.FileOptions.DelphiVersionFor(AUri);
    end;
  Result.HintSettingsFor :=
    function(const AUri: string): THintSettings
    begin
      Result := mCore.Settings.Hints(AUri);
    end;
  Result.RationaleOptionsFor := mCore.Sources.RationaleOptions();
  Result.ConditionalContextFor := mCore.Directives.ConditionalContext();
  Result.HighlightSettingsFor :=
    function(const AUri: string): THighlightSettings
    begin
      Result := mCore.Settings.Highlight(AUri);
    end;
  Result.CompilerSwitchContextFor := mCore.Directives.CompilerSwitchContext();
  Result.ReferenceSettingsFor :=
    function(const AUri: string): TReferenceSettings
    begin
      Result := mCore.Settings.References(AUri);
    end;
  Result.RenameTypeCommentsFor :=
    function(const AUri: string): Boolean
    begin
      Result := not SameText(mCore.Settings.SettingsFor(AUri).ClassCompletion.TypeComment, 'off');
    end;
end;

function TShellCodeArea.RefactoringServices: TShellRefactoringServices;
var
  mCore: TShellCore;
begin
  mCore := FCore;
  Result := Default(TShellRefactoringServices);
  Result.Logger := FServices.Logger;
  Result.Documents := FServices.Documents;
  Result.Index := FServices.Index;
  Result.EnsureUnit := mCore.Folders.EnsureUnitFunc();
  Result.Namespaces := Namespaces;
  Result.ProjectFiles := ProjectFiles;
  Result.ReadText := ReadText;
  Result.SettingsFor :=
    function(const AUri: string): TRefactoringSettings
    begin
      Result := mCore.Settings.Refactoring(AUri);
    end;
  Result.FormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := mCore.FileOptions.ResolvedFormatStyleFor(AUri);
    end;
  Result.TypeCommentFor :=
    function(const AUri: string): string
    begin
      Result := mCore.Settings.SettingsFor(AUri).ClassCompletion.TypeComment;
    end;
  Result.LanguageLevelFor :=
    function(const AUri: string): string
    begin
      Result := mCore.FileOptions.LanguageLevelFor(AUri);
    end;
  Result.DelphiVersionFor :=
    function(const AUri: string): string
    begin
      Result := mCore.FileOptions.DelphiVersionFor(AUri);
    end;
  // Die Code-Aktionen entstehen erst nach den Refactorings: UsesContextFor liest sie beim Aufruf.
  Result.UsesContextFor := UsesContextFor;
  Result.MessagesFor := FServices.MessagesFor;
  Result.ProjectFor := RefactoringProject;
  Result.NewNamesFor :=
    function(const AUri: string): TPascalNamePrefixes
    begin
      Result := mCore.FileOptions.NewNamesFor(AUri);
    end;
  Result.MissingUnitSetupFor := MissingUnitSetupFor;
end;

function TShellCodeArea.CompletionServices: TShellCompletionServices;
var
  mCore: TShellCore;
begin
  mCore := FCore;
  Result := Default(TShellCompletionServices);
  Result.Documents := FServices.Documents;
  // Mit den Ersatz-Units der IDE: Mitglieder von Typen aus Packages ohne Quelltext.
  Result.Index := FServices.EditorIndex;
  Result.EnsureUnit := mCore.Folders.EnsureUnitFunc();
  Result.ReadText := ReadText;
  Result.CompletionSettingsFor :=
    function(const AUri: string): TCompletionSettings
    begin
      Result := mCore.Settings.Completion(AUri);
    end;
  Result.RefactoringSettingsFor :=
    function(const AUri: string): TRefactoringSettings
    begin
      Result := mCore.Settings.Refactoring(AUri);
    end;
  Result.LanguageLevelFor :=
    function(const AUri: string): string
    begin
      Result := mCore.FileOptions.LanguageLevelFor(AUri);
    end;
  Result.RefactoringContextFor := RefactoringContextFor;
  Result.SlashCommandsFor := mCore.FileOptions.SlashCommands();
  Result.RuleIdsFor := FServices.RuleIdsFor;
  Result.NamingFor := NamingPrefixFor;
  Result.IdeTypesFor := FServices.IdeTypesFor;
  Result.HintsFor :=
    function(const AUri: string): THintSettings
    begin
      Result := mCore.Settings.Hints(AUri);
    end;
  Result.DocCommentsFor :=
    function(const AUri: string): Boolean
    begin
      Result := mCore.FileOptions.DocCommentsFor(AUri);
    end;
  Result.SymbolsFor := mCore.Directives.ConditionalContext();
  Result.Notify := FServices.Notify;
  Result.Log := FServices.Log;
end;

function TShellCodeArea.CodeActionServices: TShellCodeActionServices;
var
  mCore: TShellCore;
begin
  mCore := FCore;
  Result := Default(TShellCodeActionServices);
  Result.Documents := FServices.Documents;
  Result.Index := FServices.Index;
  Result.EnsureUnit := mCore.Folders.EnsureUnitFunc();
  Result.RuleContextFor :=
    function(const AUri: string; out AContext: TRuleCheckContext): Boolean
    begin
      Result := mCore.RuleContext.RuleContextFor(AUri, AContext);
    end;
  Result.StringLiteralFor :=
    function(const AUri: string; out AMultiline: Boolean): TStringLiteralSettings
    begin
      Result := mCore.Settings.StringLiteral(AUri, AMultiline);
    end;
  Result.DocCommentsFor :=
    function(const AUri: string): Boolean
    begin
      Result := mCore.FileOptions.DocCommentsFor(AUri);
    end;
  Result.FormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := mCore.FileOptions.ResolvedFormatStyleFor(AUri);
    end;
  Result.RefactoringFor :=
    function(const AUri: string): TRefactoringSettings
    begin
      Result := mCore.Settings.Refactoring(AUri);
    end;
  Result.DefinesFor := mCore.Directives.Defines();
  Result.ExtraActions := ExtraCodeActions;
  Result.LanguageLevelFor :=
    function(const AUri: string): string
    begin
      Result := mCore.FileOptions.LanguageLevelFor(AUri);
    end;
  Result.WorkspaceOf := CodeActionWorkspaceOf;
  Result.UnitFileOf := UsesUnitFileFunc(FCore.Workspaces);
  Result.SlashHost := FServices.Editing.SlashHost;
end;

function TShellCodeArea.NamingPrefixFor(const AUri: string; AKind: TNamingKind): string;
var
  mWorkspace: TCoreWorkspace;
  mProject: TProjectInfo;
  mContext: TIdeProjectContext;
begin
  mWorkspace := FCore.Workspaces.WorkspaceOf(TDocumentUris.ToPath(AUri));
  if (mWorkspace <> nil) and mWorkspace.State.Project(mProject) and
    FServices.IdeProjectFor(mProject.FileName, mContext) and mContext.HasNaming[AKind] then
  begin
    Exit(mContext.Naming[AKind]);
  end;
  Result := TCompletionNames.NamingPrefix(FServices.Index, AKind);
end;

function TShellCodeArea.CodeActionWorkspaceOf(const AUri: string): TShellCodeActionWorkspace;
var
  mWorkspace: TCoreWorkspace;
begin
  Result := Default(TShellCodeActionWorkspace);
  Result.MemberOrder := TMemberOrderSettings.Default;
  System.TMonitor.Enter(FCore.Workspaces.Lock);
  try
    mWorkspace := FCore.Workspaces.Pick(TDocumentUris.ToPath(AUri));
    if mWorkspace <> nil then
    begin
      Result.Found := True;
      Result.MemberOrder := mWorkspace.Configuration.Settings.MemberOrder;
      Result.SortUses := mWorkspace.Configuration.Settings.SortUses;
      Result.SortUsesByNamespace := mWorkspace.Configuration.Settings.SortUsesByNamespace;
      Result.SortUsesByOrigin := mWorkspace.Configuration.Settings.SortUsesByOrigin;
      Result.UsesGroupStyle := TUsesGroups.StyleOf(mWorkspace.Configuration.Settings.UsesGroupStyle);
      Result.MaxLineLength := mWorkspace.Configuration.Settings.Formatting.MaxLineLength;
      // usesKeep und die Option keep von unused-uses (#1135): Regel, Abblenden und „uses aufräumen“ gleich.
      Result.UsesKeep := TUnusedUsesRule.Keep(TRuleEngine.RuleOptions(cUnusedUsesRuleId,
        mWorkspace.Configuration.Settings), mWorkspace.Configuration.Settings.UsesKeep);
      Result.Namespaces := mWorkspace.State.Namespaces;
      Result.IncludePaths := mWorkspace.State.IncludePaths;
    end;
  finally
    System.TMonitor.Exit(FCore.Workspaces.Lock);
  end;
end;

function TShellCodeArea.ExtraCodeActions(const AUri: string; const ARange: TTextRange): TArray<TJSONObject>;
begin
  Result := FTestUnits.Actions(AUri, ARange.StartPos.Line);
  Result := Result + FRefactorings.Actions(AUri, ARange);
end;

function TShellCodeArea.RefactoringProject(const AFileName: string; out AProject: TProjectInfo): Boolean;
var
  mWorkspace: TCoreWorkspace;
begin
  AProject := Default(TProjectInfo);
  System.TMonitor.Enter(FCore.Workspaces.Lock);
  try
    mWorkspace := FCore.Workspaces.Pick(AFileName);
    Result := (mWorkspace <> nil) and mWorkspace.State.Project(AProject);
  finally
    System.TMonitor.Exit(FCore.Workspaces.Lock);
  end;
end;

function TShellCodeArea.MissingUnitSetupFor(const AFileName, AUnitName: string;
  out ASetup: TMissingUnitSetup): Boolean;
var
  mWorkspace: TCoreWorkspace;
  mGroup: TArray<TMissingUnitProject>;
  mProject: TProjectInfo;
begin
  ASetup := Default(TMissingUnitSetup);
  // Arbeitsbereich festhalten, die .dproj-Dateien aber außerhalb von FCore.Workspaces.Lock lesen (#647).
  System.TMonitor.Enter(FCore.Workspaces.Lock);
  try
    mWorkspace := FCore.Workspaces.Pick(AFileName);
    if mWorkspace = nil then
    begin
      Exit(False);
    end;
    mGroup := GroupMembersOf(mWorkspace);
    FCore.Workspaces.Hold(TArray<TCoreWorkspace>.Create(mWorkspace));
  finally
    System.TMonitor.Exit(FCore.Workspaces.Lock);
  end;
  try
    Result := mWorkspace.State.Project(mProject);
    if Result then
    begin
      ASetup := TCoreWorkspaceJobs.MissingUnitSetupOf(mProject, mWorkspace.State.Install,
        mWorkspace.Setup.Factories);
    end;
  finally
    FCore.Workspaces.Release(TArray<TCoreWorkspace>.Create(mWorkspace));
  end;
  if not Result then
  begin
    Exit;
  end;
  ASetup.UnitName := AUnitName;
  ASetup.GroupProjects := mGroup;
  // Nur der Index: nichts nachladen, die Suche läuft bei jeder Code-Aktion auf der Zeile.
  ASetup.IndexFile := IndexUnitFile;
end;

function TShellCodeArea.GroupMembersOf(AWorkspace: TCoreWorkspace): TArray<TMissingUnitProject>;
var
  mOther: TCoreWorkspace;
  mMember: TMissingUnitProject;
  mOtherProject: TProjectInfo;
begin
  Result := nil;
  for mOther in FCore.Workspaces.Items do
  begin
    if (mOther <> AWorkspace) and mOther.State.Project(mOtherProject) and
      not SameFileName(mOtherProject.FileName, AWorkspace.State.ProjectFileName) then
    begin
      mMember := Default(TMissingUnitProject);
      mMember.FileName := mOtherProject.FileName;
      mMember.SearchPaths := mOtherProject.SearchPaths;
      Result := Result + [mMember];
    end;
  end;
end;

function TShellCodeArea.IndexUnitFile(AName: string): string;
var
  mUnit: TUnitIndex;
begin
  Result := '';
  if FServices.Index.FindUnit(AName, mUnit) then
  begin
    Result := mUnit.FileName;
  end;
end;

function TShellCodeArea.UsesContextFor(const AUri: string; out AContext: TUsesContext): Boolean;
begin
  AContext := Default(TUsesContext);
  // Die Code-Aktionen entstehen zuletzt: Bis dahin gibt es keinen uses-Kontext.
  Result := (FCodeActions <> nil) and FCodeActions.UsesContextOf(AUri, AContext);
end;

end.
