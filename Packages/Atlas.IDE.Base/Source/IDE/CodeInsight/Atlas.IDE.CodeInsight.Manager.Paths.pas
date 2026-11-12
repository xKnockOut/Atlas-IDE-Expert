unit Atlas.IDE.CodeInsight.Manager.Paths;

// Pfade und Protokoll des Code Insight-Managers: Server aus HKCU\Software\Atlas\IdePlugin (ServerPath,
// ServerArguments), ersatzweise aus dem früheren Schlüssel HKCU\Software\BetterDelphiLSP\IdePlugin (#403). Ohne
// Eintrag: AtlasServer.exe neben dem Plugin, sonst ..\..\..\Win64\Debug\Bin\ (Ausgabeordner des Repos).
// Diagnose = 1 (DWORD) im selben Schlüssel protokolliert die Aufrufe der IDE in Atlas.IDE.Expert<Version>.log neben
// dem Plugin (Name der BPL bis 1.x).

interface

type
  /// <summary>Pfade von Server und Protokoll und Zeilen im Protokoll des Managers.</summary>
  TAtlasCodeInsightPaths = record
  public
    /// <summary>Pfad zu AtlasServer.exe aus den Einstellungen, sonst DefaultServerPath; AArguments: zusätzliche
    /// Argumente aus der Registry. Auch für die Aufrufe der Optionsseite (#227).</summary>
    class function ServerPath(out AArguments: string): string; static;
    /// <summary>Server ohne eingestellten Pfad: neben dem Plugin, sonst Output\Win64\Debug\Bin im Repo.</summary>
    class function DefaultServerPath: string; static;
    /// <summary>Protokolldatei neben dem Plugin.</summary>
    class function DiagnoseLog: string; static;
    /// <summary>Diagnose = 1 (DWORD): Aufrufe der IDE und Ergebnisse in DiagnoseLog.</summary>
    class function DiagnoseEnabled: Boolean; static;
    /// <summary>Pfade und Benutzername aus einer Zeile des Diagnoselogs (#647); Meldungen wie
    /// „Server nicht gefunden: C:\…“ dürfen so weitergegeben werden.</summary>
    class function WithoutPaths(const AText: string): string; static;
    /// <summary>Zeile mit Uhrzeit und ohne Pfade ins Protokoll; ein gesperrtes Protokoll stört die IDE nie.</summary>
    class procedure Append(const AMessage: string); static;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.RegularExpressions,
  System.Win.Registry;

const
  cRegistryKey = 'Software\Atlas\IdePlugin';
  // Schlüssel vor der Umbenennung in Atlas (#403), wird nur noch gelesen.
  cLegacyRegistryKey = 'Software\BetterDelphiLSP\IdePlugin';

/// <summary>Öffnet den Schlüssel der Einstellungen, ersatzweise den früheren; liefert den geöffneten Schlüssel oder
/// ''.</summary>
function OpenSettingsKey(ARegistry: TRegistry): string;
begin
  ARegistry.RootKey := HKEY_CURRENT_USER;
  if ARegistry.OpenKeyReadOnly(cRegistryKey) then
  begin
    Result := cRegistryKey;
  end
  else if ARegistry.OpenKeyReadOnly(cLegacyRegistryKey) then
  begin
    Result := cLegacyRegistryKey;
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasCodeInsightPaths.DiagnoseEnabled: Boolean;
var
  mRegistry: TRegistry;
begin
  Result := False;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    if (OpenSettingsKey(mRegistry) <> '') and mRegistry.ValueExists('Diagnose') and
      (mRegistry.GetDataType('Diagnose') = rdInteger) then
    begin
      Result := mRegistry.ReadInteger('Diagnose') <> 0;
    end;
  finally
    mRegistry.Free;
  end;
end;

class function TAtlasCodeInsightPaths.DiagnoseLog: string;
const
  cBaseName = 'Atlas.IDE.Base';
  cLogName = 'Atlas.IDE.Expert';
var
  mModule, mName: string;
begin
  // Neben dem Plugin, nicht im Temp-Ordner: Den hat die IDE nicht in jedem Fall gemeinsam mit uns.
  mModule := GetModuleName(HInstance);
  mName := ChangeFileExt(ExtractFileName(mModule), '.log');
  // Der Name bleibt trotz neuem BPL-Namen (#1456): Atlas.IDE.Base370.bpl schreibt Atlas.IDE.Expert370.log.
  if SameText(Copy(mName, 1, Length(cBaseName)), cBaseName) then
  begin
    mName := cLogName + Copy(mName, Length(cBaseName) + 1, MaxInt);
  end;
  Result := ExtractFilePath(mModule) + mName;
end;

class function TAtlasCodeInsightPaths.ServerPath(out AArguments: string): string;
var
  mRegistry: TRegistry;
  mKey: string;
begin
  Result := '';
  AArguments := '';
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mKey := OpenSettingsKey(mRegistry);
    if (mKey <> '') and mRegistry.ValueExists('ServerPath') then
    begin
      Result := mRegistry.ReadString('ServerPath');
    end;
    if (mKey <> '') and mRegistry.ValueExists('ServerArguments') then
    begin
      AArguments := mRegistry.ReadString('ServerArguments');
    end;
  finally
    mRegistry.Free;
  end;
  // Der alte Schlüssel zeigt meist noch auf BetterDelphiLSP.exe; fehlt sie, gelten die Vorgaben.
  if (mKey = cLegacyRegistryKey) and (Result <> '') and not FileExists(Result) then
  begin
    Result := '';
  end;
  if Result = '' then
  begin
    Result := DefaultServerPath;
  end;
end;

class function TAtlasCodeInsightPaths.DefaultServerPath: string;
var
  mPluginDir: string;
begin
  mPluginDir := ExtractFilePath(GetModuleName(HInstance));
  Result := mPluginDir + 'AtlasServer.exe';
  if FileExists(Result) then
  begin
    Exit;
  end;
  // Release-Paket (#495): BPL in <Ziel>\Win32 bzw. \Win64, der Server eine Ebene darüber.
  Result := ExpandFileName(mPluginDir + '..\AtlasServer.exe');
  if FileExists(Result) then
  begin
    Exit;
  end;
  // Ausgabeordner des Repos: Win64 bevorzugt, sonst ein Win32-Bau des Servers.
  Result := ExpandFileName(mPluginDir + '..\..\..\Win64\Debug\Bin\AtlasServer.exe');
  if not FileExists(Result) and FileExists(ExpandFileName(mPluginDir + '..\..\..\Win32\Debug\Bin\AtlasServer.exe')) then
  begin
    Result := ExpandFileName(mPluginDir + '..\..\..\Win32\Debug\Bin\AtlasServer.exe');
  end;
end;

class function TAtlasCodeInsightPaths.WithoutPaths(const AText: string): string;
var
  mUserName: string;
begin
  Result := TRegEx.Replace(AText, '(?:\b[A-Za-z]:|\\\\)[\\/]\S*|file:\S+|\S*\\\S*', '<pfad>');
  mUserName := GetEnvironmentVariable('USERNAME');
  if Length(mUserName) >= 3 then
  begin
    Result := StringReplace(Result, mUserName, '<benutzer>', [rfReplaceAll, rfIgnoreCase]);
  end;
end;

class procedure TAtlasCodeInsightPaths.Append(const AMessage: string);
begin
  try
    TFile.AppendAllText(DiagnoseLog, FormatDateTime('hh":"nn":"ss.zzz', Now) + ' ' + WithoutPaths(AMessage) +
      sLineBreak, TEncoding.UTF8);
  except
    // Protokoll ist Beiwerk; ein gesperrtes Log darf die IDE nicht stören.
  end;
end;

end.
