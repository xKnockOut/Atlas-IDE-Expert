unit Shell.Composition.CodeActions;

// Internals-Rolle Shell: Code-Aktionen (#122, #182, #621), Dokumentlinks auf Include-Dateien und Farben im
// Editor. uses nach Herkunft gliedern (#2794): Die Gruppe einer Unit folgt aus ihrer Datei im Index und deren
// Fundort, den die Komposition kennt (UnitFileOf). Die Komposition reicht Dokumente, Index, Prüfkontext, Einstellungen je Datei und die Lage des
// Arbeitsbereichs als Dienste herein; die Code-Aktionen entstehen hier.

interface

uses
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Pascal.UsesGroups,
  Atlas.Common.Pascal.UsesEdits,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Lsp.SyntaxDiagnostics,
  Atlas.Common.Rules.CheckContext,
  Atlas.Common.Lsp.CodeActions,
  Atlas.Common.Lsp.DocumentLinks,
  Atlas.Common.Lsp.Colors;

type
  /// <summary>Was die Code-Aktionen vom Arbeitsbereich einer Datei brauchen; Found False ohne Arbeitsbereich.
  /// </summary>
  TShellCodeActionWorkspace = record
    Found: Boolean;
    MemberOrder: TMemberOrderSettings;
    SortUses: Boolean;
    SortUsesByNamespace: Boolean;
    SortUsesByOrigin: Boolean;
    UsesGroupStyle: TUsesGroupStyle;
    /// <summary>format.maxLineLength; 0 = Vorgabe.</summary>
    MaxLineLength: Integer;
    UsesKeep: TArray<string>;
    Namespaces: TArray<string>;
    IncludePaths: TArray<string>;
  end;

  TShellCodeActionWorkspaceFunc = reference to function(const AUri: string): TShellCodeActionWorkspace;
  /// <summary>Fundort der Datei AFileName einer Unit aus Sicht der Datei AUri (#2794).</summary>
  TShellUsesUnitFileFunc = reference to function(const AUri, AFileName: string): TUsesUnitFile;
  TShellCodeActionLevelFunc = reference to function(const AUri: string): string;

  /// <summary>Was die Code-Aktionen von der Komposition brauchen.</summary>
  TShellCodeActionServices = record
    Documents: IDocumentStore;
    Index: ISymbolIndex;
    EnsureUnit: TEnsureUnitFunc;
    RuleContextFor: TRuleContextProvider;
    StringLiteralFor: TStringLiteralProvider;
    DocCommentsFor: TDocCommentsProvider;
    FormatStyleFor: TCodeActionStyleProvider;
    RefactoringFor: TCodeActionRefactoringProvider;
    DefinesFor: TDefinesProvider;
    /// <summary>Aktionen der Testunits und Refactorings.</summary>
    ExtraActions: TExtraActionsFunc;
    LanguageLevelFor: TShellCodeActionLevelFunc;
    /// <summary>Lage des Arbeitsbereichs der Datei, unter dessen Sperre gelesen.</summary>
    WorkspaceOf: TShellCodeActionWorkspaceFunc;
    /// <summary>Fundort einer Unit-Datei (#2794); nil = Gruppe nur nach Namespace.</summary>
    UnitFileOf: TShellUsesUnitFileFunc;
    /// <summary>Für die Einstellungen der Erzeuger; nil ohne.</summary>
    SlashHost: ISlashHost;
  end;

  /// <summary>Code-Aktionen, Dokumentlinks und Farben.</summary>
  TShellCodeActions = class
  private
    FServices: TShellCodeActionServices;
    FCodeActions: TLspCodeActions;
    FDocumentLinks: TLspDocumentLinks;
    FColors: TLspColors;
    function ClassActionContextOf(const AUri: string): TClassActionContext;
    function MemberOrderOf(const AUri: string): TMemberOrderSettings;
    function UsesOrderOf(const AUri: string): TUsesRewrite;
    function GroupOf(const AUri: string): TUsesGroupFunc;
    function IncludePathsOf(const AUri: string): TArray<string>;
    function FormModulesOf(const AUri: string): TArray<string>;
  public
    constructor Create(const AServices: TShellCodeActionServices);
    destructor Destroy; override;
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Index und Einstellungen für die uses-Aktionen und die Diagnosen zu ungenutzten uses (#621).
    /// </summary>
    function UsesContextOf(const AUri: string; out AContext: TUsesContext): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Dfm.FormModel,
  Atlas.Common.Documents.Uris,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.DocumentActions,
  Adapters.Lsp.RuleActions,
  Atlas.Common.Lsp.FormFiles,
  Atlas.Common.Semantics.UsesUsage,
  Core.Bootstrap,
  Platform.Server;

/// <summary>Code-Aktion für binär gespeicherte Formulare (#122): Umwandeln in Text.</summary>
function FormActionsFunc(): TFormActionsFunc;
begin
  Result :=
    function(const AUri, AText: string; const ARange: TTextRange): TArray<TCodeAction>
    var
      mAction: TCodeAction;
    begin
      Result := nil;
      if TFormModel.IsBinary(AText) then
      begin
        mAction := Default(TCodeAction);
        mAction.Title := 'Formular in Text umwandeln';
        mAction.Kind := cQuickFixKind;
        mAction.IsPreferred := True;
        mAction.Command := TLspFormFiles.cConvertCommand;
        mAction.CommandArguments := [AUri];
        Result := [mAction];
      end;
    end;
end;

/// <summary>Units, die AName im interface auf oberster Ebene deklarieren.</summary>
function DeclaringFunc(const AIndex: ISymbolIndex): TUnitsDeclaringFunc;
begin
  Result :=
    function(const AName: string): TArray<string>
    var
      mLocation: TSymbolLocation;
    begin
      Result := nil;
      for mLocation in AIndex.FindSymbols(AName) do
      begin
        if mLocation.Symbol.InInterface and (mLocation.Symbol.Container = '') and
          (IndexText(mLocation.UnitName, Result) < 0) then
        begin
          Result := Result + [mLocation.UnitName];
        end;
      end;
    end;
end;

{ TShellCodeActions }

constructor TShellCodeActions.Create(const AServices: TShellCodeActionServices);
var
  mRules: IRuleCodeActions;
begin
  inherited Create;
  FServices := AServices;
  mRules := TRuleCodeActionsProvider.Create(FServices.RuleContextFor);
  FCodeActions := TLspCodeActions.Create(FServices.Documents, TLspRuleActionsAdapter.Wrap(mRules));
  FCodeActions.FormActions := FormActionsFunc();
  FCodeActions.StringLiteralFor := FServices.StringLiteralFor;
  FCodeActions.DocCommentsFor := FServices.DocCommentsFor;
  // try/finally rückt wie das Formatieren ein (#42, #43).
  FCodeActions.FormatStyleFor := FServices.FormatStyleFor;
  FCodeActions.RefactoringFor := FServices.RefactoringFor;
  FCodeActions.ClassActionContextFor := ClassActionContextOf;
  FCodeActions.MemberOrderFor := MemberOrderOf;
  FCodeActions.UsesOrderFor := UsesOrderOf;
  FCodeActions.UsesContextFor := UsesContextOf;
  FCodeActions.DefinesFor := FServices.DefinesFor;
  FCodeActions.ExtraActions := FServices.ExtraActions;
  FDocumentLinks := TLspDocumentLinks.Create(FServices.Documents, IncludePathsOf);
  FColors := TLspColors.Create(FServices.Documents, PlatformSystemColor);
end;

destructor TShellCodeActions.Destroy;
begin
  FreeAndNil(FCodeActions);
  FreeAndNil(FDocumentLinks);
  FreeAndNil(FColors);
  inherited Destroy;
end;

function TShellCodeActions.ClassActionContextOf(const AUri: string): TClassActionContext;
begin
  Result := TClassActionContext.Default;
  Result.Index := FServices.Index;
  Result.DelphiVersion := FServices.LanguageLevelFor(AUri);
  Result.Uri := AUri;
  Result.Host := FServices.SlashHost;
end;

function TShellCodeActions.MemberOrderOf(const AUri: string): TMemberOrderSettings;
begin
  Result := FServices.WorkspaceOf(AUri).MemberOrder;
end;

function TShellCodeActions.UsesOrderOf(const AUri: string): TUsesRewrite;
var
  mWorkspace: TShellCodeActionWorkspace;
begin
  mWorkspace := FServices.WorkspaceOf(AUri);
  Result := Default(TUsesRewrite);
  Result.Sort := mWorkspace.SortUses;
  Result.ByNamespace := mWorkspace.SortUsesByNamespace;
  if mWorkspace.SortUses and mWorkspace.SortUsesByOrigin then
  begin
    Result.GroupOf := GroupOf(AUri);
    Result.GroupStyle := mWorkspace.UsesGroupStyle;
    Result.MaxLineLength := mWorkspace.MaxLineLength;
  end;
end;

/// <summary>Unit AUnitName im Index, auch über die Unit-Namespaces (SysUtils als System.SysUtils).</summary>
function FindIndexedUnit(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>; const AUnitName: string;
  out AUnit: TUnitIndex): Boolean;
var
  mNamespace: string;
begin
  Result := AIndex.FindUnit(AUnitName, AUnit);
  for mNamespace in ANamespaces do
  begin
    if Result then
    begin
      Exit;
    end;
    Result := AIndex.FindUnit(mNamespace + '.' + AUnitName, AUnit);
  end;
end;

/// <summary>Gruppe nach Fundort der Datei im Index (#2794), ohne Treffer nach Namespace.</summary>
function IndexGroupFunc(const AIndex: ISymbolIndex; const ANamespaces: TArray<string>; const AUri: string;
  const AFileOf: TShellUsesUnitFileFunc): TUsesGroupFunc;
begin
  Result :=
    function(const AUnitName: string): TUsesGroup
    var
      mUnit: TUnitIndex;
    begin
      if FindIndexedUnit(AIndex, ANamespaces, AUnitName, mUnit) then
      begin
        Result := TUsesGroups.OfFile(mUnit.UnitName, AFileOf(AUri, mUnit.FileName));
      end
      else
      begin
        Result := TUsesGroups.OfName(AUnitName);
      end;
    end;
end;

function TShellCodeActions.GroupOf(const AUri: string): TUsesGroupFunc;
begin
  if (FServices.Index = nil) or not Assigned(FServices.UnitFileOf) then
  begin
    Result :=
      function(const AUnitName: string): TUsesGroup
      begin
        Result := TUsesGroups.OfName(AUnitName);
      end;
    Exit;
  end;
  Result := IndexGroupFunc(FServices.Index, FServices.WorkspaceOf(AUri).Namespaces, AUri, FServices.UnitFileOf);
end;

function TShellCodeActions.IncludePathsOf(const AUri: string): TArray<string>;
begin
  Result := FServices.WorkspaceOf(AUri).IncludePaths;
end;

function TShellCodeActions.FormModulesOf(const AUri: string): TArray<string>;
var
  mFileName, mText: string;
begin
  Result := nil;
  mFileName := TDocumentUris.ToPath(AUri);
  if not SameText(ExtractFileExt(mFileName), '.pas') then
  begin
    Exit;
  end;
  // Verweise der Formulardatei auf andere Module halten deren uses-Eintrag (dfm-reference-unit-missing).
  // Offene Dokumente zuerst: Der Designer schickt den ungespeicherten Stand der Formulardatei (#402).
  if TCoreBootstrap.ReadSourceText(FServices.Documents, ChangeFileExt(mFileName, '.dfm'), mText) or
    TCoreBootstrap.ReadSourceText(FServices.Documents, ChangeFileExt(mFileName, '.fmx'), mText) then
  begin
    Result := TFormModel.ForeignModulesOf(mText);
  end;
end;

procedure TShellCodeActions.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FCodeActions.Attach(ADispatcher);
  FDocumentLinks.Attach(ADispatcher);
  FColors.Attach(ADispatcher);
end;

function TShellCodeActions.UsesContextOf(const AUri: string; out AContext: TUsesContext): Boolean;
var
  mWorkspace: TShellCodeActionWorkspace;
  mSource: TUsesUsageSource;
begin
  AContext := Default(TUsesContext);
  mWorkspace := FServices.WorkspaceOf(AUri);
  AContext.Keep := mWorkspace.UsesKeep;
  AContext.Namespaces := mWorkspace.Namespaces;
  AContext.Info := TUsesUsage.UnitInfo(FServices.Index, FServices.EnsureUnit, FormModulesOf(AUri));
  // Namensauflösung für ungenutzte uses (#1925): dieselbe Analyse wie die Regel unused-uses.
  mSource := Default(TUsesUsageSource);
  mSource.Index := FServices.Index;
  mSource.EnsureUnit := FServices.EnsureUnit;
  mSource.Namespaces := mWorkspace.Namespaces;
  AContext.Resolve := TUsesUsage.ResolveFunc(mSource, TDocumentUris.ToPath(AUri), AContext.Info);
  AContext.ResolveTree := TUsesUsage.ResolveTreeFunc(mSource, TDocumentUris.ToPath(AUri), AContext.Info);
  AContext.Declaring := DeclaringFunc(FServices.Index);
  AContext.GroupOf := GroupOf(AUri);
  Result := True;
end;

end.
