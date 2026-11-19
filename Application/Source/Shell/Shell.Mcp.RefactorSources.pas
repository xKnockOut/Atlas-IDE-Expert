unit Shell.Mcp.RefactorSources;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Anbindung des Werkzeugs refactor (#2150) an die Projektgruppe: Dienste
// des TMcpRefactorHost aus Einstellungen, Projekt und Namensregeln der Arbeitsbereiche sowie Anlegen und Löschen von
// Dateien für die Bearbeitungswerkzeuge.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Mcp.EditTools,
  Shell.Mcp.Context;

type
  TMcpRefactorSources = class
  public
    /// <summary>Gibt AContext die Quelle von refactor (Code-Aktionen und Refactorings des Servers über Index und
    /// Gruppe des Kontexts) und den Bearbeitungswerkzeugen das Anlegen und Löschen von Dateien.</summary>
    class procedure Attach(var AContext: TMcpToolContext; const ALogger: ILogger); static;
    /// <summary>Neue Dateien als UTF-8 mit BOM und CRLF anlegen, Dateien von der Platte löschen.</summary>
    class function FileOperations: TMcpFileOperations; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Mcp.Server,
  Shell.Workspace,
  Shell.WorkspaceGroup,
  Shell.Composition.Refactorings.Services,
  Shell.Mcp.RefactorHost;

/// <summary>Neue Datei aus refactor (#2150): UTF-8 mit BOM und CRLF wie neue Units der IDE, Ordner wird angelegt.
/// </summary>
procedure CreateSourceFile(const AFileName, AText: string);
begin
  if (ExtractFileDir(AFileName) <> '') and not ForceDirectories(ExtractFileDir(AFileName)) then
  begin
    raise EMcpToolError.CreateFmt('%s: %s', [ExtractFileDir(AFileName), SysErrorMessage(GetLastOSError)]);
  end;
  TFileEncoding.SaveToFile(AFileName, AText, TFileFormat.Create(TFileEncodingKind.Utf8Bom, TLineBreakStyle.CRLF));
end;

/// <summary>Gelöschte Datei aus refactor (#2150), z. B. beim sicheren Löschen einer Unit.</summary>
function DeleteSourceFile(const AFileName: string; out AError: string): Boolean;
begin
  AError := '';
  Result := System.SysUtils.DeleteFile(AFileName);
  if not Result then
  begin
    AError := SysErrorMessage(GetLastOSError);
  end;
end;

/// <summary>Präfixe neuer Namen wie im Server (TShellFileOptions.NewNamesFor): die der Namensregel des Projekts.
/// </summary>
function NewNamesOf(AGroup: TShellWorkspaceGroup): TShellNewNamesFunc;
begin
  Result :=
    function(const AUri: string): TPascalNamePrefixes
    var
      mWorkspace: TShellWorkspace;
      mContext: TRuleContext;
      mFileName: string;
    begin
      mFileName := TDocumentUris.ToPath(AUri);
      mWorkspace := AGroup.WorkspaceOf(mFileName);
      mContext := Default(TRuleContext);
      mContext.RelativePath := ExtractRelativePath(IncludeTrailingPathDelimiter(
        mWorkspace.Configuration.ConfigRoot), mFileName);
      mContext.Naming := mWorkspace.RuleServices.Naming;
      mContext.UnitName := ChangeFileExt(ExtractFileName(mFileName), '');
      Result := TRuleEngine.NewNames(BuiltinRules, mWorkspace.Configuration.Settings, mContext);
    end;
end;

/// <summary>Delphi-Version der Datei: aus dem Projekt, sonst delphiVersion in atlas.json.</summary>
function DelphiVersionOf(AGroup: TShellWorkspaceGroup): TShellUriTextFunc;
begin
  Result :=
    function(const AUri: string): string
    var
      mWorkspace: TShellWorkspace;
    begin
      mWorkspace := AGroup.WorkspaceOf(TDocumentUris.ToPath(AUri));
      Result := mWorkspace.State.DelphiVersion;
      if Result = '' then
      begin
        Result := mWorkspace.Configuration.Settings.DelphiVersion;
      end;
    end;
end;

function RefactorSettingsOf(AGroup: TShellWorkspaceGroup): TMcpRefactorSettingsFunc;
begin
  Result :=
    function(const AFileName: string): TServerSettings
    begin
      Result := AGroup.WorkspaceOf(AFileName).Configuration.Settings;
    end;
end;

function RefactorProjectOf(AGroup: TShellWorkspaceGroup): TShellProjectFunc;
begin
  Result :=
    function(const AFileName: string; out AProject: TProjectInfo): Boolean
    begin
      Result := AGroup.WorkspaceOf(AFileName).State.Project(AProject);
    end;
end;

/// <summary>Namensräume, Units und Dateien der Gruppe.</summary>
procedure AddGroupAccess(var AServices: TMcpRefactorHostServices; AGroup: TShellWorkspaceGroup);
begin
  AServices.EnsureUnit :=
    function(const AUnitName: string): Boolean
    begin
      Result := AGroup.EnsureUnit(AUnitName);
    end;
  AServices.Namespaces :=
    function: TArray<string>
    begin
      Result := AGroup.Main.State.Namespaces;
    end;
  AServices.ProjectFiles :=
    function: TArray<string>
    begin
      Result := AGroup.AllFiles;
    end;
end;

function RefactorStyleOf(AGroup: TShellWorkspaceGroup): TShellFormatStyleFunc;
begin
  Result :=
    function(const AUri: string): TFormatStyle
    begin
      Result := FormatStyleOf(AGroup, TDocumentUris.ToPath(AUri));
    end;
end;

function NewHost(const AIndex: ISymbolIndex; AGroup: TShellWorkspaceGroup; const ALogger: ILogger): IMcpRefactorHost;
var
  mServices: TMcpRefactorHostServices;
begin
  mServices := Default(TMcpRefactorHostServices);
  mServices.Logger := ALogger;
  mServices.Index := AIndex;
  AddGroupAccess(mServices, AGroup);
  mServices.ReadText := ReadSourceText;
  mServices.SettingsFor := RefactorSettingsOf(AGroup);
  mServices.FormatStyleFor := RefactorStyleOf(AGroup);
  mServices.DelphiVersionFor := DelphiVersionOf(AGroup);
  mServices.NewNamesFor := NewNamesOf(AGroup);
  mServices.ProjectFor := RefactorProjectOf(AGroup);
  Result := TMcpRefactorHost.Create(mServices);
end;

{ TMcpRefactorSources }

class procedure TMcpRefactorSources.Attach(var AContext: TMcpToolContext; const ALogger: ILogger);
begin
  AContext.Refactor := NewHost(AContext.Index, AContext.Group, ALogger);
  AContext.Edit.Files := FileOperations;
end;

class function TMcpRefactorSources.FileOperations: TMcpFileOperations;
begin
  Result := Default(TMcpFileOperations);
  Result.CreateFile := CreateSourceFile;
  Result.DeleteFile := DeleteSourceFile;
end;

end.
