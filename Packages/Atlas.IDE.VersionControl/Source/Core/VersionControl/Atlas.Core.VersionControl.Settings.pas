unit Atlas.Core.VersionControl.Settings;

// Einstellungen vcs.* der globalen Atlas-Einstellungen, wie sie das Plugin braucht: Anbieter, Pfade zu git und
// svn, Zeitlimit und Zuordnung Projekt → Arbeitskopie. Aus dem Text der Datei gelesen, ohne IDE testbar (#1967);
// Atlas.IDE.VersionControl.Service lädt die Datei und merkt sich das Ergebnis.

interface

uses
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Projects.VersionControl;

type
  TAtlasVcsPluginSettings = record
  public const
    /// <summary>Zeitlimit eines Aufrufs in Sekunden; außerhalb 1–300 gilt die Vorgabe wie im Parser des Servers.
    /// </summary>
    cDefaultTimeoutSeconds = 15;
    cMinTimeoutSeconds = 1;
    cMaxTimeoutSeconds = 300;
    cMsPerSecond = 1000;
  public
    Provider: TAtlasVcsProvider;
    GitPath: string;
    SvnPath: string;
    TimeoutMs: Cardinal;
    Projects: TArray<TAtlasVcsProjectMapping>;
    /// <summary>Vorgaben: Anbieter automatisch, Programme aus dem Suchpfad, 15 s, keine Zuordnung.</summary>
    class function Default: TAtlasVcsPluginSettings; static;
    /// <summary>Werte aus dem JSON-Text AText der Einstellungsdatei; Vorgaben, wo ein Wert fehlt, und ganz, wenn
    /// der Text kein JSON-Objekt ist.</summary>
    class function Parse(const AText: string): TAtlasVcsPluginSettings; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Settings.JsonText;

/// <summary>Inhalt eines JSON-Strings (getrimmt); '' ohne Wert oder bei anderem Typ. TJSONNumber erbt unter
/// Delphi 12 und FPC von TJSONString und wird deshalb ausdrücklich ausgeschlossen.</summary>
function JsonString(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if AJson = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if (mValue is TJSONString) and not (mValue is TJSONNumber) then
    begin
      Result := Trim(TJSONString(mValue).Value);
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasVcsPluginSettings.Default: TAtlasVcsPluginSettings;
begin
  Result.Provider := TAtlasVcsProvider.Auto;
  Result.GitPath := '';
  Result.SvnPath := '';
  Result.TimeoutMs := cDefaultTimeoutSeconds * cMsPerSecond;
  Result.Projects := nil;
end;

class function TAtlasVcsPluginSettings.Parse(const AText: string): TAtlasVcsPluginSettings;
var
  mRoot: TJSONObject;
  mSeconds: Integer;
begin
  Result := Default;
  mRoot := TAtlasJsonText.Parse(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    Result.Provider := AtlasVcsProviderOf(TAtlasJsonText.ValueAt(mRoot, 'vcs.provider'));
    Result.GitPath := JsonString(TAtlasJsonText.ValueAt(mRoot, 'vcs.git.path'));
    Result.SvnPath := JsonString(TAtlasJsonText.ValueAt(mRoot, 'vcs.svn.path'));
    mSeconds := StrToIntDef(TAtlasJsonText.ValueAt(mRoot, 'vcs.timeoutSeconds'), cDefaultTimeoutSeconds);
    if (mSeconds < cMinTimeoutSeconds) or (mSeconds > cMaxTimeoutSeconds) then
    begin
      mSeconds := cDefaultTimeoutSeconds;
    end;
    Result.TimeoutMs := Cardinal(mSeconds) * cMsPerSecond;
    Result.Projects := TAtlasVcsProjects.Read(TAtlasJsonText.ValueAt(mRoot, TAtlasVcsProjects.cPath));
  finally
    mRoot.Free;
  end;
end;

end.
