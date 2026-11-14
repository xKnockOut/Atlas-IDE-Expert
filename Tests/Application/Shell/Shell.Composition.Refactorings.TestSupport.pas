unit Shell.Composition.Refactorings.TestSupport;

// Gemeinsame Hilfen der Tests der Refactorings des Servers (Shell.Composition.Refactorings.*.Tests): Dienste, die
// nichts finden und nichts lesen, und ein offenes Dokumentenlager.

interface

uses
  Atlas.Common.Documents.Contract,
  Shell.Composition.Refactorings.Services;

/// <summary>Dienste für die Teile der Refactorings: leerer Index, keine Projekte, keine Meldungen; Einstellungen
/// über ASettingsFor.</summary>
function NewRefactoringServices(const ADocuments: IDocumentStore;
  const ASettingsFor: TShellRefactoringSettingsFunc): TShellRefactoringServices;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Index.SymbolIndex;

function NoNames: TArray<string>;
begin
  Result := nil;
end;

function NamesFunc(): TShellNamesFunc;
begin
  Result :=
    function: TArray<string>
    begin
      Result := NoNames;
    end;
end;

function NoText(): TShellUriTextFunc;
begin
  Result :=
    function(const AUri: string): string
    begin
      Result := '';
    end;
end;

/// <summary>Meldungen, Projekt und Namenspräfixe: nichts bekannt.</summary>
procedure SetNoProject(var AServices: TShellRefactoringServices);
begin
  AServices.MessagesFor :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := nil;
    end;
  AServices.ProjectFor :=
    function(const AFileName: string; out AProject: TProjectInfo): Boolean
    begin
      AProject := Default(TProjectInfo);
      Result := False;
    end;
  AServices.NewNamesFor :=
    function(const AUri: string): TPascalNamePrefixes
    begin
      Result := Default(TPascalNamePrefixes);
    end;
end;

function NewRefactoringServices(const ADocuments: IDocumentStore;
  const ASettingsFor: TShellRefactoringSettingsFunc): TShellRefactoringServices;
begin
  Result := Default(TShellRefactoringServices);
  Result.Logger := TLogger.Create;
  Result.Documents := ADocuments;
  Result.Index := TSymbolIndex.Create;
  Result.EnsureUnit :=
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end;
  Result.Namespaces := NamesFunc();
  Result.ProjectFiles := NamesFunc();
  Result.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end;
  Result.SettingsFor := ASettingsFor;
  Result.FormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := Default(TFormatStyle);
    end;
  Result.LanguageLevelFor := NoText();
  Result.DelphiVersionFor := NoText();
  Result.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      AContext := Default(TUsesContext);
      Result := False;
    end;
  SetNoProject(Result);
end;

end.
