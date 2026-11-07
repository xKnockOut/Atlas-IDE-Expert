unit Shell.Bootstrap;

// Host-Rolle Shell: gemeinsamer Aufbau für LSP-Server, MCP-Modus und Linter
// (Code-Review D-08). Bisher hatte jeder Modus eigene Kopien:
// - Dateien lesen wie der Server (Kodierung erkennen),
// - Projekte einer Projektgruppe im Ordner,
// - globale Einstellungen aus %APPDATA%\Atlas\settings.json,
// - atlas.json eines Ordners ohne Editor.
// Die Logdatei (--log) richtet TShellDiagnostics.AddLogFile ein.
// Bewusst ohne Windows-Units, damit die Tests auch ohne Windows laufen.

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Localization.Texts;

type
  TShellBootstrap = class
  public
    /// <summary>Datei lesen wie der Server (Kodierung erkennen); False und '' ohne Datei.</summary>
    class function ReadSourceText(const AFileName: string; out AText: string): Boolean; overload; static;
    /// <summary>Wie oben, geöffnete Dokumente aus ADocuments haben aber Vorrang vor der Datei auf der Platte.
    /// </summary>
    class function ReadSourceText(const ADocuments: IDocumentStore; const AFileName: string;
      out AText: string): Boolean; overload; static;
    /// <summary>Projekte der einzigen .groupproj in ARoot (#648); leer ohne oder mit mehreren Gruppen.</summary>
    class function GroupProjects(const ARoot: string; const ALogger: ILogger): TArray<string>; static;
    /// <summary>Projekte der Projektgruppe AGroupFile; leer, wenn sie nicht lesbar ist (Warnung im Log).</summary>
    class function LoadGroup(const AGroupFile: string; const ALogger: ILogger): TArray<string>; static;
    /// <summary>%APPDATA%\Atlas\settings.json; '' ohne APPDATA.</summary>
    class function GlobalSettingsFile: string; overload; static;
    /// <summary>settings.json unter AAppData\Atlas; '' ohne AAppData.</summary>
    class function GlobalSettingsFile(const AAppData: string): string; overload; static;
    /// <summary>Text der globalen settings.json oder ''. Ist sie nicht lesbar, steht eine Warnung in
    /// ALogger; ohne ALogger geht die Ausnahme an den Aufrufer.</summary>
    class function LoadGlobalSettings(const ALogger: ILogger): string; overload; static;
    class function LoadGlobalSettings(const AFileName: string; const ALogger: ILogger): string; overload; static;
    /// <summary>Einstellungen aus atlas.json (oder der früheren Datei) in ARoot, ohne globale Datei und
    /// Editor; ohne Datei die Vorgaben.</summary>
    class function ProjectSettings(const ARoot: string): TServerSettings; static;
    /// <summary>Sprache der Texte ohne Client (#1458): ALocale (--locale), sonst language aus der globalen
    /// settings.json (AGlobalText), sonst Englisch.</summary>
    class function TextLanguage(const ALocale, AGlobalText: string): TTextLanguage; static;
    /// <summary>Setzt die Sprache nach TextLanguage mit der globalen settings.json; eine unlesbare Datei zählt
    /// als leer. Der LSP-Server wählt nach initialize mit der Sprache des Clients neu.</summary>
    class procedure UseTextLanguage(const ALocale: string); static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Projects.GroupReader,
  Atlas.Text.LogMarks;

class function TShellBootstrap.ReadSourceText(const AFileName: string; out AText: string): Boolean;
var
  mFileFormat: TFileFormat;
begin
  Result := (AFileName <> '') and FileExists(AFileName);
  if Result then
  begin
    AText := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  end
  else
  begin
    AText := '';
  end;
end;

class function TShellBootstrap.ReadSourceText(const ADocuments: IDocumentStore; const AFileName: string;
  out AText: string): Boolean;
var
  mDocument: ITextDocument;
begin
  if (ADocuments <> nil) and ADocuments.TryGet(TDocumentUris.FromPath(AFileName), mDocument) then
  begin
    AText := mDocument.Text;
    Exit(True);
  end;
  Result := ReadSourceText(AFileName, AText);
end;

class function TShellBootstrap.LoadGroup(const AGroupFile: string; const ALogger: ILogger): TArray<string>;
begin
  Result := nil;
  try
    Result := TGroupProjReader.Load(AGroupFile);
    if ALogger <> nil then
    begin
      ALogger.Info(Format('Projektgruppe %s: %d Projekte', [TLogMarks.Path(AGroupFile), Length(Result)]));
    end;
  except
    on E: Exception do
    begin
      if ALogger <> nil then
      begin
        ALogger.Warning(Format('Projektgruppe %s nicht lesbar: %s', [TLogMarks.Path(AGroupFile),
          TLogMarks.Text(E.Message)]));
      end;
      Result := nil;
    end;
  end;
end;

class function TShellBootstrap.GroupProjects(const ARoot: string; const ALogger: ILogger): TArray<string>;
var
  mGroups: TArray<string>;
begin
  Result := nil;
  try
    mGroups := TDirectory.GetFiles(ARoot, '*.groupproj');
  except
    // Nicht lesbare Ordner haben keine Gruppe.
    on Exception do
      mGroups := nil;
  end;
  if Length(mGroups) = 1 then
  begin
    Result := LoadGroup(mGroups[0], ALogger);
  end;
end;

class function TShellBootstrap.GlobalSettingsFile: string;
begin
  Result := GlobalSettingsFile(GetEnvironmentVariable('APPDATA'));
end;

class function TShellBootstrap.GlobalSettingsFile(const AAppData: string): string;
begin
  Result := TConfigurationScopes.GlobalFile(AAppData);
end;

class function TShellBootstrap.LoadGlobalSettings(const ALogger: ILogger): string;
begin
  Result := LoadGlobalSettings(GlobalSettingsFile, ALogger);
end;

class function TShellBootstrap.LoadGlobalSettings(const AFileName: string; const ALogger: ILogger): string;
var
  mFileFormat: TFileFormat;
begin
  Result := '';
  if (AFileName = '') or not FileExists(AFileName) then
  begin
    Exit;
  end;
  try
    Result := TFileEncoding.LoadFromFile(AFileName, mFileFormat);
  except
    // Gerade geschrieben oder gesperrt: Der Server liest sie beim nächsten Ereignis erneut.
    on E: Exception do
    begin
      if ALogger = nil then
      begin
        raise;
      end;
      ALogger.Warning('Globale Einstellungen nicht lesbar: ' + TLogMarks.Text(E.Message));
    end;
  end;
end;

class function TShellBootstrap.ProjectSettings(const ARoot: string): TServerSettings;
var
  mText: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  if not ReadSourceText(ExistingOrLegacyFile(ARoot, cConfigurationFileName, cLegacyConfigurationFileName), mText) then
  begin
    Exit(TServerSettings.Default);
  end;
  Result := TConfigurationParser.Parse(TConfigurationScopes.Filter(mText, TConfigurationScope.Project), mIssues);
end;

class function TShellBootstrap.TextLanguage(const ALocale, AGlobalText: string): TTextLanguage;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TAtlasLocale.Resolve(ALocale, TConfigurationParser.Parse(AGlobalText, mIssues).Language);
end;

class procedure TShellBootstrap.UseTextLanguage(const ALocale: string);
var
  mGlobal: string;
begin
  try
    mGlobal := LoadGlobalSettings(nil);
  except
    on Exception do
      mGlobal := '';
  end;
  TAtlasLocale.Use(TextLanguage(ALocale, mGlobal));
end;

end.
