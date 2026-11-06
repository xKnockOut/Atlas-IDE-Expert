unit Atlas.Common.Lsp.Processes;

// Befehl atlas.server.processes (#62) für „Atlas › Diagnose › Prozesse am
// Projekt“: je Arbeitsbereich der Index-Cache (Ordner\Datei, Format, Stand),
// wer die Sperre hält, die angemeldeten Prozesse und ihre Sperr- und
// Cache-Ereignisse nach Zeit. Die Antwort trägt dazu "markdown" für die
// Meldungsansicht und das Log. Fürs Log kennzeichnet MarkedMarkdown Namen
// der Arbeitsbereiche und Caches (#1478), damit sie dort anonym stehen.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.Processes;

const
  ProcessesCommand = 'atlas.server.processes';

type
  TLspProcessWorkspace = record
    Name: string;
    /// <summary>.dproj; '' ohne Projekt.</summary>
    Project: string;
    CacheFile: string;
    FormatVersion: Integer;
    /// <summary>Letztes Schreiben der Cache-Datei; 0 = noch keine.</summary>
    Saved: TDateTime;
    Units: Integer;
    Processes: TArray<TIndexProcessInfo>;
    /// <summary>Kurzname der Cache-Datei: Hash-Ordner\Datei.</summary>
    function CacheName: string;
    /// <summary>Prozess mit der Sperre; False, wenn keiner sie hält.</summary>
    function Holder(out AProcess: TIndexProcessInfo): Boolean;
    /// <summary>Genau ein Schreiber und alle anderen lesen: Der Index wurde nur einmal aufgebaut.</summary>
    function BuiltOnce: Boolean;
  end;

  TLspProcesses = class
  public
    /// <summary>"vor 12 s", "vor 3 min", "vor 2 h" bzw. Datum; ANow ist die Bezugszeit.</summary>
    class function Age(ASaved, ANow: TDateTime): string; static;
    /// <summary>"LSP · Atlas IDE Expert (pid 4711)".</summary>
    class function ProcessText(const AProcess: TIndexProcessInfo): string; static;
    /// <summary>Wie ToMarkdown, Arbeitsbereich und Cache gekennzeichnet (Atlas.Text.LogMarks), fürs Log.</summary>
    class function MarkedMarkdown(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
      ANow: TDateTime): string; static;
    class function ToMarkdown(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
      ANow: TDateTime): string; static;
    class function ToJson(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
      ANow: TDateTime): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.DateUtils,
  System.Classes,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TProcessesText = (NotSavedYet, NoIndexCacheNoProject, UnsavedStatesStaySeparatePer, ProcessesOnTheProject,
    StateSavedFormatUnits, IndexBuiltOnlyOnceProcesses, UnknownClient, Lock, Writes, LockFree, ThisProcess,
    StateBuilding, StateReading, StateReady);

const
  cTexts: array[TProcessesText] of TAtlasText = (
    (De: 'noch nicht gespeichert'; En: 'not saved yet'),
    (De: 'Kein Index-Cache: Es ist noch kein Projekt geladen.'; En: 'No index cache: no project is loaded yet.'),
    (De: 'Ungespeicherte Stände bleiben je Prozess getrennt: Andere Prozesse sehen den gespeicherten Stand, bis der ' +
      'Editor speichert.';
     En: 'Unsaved states stay separate per process: other processes see the saved state until the editor saves.'),
    (De: '## Prozesse am Projekt'; En: '## Processes on the project'),
    (De: '- Stand: %s gespeichert · Format %d · %d Units'; En: '- State: %s saved · format %d · %d units'),
    (De: '- Index nur einmal aufgebaut, %d Prozesse'; En: '- Index built only once, %d processes'),
    (De: 'unbekannter Client'; En: 'unknown client'),
    (De: '- Sperre: '; En: '- Lock: '),
    (De: ', schreibt'; En: ', writes'),
    (De: '- Sperre: frei'; En: '- Lock: free'),
    (De: ' (dieser Prozess)'; En: ' (this process)'),
    (De: 'baut Index'; En: 'building the index'),
    (De: 'liest Cache'; En: 'reading the cache'),
    (De: 'bereit'; En: 'ready'));

{$SCOPEDENUMS OFF}

{ TLspProcessWorkspace }

function TLspProcessWorkspace.CacheName: string;
begin
  Result := '';
  if CacheFile <> '' then
  begin
    Result := ExtractFileName(ExtractFileDir(CacheFile)) + PathDelim + ExtractFileName(CacheFile);
  end;
end;

function TLspProcessWorkspace.Holder(out AProcess: TIndexProcessInfo): Boolean;
var
  Process: TIndexProcessInfo;
begin
  for Process in Processes do
  begin
    if Process.Writer then
    begin
      AProcess := Process;
      Exit(True);
    end;
  end;
  AProcess := Default(TIndexProcessInfo);
  Result := False;
end;

function TLspProcessWorkspace.BuiltOnce: Boolean;
var
  Process: TIndexProcessInfo;
  Writers: Integer;
begin
  Writers := 0;
  for Process in Processes do
  begin
    if Process.Writer then
    begin
      Inc(Writers);
    end;
  end;
  Result := (Writers = 1) and (Length(Processes) > 1);
end;

{ TLspProcesses }

class function TLspProcesses.Age(ASaved, ANow: TDateTime): string;
var
  Seconds: Int64;
begin
  if ASaved = 0 then
  begin
    Exit(cTexts[TProcessesText.NotSavedYet].Text);
  end;
  Seconds := SecondsBetween(ANow, ASaved);
  if Seconds < 60 then
  begin
    Result := Format('vor %d s', [Seconds]);
  end
  else if Seconds < 3600 then
  begin
    Result := Format('vor %d min', [Seconds div 60]);
  end
  else if Seconds < 86400 then
  begin
    Result := Format('vor %d h', [Seconds div 3600]);
  end
  else
  begin
    Result := 'am ' + FormatDateTime('dd.mm.yyyy hh":"nn', ASaved);
  end;
end;

/// <summary>Zustand in der Sprache von Atlas; der Zustand selbst steht als fester Wert in der Prozessliste, die
/// sich mehrere Prozesse teilen.</summary>
function StateText(const AState: string): string;
begin
  if AState = TIndexProcessInfo.StateBuilding then
  begin
    Result := cTexts[TProcessesText.StateBuilding].Text;
  end
  else if AState = TIndexProcessInfo.StateReading then
  begin
    Result := cTexts[TProcessesText.StateReading].Text;
  end
  else if AState = TIndexProcessInfo.StateReady then
  begin
    Result := cTexts[TProcessesText.StateReady].Text;
  end
  else
  begin
    Result := AState;
  end;
end;

class function TLspProcesses.ProcessText(const AProcess: TIndexProcessInfo): string;
var
  Client: string;
begin
  Client := AProcess.Client;
  if Client = '' then
  begin
    Client := cTexts[TProcessesText.UnknownClient].Text;
  end;
  Result := Format('%s · %s (pid %d)', [AProcess.Kind, Client, AProcess.Pid]);
end;

class function TLspProcesses.ToMarkdown(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
  ANow: TDateTime): string;
begin
  Result := TLogMarks.Plain(MarkedMarkdown(AWorkspaces, AOwnPid, ANow));
end;

class function TLspProcesses.MarkedMarkdown(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
  ANow: TDateTime): string;
var
  Builder: TStringBuilder;
  Workspace: TLspProcessWorkspace;
  Process, Holder: TIndexProcessInfo;
  Event: TIndexProcessEvent;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append(cTexts[TProcessesText.ProcessesOnTheProject].Text).Append(#10);
    if Length(AWorkspaces) = 0 then
    begin
      Builder.Append(#10).Append(cTexts[TProcessesText.NoIndexCacheNoProject].Text).Append(#10);
    end;
    for Workspace in AWorkspaces do
    begin
      Builder.Append(#10).Append('### ').Append(TLogMarks.Name(Workspace.Name)).Append(#10);
      Builder.Append('- Index-Cache: ').Append(TLogMarks.Path(Workspace.CacheName)).Append(#10);
      if Workspace.Holder(Holder) then
      begin
        Builder.Append(cTexts[TProcessesText.Lock].Text).Append(ProcessText(Holder))
          .Append(cTexts[TProcessesText.Writes].Text).Append(#10);
      end
      else
      begin
        Builder.Append(cTexts[TProcessesText.LockFree].Text).Append(#10);
      end;
      Builder.Append(cTexts[TProcessesText.StateSavedFormatUnits].Fmt([Age(Workspace.Saved, ANow),
        Workspace.FormatVersion, Workspace.Units]));
      Builder.Append(#10);
      for Process in Workspace.Processes do
      begin
        Builder.Append('- ').Append(ProcessText(Process)).Append(': ').Append(StateText(Process.State));
        if Process.Pid = AOwnPid then
        begin
          Builder.Append(cTexts[TProcessesText.ThisProcess].Text);
        end;
        Builder.Append(#10);
      end;
      if Workspace.BuiltOnce then
      begin
        Builder.Append(cTexts[TProcessesText.IndexBuiltOnlyOnceProcesses].Fmt([Length(Workspace.Processes)]))
          .Append(#10);
      end;
      for Event in TIndexProcessLog.Events(Workspace.Processes) do
      begin
        Builder.Append('  - ').Append(FormatDateTime('hh":"nn":"ss', Event.Time)).Append(' ').Append(Event.Text)
          .Append(#10);
      end;
    end;
    Builder.Append(#10).Append(cTexts[TProcessesText.UnsavedStatesStaySeparatePer].Text).Append(#10);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

class function TLspProcesses.ToJson(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
  ANow: TDateTime): TJSONObject;
var
  Items, Processes, Events: TJSONArray;
  Item, Entry: TJSONObject;
  Workspace: TLspProcessWorkspace;
  Process, Holder: TIndexProcessInfo;
  Event: TIndexProcessEvent;
begin
  Result := TJSONObject.Create;
  Items := TJSONArray.Create;
  Result.AddPair('workspaces', Items);
  for Workspace in AWorkspaces do
  begin
    Item := TJSONObject.Create;
    Items.AddElement(Item);
    Item.AddPair('name', Workspace.Name);
    Item.AddPair('project', Workspace.Project);
    Item.AddPair('cache', Workspace.CacheName);
    Item.AddPair('format', TJSONNumber.Create(Workspace.FormatVersion));
    Item.AddPair('saved', Age(Workspace.Saved, ANow));
    Item.AddPair('units', TJSONNumber.Create(Workspace.Units));
    if Workspace.Holder(Holder) then
    begin
      Item.AddPair('lockHolder', ProcessText(Holder));
    end
    else
    begin
      Item.AddPair('lockHolder', '');
    end;
    Item.AddPair('builtOnce', TJSONBool.Create(Workspace.BuiltOnce));
    Processes := TJSONArray.Create;
    Item.AddPair('processes', Processes);
    for Process in Workspace.Processes do
    begin
      Entry := TJSONObject.Create;
      Processes.AddElement(Entry);
      Entry.AddPair('pid', TJSONNumber.Create(Process.Pid));
      Entry.AddPair('kind', Process.Kind);
      Entry.AddPair('client', Process.Client);
      Entry.AddPair('state', Process.State);
      Entry.AddPair('writer', TJSONBool.Create(Process.Writer));
      Entry.AddPair('own', TJSONBool.Create(Process.Pid = AOwnPid));
    end;
    Events := TJSONArray.Create;
    Item.AddPair('events', Events);
    for Event in TIndexProcessLog.Events(Workspace.Processes) do
    begin
      Entry := TJSONObject.Create;
      Events.AddElement(Entry);
      Entry.AddPair('time', FormatDateTime('hh":"nn":"ss', Event.Time));
      Entry.AddPair('text', Event.Text);
    end;
  end;
  Result.AddPair('markdown', ToMarkdown(AWorkspaces, AOwnPid, ANow));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Processes', cTexts);

end.
