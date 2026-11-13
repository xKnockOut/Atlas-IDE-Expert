unit Atlas.Common.Monitor.Settings;

// Einstellungen von AtlasMonitor (#1901) in einer eigenen Datei des Programms, %APPDATA%\Atlas\monitor.json:
// monitor.trayIcon (Symbol im Infobereich, Vorgabe an) und monitor.startWithWindows (Vorgabe aus). Lesen ist
// nachsichtig: Fehlt die Datei oder ein Schlüssel, gilt die Vorgabe; unbekannte Schlüssel bleiben beim Speichern
// erhalten. Der Abschnitt "check" hält den Stand des Prüffensters (#1900: Ziele, Befehl, Optionen, Editor). Dazu die
// Sprache des Programms: --locale, sonst language aus settings.json, sonst die Sprache von Windows.

interface

uses
  System.SysUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Targets;

type
  TMonitorSettings = record
  public const
    cFileName = 'monitor.json';
  public
    TrayIcon: Boolean;
    StartWithWindows: Boolean;
    /// <summary>Stand des Prüffensters (#1900).</summary>
    Check: TMonitorCheckState;
    class function Defaults: TMonitorSettings; static;
    /// <summary>Einstellungen aus dem Text einer monitor.json; Vorgaben für fehlende oder ungültige Werte.</summary>
    class function FromText(const AText: string): TMonitorSettings; static;
    /// <summary>Text der Datei mit diesen Werten; die übrigen Schlüssel aus AOldText bleiben.</summary>
    function ToText(const AOldText: string): string;
    /// <summary>Pfad der Datei unter AAppData\Atlas; '' ohne AAppData.</summary>
    class function FileIn(const AAppData: string): string; static;
    /// <summary>Liest AFileName; Vorgaben, wenn sie fehlt oder unlesbar ist.</summary>
    class function Load(const AFileName: string): TMonitorSettings; static;
    /// <summary>Schreibt AFileName atomar; False bei einem Fehler.</summary>
    function Save(const AFileName: string): Boolean;
    /// <summary>Sprache: ALocale (--locale), sonst language aus AGlobalText (settings.json), sonst AWindowsCode
    /// (z. B. "de-DE"), sonst Englisch.</summary>
    class function LanguageOf(const ALocale, AGlobalText, AWindowsCode: string): TTextLanguage; static;
  end;

implementation

uses
  System.IOUtils,
  System.JSON,
  Atlas.Text.Json;

const
  cSection = 'monitor';
  cTrayIcon = 'trayIcon';
  cStartWithWindows = 'startWithWindows';
  cCheck = 'check';

class function TMonitorSettings.Defaults: TMonitorSettings;
begin
  Result := Default(TMonitorSettings);
  Result.TrayIcon := True;
  Result.StartWithWindows := False;
  Result.Check := TMonitorCheckState.Defaults;
end;

class function TMonitorSettings.FromText(const AText: string): TMonitorSettings;
var
  mRoot, mSection: TJSONObject;
begin
  Result := Defaults;
  mRoot := TJsonRead.ParseObjectOrEmpty(AText);
  try
    mSection := TJsonRead.Obj(mRoot, cSection);
    Result.TrayIcon := TJsonRead.FlagOr(mSection, cTrayIcon, Result.TrayIcon);
    Result.StartWithWindows := TJsonRead.FlagOr(mSection, cStartWithWindows, Result.StartWithWindows);
    Result.Check := TMonitorCheckState.FromJson(TJsonRead.Obj(mRoot, cCheck));
  finally
    mRoot.Free;
  end;
end;

/// <summary>Ersetzt den Wert AName in AObject durch AValue.</summary>
procedure PutFlag(AObject: TJSONObject; const AName: string; AValue: Boolean);
begin
  AObject.RemovePair(AName).Free;
  AObject.AddPair(AName, TJSONBool.Create(AValue));
end;

function TMonitorSettings.ToText(const AOldText: string): string;
var
  mRoot, mSection: TJSONObject;
begin
  mRoot := TJsonRead.ParseObjectOrEmpty(AOldText);
  try
    mSection := TJsonRead.Obj(mRoot, cSection);
    if mSection = nil then
    begin
      mRoot.RemovePair(cSection).Free;
      mSection := TJSONObject.Create;
      mRoot.AddPair(cSection, mSection);
    end;
    PutFlag(mSection, cTrayIcon, TrayIcon);
    PutFlag(mSection, cStartWithWindows, StartWithWindows);
    mRoot.RemovePair(cCheck).Free;
    mRoot.AddPair(cCheck, Check.ToJson);
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

class function TMonitorSettings.FileIn(const AAppData: string): string;
begin
  Result := '';
  if AAppData <> '' then
  begin
    Result := TPath.Combine(TPath.Combine(AAppData, 'Atlas'), cFileName);
  end;
end;

/// <summary>Inhalt von AFileName; '' wenn sie fehlt oder nicht lesbar ist.</summary>
function ReadText(const AFileName: string): string;
begin
  Result := '';
  try
    if (AFileName <> '') and TFile.Exists(AFileName) then
    begin
      Result := TFile.ReadAllText(AFileName, TEncoding.UTF8);
    end;
  except
    // lsp-ignore: catch-all-without-raise -- unlesbare Datei: Vorgaben, das Programm startet trotzdem
    on Exception do
      Result := '';
  end;
end;

class function TMonitorSettings.Load(const AFileName: string): TMonitorSettings;
begin
  Result := FromText(ReadText(AFileName));
end;

function TMonitorSettings.Save(const AFileName: string): Boolean;
var
  mTemp: string;
begin
  Result := False;
  if AFileName = '' then
  begin
    Exit;
  end;
  try
    ForceDirectories(ExtractFileDir(AFileName));
    mTemp := AFileName + '.tmp';
    TFile.WriteAllText(mTemp, ToText(ReadText(AFileName)), TEncoding.UTF8);
    if TFile.Exists(AFileName) then
    begin
      TFile.Delete(AFileName);
    end;
    TFile.Move(mTemp, AFileName);
    Result := True;
  except
    // lsp-ignore: catch-all-without-raise -- Ergebnis False; die Oberfläche meldet den Fehler
    on Exception do
      Result := False;
  end;
end;

class function TMonitorSettings.LanguageOf(const ALocale, AGlobalText, AWindowsCode: string): TTextLanguage;
var
  mRoot: TJSONObject;
  mSetting: string;
begin
  if TAtlasLocale.TryParse(ALocale, Result) then
  begin
    Exit;
  end;
  mRoot := TJsonRead.ParseObjectOrEmpty(AGlobalText);
  try
    mSetting := TJsonRead.Text(mRoot, 'language');
  finally
    mRoot.Free;
  end;
  if TAtlasLocale.TryParse(mSetting, Result) or TAtlasLocale.TryParse(AWindowsCode, Result) then
  begin
    Exit;
  end;
  Result := TTextLanguage.English;
end;

end.
