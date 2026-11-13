unit Atlas.IDE.Foundation.Host;

// Dienste von Base für die Module (#1455): Serversitzung (laufend
// bzw. bei Bedarf gestartet), Befehle im Hintergrund an den Server,
// Meldungsansicht „Atlas“, Warnungen, Bericht und Diagnoselog, Felder im
// Atlas-Statusfeld und Compile-Ereignisse; für Bereiche wie die
// Willkommensseite außerdem Zustand des Servers, Befehle der Palette,
// Tastenübersicht, Ausblenden über das Kontextmenü (#628), eigene Snippets
// und Knöpfe für Neustart, Optionen, Logordner und Update. Builds auf Auftrag stellt das
// Modul Build-Pipeline über IAtlasBuildJobs (Atlas.IDE.Contracts.BuildPipeline) bereit.
// Teilnehmer, die ein Modul an den Compile-Ereignissen anmeldet, und Felder im
// Statusfeld nimmt es beim Stoppen selbst zurück (Remove, leerer Text). Die Kompositionswurzel setzt die Quellen beim
// Start
// (Install) und nimmt sie beim Entladen zurück (Uninstall); danach liefern
// sie nil bzw. tun nichts. Ein Modul fragt die Sitzung bei jedem Aufruf
// neu, statt sie zu speichern: Der Server kann neu starten.
// Antworten des Servers erreichen das Modul nur, solange sein Scope offen
// ist (Regel 3, TAtlasModuleAnswer), und immer im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Build.Events,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Lines,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Completion.Snippets;

type
  /// <summary>Befehl mit Argumenten (JSON-Array) im Hintergrund an den laufenden Server; ADone bekommt das
  /// Ergebnis als JSON ('' bei Fehler oder Zeitlimit) in einem beliebigen Thread. False = nicht gestartet (kein
  /// Server oder schon ein Befehl unterwegs).</summary>
  TAtlasHostCommandRunner = reference to function(const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal;
    const ADone: TProc<string>): Boolean;

  /// <summary>Anfrage (LSP-Methode mit Parametern als JSON-Objekt) im Hintergrund an den laufenden Server, abbrechbar
  /// über ACancelled; ADone bekommt die Antwort als JSON ('' bei Fehler, Abbruch oder Zeitlimit) in einem beliebigen
  /// Thread. False = nicht gestartet (kein Server).</summary>
  TAtlasHostRequestRunner = reference to function(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
    const ACancelled: TFunc<Boolean>; const ADone: TProc<string>): Boolean;

  /// <summary>Zusatzfeld im Atlas-Statusfeld setzen (TAtlasStatusExtra); leerer Text entfernt es.</summary>
  TAtlasHostStatusExtra = reference to procedure(const AExtra: TAtlasStatusExtra);

  /// <summary>Indiziert der Server gerade? APercent -1 = unbekannt.</summary>
  TAtlasHostIndexing = reference to function(out APercent: Integer): Boolean;

  /// <summary>Einstellung AKey über das Kontextmenü an APoint ausblenden (#628, mit „Rückgängig“); False, wenn
  /// Ausblenden aus ist oder der Schlüssel nicht abschaltbar.</summary>
  TAtlasHostHideSetting = reference to function(const AKey: string; APoint: TPoint): Boolean;

  /// <summary>Quellen der Dienste; jedes Feld darf fehlen.</summary>
  TAtlasHostServices = record
    /// <summary>Laufende Sitzung, startet keinen Server.</summary>
    Session: TFunc<TLspSession>;
    /// <summary>Sitzung, Server bei Bedarf gestartet (Hauptthread).</summary>
    ActiveSession: TFunc<TLspSession>;
    Log: TProc<string>;
    /// <summary>Warnung an Benutzer (Meldungsansicht und Bericht des Managers).</summary>
    Warning: TProc<string>;
    /// <summary>Zeile im Bericht des Managers (Diagnose), ohne Meldungsansicht.</summary>
    Report: TProc<string>;
    RunCommand: TAtlasHostCommandRunner;
    /// <summary>Wie RunCommand, aber nebenläufig zu anderen Befehlen (für Fenster, die regelmäßig nachfragen);
    /// False nur ohne laufenden Server.</summary>
    RunServerCommand: TAtlasHostCommandRunner;
    RunRequest: TAtlasHostRequestRunner;
    StatusExtra: TAtlasHostStatusExtra;
    CompileEvents: TFunc<TAtlasCompileEvents>;
    /// <summary>Zustand des Servers (Version, Pfad, Sitzung) wie im Statusfeld.</summary>
    ServerInfo: TFunc<TAtlasServerInfo>;
    ServerIndexing: TAtlasHostIndexing;
    /// <summary>Units im Index; -1 = unbekannt.</summary>
    IndexedUnits: TFunc<Integer>;
    /// <summary>Atlas-Befehle der Palette (auch die der Module) mit Taste.</summary>
    PaletteCommands: TFunc<TArray<TAtlasCommand>>;
    ExecuteCommand: TProc<string>;
    ShowPalette: TProc;
    /// <summary>Übersicht aller Tastenkürzel (#520).</summary>
    ShowKeyMap: TProc;
    HideSetting: TAtlasHostHideSetting;
    /// <summary>Eigene Snippets für neue Dateien (#759).</summary>
    FileSnippets: TFunc<TAtlasSnippetList>;
    RestartServer: TProc;
    OpenOptions: TProc;
    OpenLogFolder: TProc;
    OpenUpdate: TProc;
    /// <summary>Meldungsansicht der IDE nach vorn holen.</summary>
    ShowMessages: TProc;
    /// <summary>Zeilen des Statusfelds (#591) laufen; die Willkommensseite (#754) beobachtet sie.</summary>
    StatusLinesReady: TFunc<Boolean>;
  end;

  /// <summary>Anfrage an den Server für TAtlasIdeHost.RunRequestAsync: Methode, Parameter als JSON, Zeitgrenze und
  /// Abbruch.</summary>
  TAtlasServerRequest = record
    Method: string;
    ParamsJson: string;
    TimeoutMs: Cardinal;
    Cancelled: TFunc<Boolean>;
    class function Create(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
      const ACancelled: TFunc<Boolean>): TAtlasServerRequest; static;
  end;

  TAtlasIdeHost = class
  private class var
    FServices: TAtlasHostServices;
  public
    class procedure Install(const AServices: TAtlasHostServices); static;
    class procedure Uninstall; static;
    /// <summary>Laufende Serversitzung; nil ohne Server oder nach Uninstall.</summary>
    class function RunningSession: TLspSession; static;
    /// <summary>Sitzung, Server bei Bedarf gestartet; nil, wenn er nicht startet. Nur im Hauptthread.</summary>
    class function ActiveSession: TLspSession; static;
    /// <summary>Zeile in der Meldungsansicht der IDE, Gruppe „Atlas“.</summary>
    class procedure Message(const AText: string); static;
    /// <summary>Fläche, über der ein Popup oder eine Palette erscheint: aktives Formular, sonst Hauptfenster,
    /// sonst Arbeitsfläche.</summary>
    class function PopupArea: TRect; static;
    /// <summary>Warnung wie die der Sicherung: Meldungsansicht und Bericht; vor Install nur die
    /// Meldungsansicht.</summary>
    class procedure Warning(const AText: string); static;
    /// <summary>Zeile im Diagnoselog des Servers; ohne Server nichts.</summary>
    class procedure Log(const AText: string); static;
    /// <summary>Zeile im Bericht des Managers (Diagnose); vor Install nichts.</summary>
    class procedure Report(const AText: string); static;
    /// <summary>Feld AId im Atlas-Statusfeld setzen; leerer Text entfernt es.</summary>
    class procedure SetStatusExtra(const AId, AText: string); static;
    /// <summary>Wie SetStatusExtra mit Hinweis und Klick. Das Modul entfernt sein Feld beim Stoppen (leerer
    /// Text), damit Base keinen Klick des Moduls mehr hält (Regel 3).</summary>
    class procedure SetStatusField(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>); static;
    /// <summary>Zusatzfeld mit Zustand (Punkt in der Atlas-Statusleiste) und Rechtsklick (#1777); leerer Text
    /// entfernt es. Wie bei SetStatusField entfernt das Modul sein Feld beim Stoppen.</summary>
    class procedure SetStatusItem(const AExtra: TAtlasStatusExtra); static;
    /// <summary>Compile-Ereignisse von Base (#527); nil vor Install und nach Uninstall.</summary>
    class function CompileEvents: TAtlasCompileEvents; static;
    /// <summary>Befehl im Hintergrund an den laufenden Server. ADone läuft im Hauptthread, gesichert über AFeature,
    /// und nur, solange AScope offen ist. False = nicht gestartet.</summary>
    class function RunCommandAsync(const AScope: IAtlasModuleScope; AFeature: TAtlasFeature;
      const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean; static;
    /// <summary>Wie RunCommandAsync, aber nebenläufig zu anderen Befehlen: belegt nicht den einen
    /// Hintergrundbefehl, den RunCommandAsync teilt. Startet keinen Server (vorher ActiveSession fragen, wenn er
    /// starten soll). False = nicht gestartet.</summary>
    class function RunServerCommandAsync(const AScope: IAtlasModuleScope; AFeature: TAtlasFeature;
      const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean; static;
    /// <summary>Anfrage im Hintergrund an den laufenden Server (startet keinen), abbrechbar über ACancelled. ADone
    /// läuft im Hauptthread, gesichert über AFeature, und nur, solange AScope offen ist. False = nicht gestartet.
    /// </summary>
    class function RunRequestAsync(const AScope: IAtlasModuleScope; AFeature: TAtlasFeature;
      const ARequest: TAtlasServerRequest; const ADone: TProc<string>): Boolean; static;
    /// <summary>Zustand des Servers; Default ohne Quelle.</summary>
    class function ServerInfo: TAtlasServerInfo; static;
    class function ServerIndexing(out APercent: Integer): Boolean; static;
    class function IndexedUnits: Integer; static;
    /// <summary>Atlas-Befehle der Palette; nil ohne Palette.</summary>
    class function PaletteCommands: TArray<TAtlasCommand>; static;
    /// <summary>Befehl der Palette ausführen; ohne Palette nichts.</summary>
    class procedure ExecuteCommand(const AId: string); static;
    class procedure ShowPalette; static;
    class procedure ShowKeyMap; static;
    class function HideSetting(const AKey: string; APoint: TPoint): Boolean; static;
    class function FileSnippets: TAtlasSnippetList; static;
    class procedure RestartServer; static;
    class procedure OpenOptions; static;
    class procedure OpenLogFolder; static;
    class procedure OpenUpdate; static;
    class procedure ShowMessages; static;
    /// <summary>Laufen die Zeilen des Statusfelds? False vor Install und nach Uninstall.</summary>
    class function StatusLinesReady: Boolean; static;
    /// <summary>Ordner des Base-Packages mit Pfadtrenner am Ende (Regel 8, #1456): Daten, Vorlagen und Doku liegen
    /// dort, auch wenn ein Modul aus einem eigenen Package fragt. Braucht kein Install.</summary>
    class function InstallFolder: string; static;
  end;

implementation

uses
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Modules.Answer;

{ TAtlasServerRequest }

class function TAtlasServerRequest.Create(const AMethod, AParamsJson: string; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>): TAtlasServerRequest;
begin
  Result.Method := AMethod;
  Result.ParamsJson := AParamsJson;
  Result.TimeoutMs := ATimeoutMs;
  Result.Cancelled := ACancelled;
end;

class procedure TAtlasIdeHost.Install(const AServices: TAtlasHostServices);
begin
  FServices := AServices;
end;

class procedure TAtlasIdeHost.Uninstall;
begin
  FServices := Default(TAtlasHostServices);
end;

class function TAtlasIdeHost.RunningSession: TLspSession;
begin
  Result := nil;
  if Assigned(FServices.Session) then
  begin
    Result := FServices.Session();
  end;
end;

class function TAtlasIdeHost.ActiveSession: TLspSession;
begin
  Result := nil;
  if Assigned(FServices.ActiveSession) then
  begin
    Result := FServices.ActiveSession();
  end;
end;

class procedure TAtlasIdeHost.Message(const AText: string);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup('Atlas');
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup('Atlas');
  end;
  mMessages.AddTitleMessage(AText, mGroup);
end;

class function TAtlasIdeHost.PopupArea: TRect;
begin
  if Screen.ActiveForm <> nil then
  begin
    Result := Screen.ActiveForm.BoundsRect;
  end
  else if Application.MainForm <> nil then
  begin
    Result := Application.MainForm.BoundsRect;
  end
  else
  begin
    Result := Screen.WorkAreaRect;
  end;
end;

class procedure TAtlasIdeHost.Warning(const AText: string);
begin
  if Assigned(FServices.Warning) then
  begin
    FServices.Warning(AText);
  end
  else
  begin
    Message(AText);
  end;
end;

class procedure TAtlasIdeHost.Log(const AText: string);
begin
  if Assigned(FServices.Log) then
  begin
    FServices.Log(AText);
  end;
end;

class procedure TAtlasIdeHost.Report(const AText: string);
begin
  if Assigned(FServices.Report) then
  begin
    FServices.Report(AText);
  end;
end;

class procedure TAtlasIdeHost.SetStatusExtra(const AId, AText: string);
begin
  SetStatusField(AId, AText, '', nil);
end;

class procedure TAtlasIdeHost.SetStatusField(const AId, AText, AHint: string; const AOnClick: TProc<TPoint>);
var
  mExtra: TAtlasStatusExtra;
begin
  mExtra := Default(TAtlasStatusExtra);
  mExtra.Id := AId;
  mExtra.Text := AText;
  mExtra.Hint := AHint;
  mExtra.OnClick := AOnClick;
  SetStatusItem(mExtra);
end;

class procedure TAtlasIdeHost.SetStatusItem(const AExtra: TAtlasStatusExtra);
begin
  if Assigned(FServices.StatusExtra) then
  begin
    FServices.StatusExtra(AExtra);
  end;
end;

class function TAtlasIdeHost.CompileEvents: TAtlasCompileEvents;
begin
  Result := nil;
  if Assigned(FServices.CompileEvents) then
  begin
    Result := FServices.CompileEvents();
  end;
end;

class function TAtlasIdeHost.ServerInfo: TAtlasServerInfo;
begin
  Result := Default(TAtlasServerInfo);
  if Assigned(FServices.ServerInfo) then
  begin
    Result := FServices.ServerInfo();
  end;
end;

class function TAtlasIdeHost.ServerIndexing(out APercent: Integer): Boolean;
begin
  APercent := -1;
  Result := Assigned(FServices.ServerIndexing) and FServices.ServerIndexing(APercent);
end;

class function TAtlasIdeHost.IndexedUnits: Integer;
begin
  Result := -1;
  if Assigned(FServices.IndexedUnits) then
  begin
    Result := FServices.IndexedUnits();
  end;
end;

class function TAtlasIdeHost.PaletteCommands: TArray<TAtlasCommand>;
begin
  Result := nil;
  if Assigned(FServices.PaletteCommands) then
  begin
    Result := FServices.PaletteCommands();
  end;
end;

class procedure TAtlasIdeHost.ExecuteCommand(const AId: string);
begin
  if Assigned(FServices.ExecuteCommand) then
  begin
    FServices.ExecuteCommand(AId);
  end;
end;

class procedure TAtlasIdeHost.ShowPalette;
begin
  if Assigned(FServices.ShowPalette) then
  begin
    FServices.ShowPalette();
  end;
end;

class procedure TAtlasIdeHost.ShowKeyMap;
begin
  if Assigned(FServices.ShowKeyMap) then
  begin
    FServices.ShowKeyMap();
  end;
end;

class function TAtlasIdeHost.HideSetting(const AKey: string; APoint: TPoint): Boolean;
begin
  Result := Assigned(FServices.HideSetting) and FServices.HideSetting(AKey, APoint);
end;

class function TAtlasIdeHost.FileSnippets: TAtlasSnippetList;
begin
  Result := nil;
  if Assigned(FServices.FileSnippets) then
  begin
    Result := FServices.FileSnippets();
  end;
end;

class procedure TAtlasIdeHost.RestartServer;
begin
  if Assigned(FServices.RestartServer) then
  begin
    FServices.RestartServer();
  end;
end;

class procedure TAtlasIdeHost.OpenOptions;
begin
  if Assigned(FServices.OpenOptions) then
  begin
    FServices.OpenOptions();
  end;
end;

class procedure TAtlasIdeHost.OpenLogFolder;
begin
  if Assigned(FServices.OpenLogFolder) then
  begin
    FServices.OpenLogFolder();
  end;
end;

class procedure TAtlasIdeHost.OpenUpdate;
begin
  if Assigned(FServices.OpenUpdate) then
  begin
    FServices.OpenUpdate();
  end;
end;

class procedure TAtlasIdeHost.ShowMessages;
begin
  if Assigned(FServices.ShowMessages) then
  begin
    FServices.ShowMessages();
  end;
end;

/// <summary>Weiterreichen in den Hauptthread; eigene Routine, damit der Rahmen nur die Antwort hält.</summary>
function DeliverInMainThread(const AAnswer: IAtlasModuleAnswer; AFeature: TAtlasFeature): TProc<string>;
begin
  Result :=
    procedure(AText: string)
    var
      mText: string;
    begin
      mText := AText;
      TAtlasMainThread.Queue(AFeature,
        procedure
        begin
          AAnswer.Deliver(mText);
        end);
    end;
end;

class function TAtlasIdeHost.RunCommandAsync(const AScope: IAtlasModuleScope; AFeature: TAtlasFeature;
  const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean;
var
  mAnswer: IAtlasModuleAnswer;
begin
  Result := False;
  if not Assigned(FServices.RunCommand) or (AScope = nil) or not AScope.IsOpen then
  begin
    Exit;
  end;
  mAnswer := TAtlasModuleAnswer.Open(AScope, ADone);
  Result := FServices.RunCommand(ACommand, AArgumentsJson, ATimeoutMs, DeliverInMainThread(mAnswer, AFeature));
  // Nicht gestartet: Der Rückruf des Moduls kommt nie, also gleich lösen.
  if not Result then
  begin
    mAnswer.Revoke;
  end;
end;

class function TAtlasIdeHost.RunServerCommandAsync(const AScope: IAtlasModuleScope; AFeature: TAtlasFeature;
  const ACommand, AArgumentsJson: string; ATimeoutMs: Cardinal; const ADone: TProc<string>): Boolean;
var
  mAnswer: IAtlasModuleAnswer;
begin
  Result := False;
  if not Assigned(FServices.RunServerCommand) or (AScope = nil) or not AScope.IsOpen then
  begin
    Exit;
  end;
  mAnswer := TAtlasModuleAnswer.Open(AScope, ADone);
  Result := FServices.RunServerCommand(ACommand, AArgumentsJson, ATimeoutMs, DeliverInMainThread(mAnswer, AFeature));
  if not Result then
  begin
    mAnswer.Revoke;
  end;
end;

class function TAtlasIdeHost.RunRequestAsync(const AScope: IAtlasModuleScope; AFeature: TAtlasFeature;
  const ARequest: TAtlasServerRequest; const ADone: TProc<string>): Boolean;
var
  mAnswer: IAtlasModuleAnswer;
begin
  Result := False;
  if not Assigned(FServices.RunRequest) or (AScope = nil) or not AScope.IsOpen then
  begin
    Exit;
  end;
  mAnswer := TAtlasModuleAnswer.Open(AScope, ADone);
  Result := FServices.RunRequest(ARequest.Method, ARequest.ParamsJson, ARequest.TimeoutMs, ARequest.Cancelled,
    DeliverInMainThread(mAnswer, AFeature));
  if not Result then
  begin
    mAnswer.Revoke;
  end;
end;

class function TAtlasIdeHost.StatusLinesReady: Boolean;
begin
  Result := Assigned(FServices.StatusLinesReady) and FServices.StatusLinesReady();
end;

class function TAtlasIdeHost.InstallFolder: string;
begin
  // HInstance ist hier das Base-Package, weil diese Unit dort liegt.
  Result := ExtractFilePath(GetModuleName(HInstance));
end;

end.
