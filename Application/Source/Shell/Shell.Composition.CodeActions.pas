unit Shell.Composition.CodeActions;

// Internals-Rolle Shell: Code-Aktionen (#122, #182, #621), Dokumentlinks auf Include-Dateien und Farben im
// Editor. Die Komposition reicht Dokumente, Index, Prüfkontext, Einstellungen je Datei und die Lage des
// Arbeitsbereichs als Dienste herein; die Code-Aktionen entstehen hier.

interface

uses
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ClassActions,
  Atlas.Common.Lsp.SyntaxDiagnostics,
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
    UsesKeep: TArray<string>;
    Namespaces: TArray<string>;
    IncludePaths: TArray<string>;
  end;

  TShellCodeActionWorkspaceFunc = reference to function(const AUri: string): TShellCodeActionWorkspace;
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
    function SortUsesOf(const AUri: string): Boolean;
    function SortUsesByNamespaceOf(const AUri: string): Boolean;
    function IncludePathsOf(const AUri: string): TArray<string>;
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
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Lsp.FormFiles,
  Shell.Platform;

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
        mAction.Kind := QuickFixKind;
        mAction.IsPreferred := True;
        mAction.Command := TLspFormFiles.ConvertCommand;
        mAction.CommandArguments := [AUri];
        Result := [mAction];
      end;
    end;
end;

/// <summary>Was der Index über eine Unit für die uses-Analyse weiß; lädt sie bei Bedarf über AEnsureUnit.</summary>
function UsesInfoFunc(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc): TUsesUnitInfoFunc;
begin
  Result :=
    function(const AUnitName: string): TUsesUnitInfo
    var
      mUnit: TUnitIndex;
      mSymbol: TIndexSymbol;
    begin
      Result := Default(TUsesUnitInfo);
      AEnsureUnit(AUnitName);
      if not AIndex.FindUnit(AUnitName, mUnit) then
      begin
        Exit;
      end;
      Result.Known := True;
      Result.HasInitialization := mUnit.HasInitialization;
      for mSymbol in mUnit.Symbols do
      begin
        if mSymbol.InInterface then
        begin
          Result.Names := Result.Names + [mSymbol.Name];
        end;
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

constructor TShellCodeActions.Create(const AServices: TShellCodeActionServices);
begin
  inherited Create;
  FServices := AServices;
  FCodeActions := TLspCodeActions.Create(FServices.Documents, FServices.RuleContextFor);
  FCodeActions.FormActions := FormActionsFunc();
  FCodeActions.StringLiteralFor := FServices.StringLiteralFor;
  FCodeActions.DocCommentsFor := FServices.DocCommentsFor;
  // try/finally rückt wie das Formatieren ein (#42, #43).
  FCodeActions.FormatStyleFor := FServices.FormatStyleFor;
  FCodeActions.RefactoringFor := FServices.RefactoringFor;
  FCodeActions.ClassActionContextFor := ClassActionContextOf;
  FCodeActions.MemberOrderFor := MemberOrderOf;
  FCodeActions.SortUsesFor := SortUsesOf;
  FCodeActions.SortUsesByNamespaceFor := SortUsesByNamespaceOf;
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

procedure TShellCodeActions.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FCodeActions.Attach(ADispatcher);
  FDocumentLinks.Attach(ADispatcher);
  FColors.Attach(ADispatcher);
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

function TShellCodeActions.SortUsesOf(const AUri: string): Boolean;
begin
  Result := FServices.WorkspaceOf(AUri).SortUses;
end;

function TShellCodeActions.SortUsesByNamespaceOf(const AUri: string): Boolean;
begin
  Result := FServices.WorkspaceOf(AUri).SortUsesByNamespace;
end;

function TShellCodeActions.IncludePathsOf(const AUri: string): TArray<string>;
begin
  Result := FServices.WorkspaceOf(AUri).IncludePaths;
end;

function TShellCodeActions.UsesContextOf(const AUri: string; out AContext: TUsesContext): Boolean;
var
  mWorkspace: TShellCodeActionWorkspace;
begin
  AContext := Default(TUsesContext);
  mWorkspace := FServices.WorkspaceOf(AUri);
  AContext.Keep := mWorkspace.UsesKeep;
  AContext.Namespaces := mWorkspace.Namespaces;
  AContext.Info := UsesInfoFunc(FServices.Index, FServices.EnsureUnit);
  AContext.Declaring := DeclaringFunc(FServices.Index);
  Result := True;
end;

end.
