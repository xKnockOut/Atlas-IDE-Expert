unit Atlas.Common.Lsp.Processes;

// Befehl atlas.server.processes (#62) für „Atlas › Diagnose › Prozesse am
// Projekt“: je Arbeitsbereich der Index-Cache (Ordner\Datei, Format, Stand),
// wer die Sperre hält, die angemeldeten Prozesse und ihre Sperr- und
// Cache-Ereignisse nach Zeit. Die Antwort trägt dazu "markdown" für die
// Meldungsansicht und das Log.

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
    class function ToMarkdown(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
      ANow: TDateTime): string; static;
    class function ToJson(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
      ANow: TDateTime): TJSONObject; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.DateUtils,
  System.Classes;

{ TLspProcessWorkspace }

function TLspProcessWorkspace.CacheName: string;
begin
  Result := '';
  if CacheFile <> '' then
    Result := ExtractFileName(ExtractFileDir(CacheFile)) + PathDelim + ExtractFileName(CacheFile);
end;

function TLspProcessWorkspace.Holder(out AProcess: TIndexProcessInfo): Boolean;
var
  Process: TIndexProcessInfo;
begin
  for Process in Processes do
    if Process.Writer then
    begin
      AProcess := Process;
      Exit(True);
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
    if Process.Writer then
      Inc(Writers);
  Result := (Writers = 1) and (Length(Processes) > 1);
end;

{ TLspProcesses }

class function TLspProcesses.Age(ASaved, ANow: TDateTime): string;
var
  Seconds: Int64;
begin
  if ASaved = 0 then
    Exit('noch nicht gespeichert');
  Seconds := SecondsBetween(ANow, ASaved);
  if Seconds < 60 then
    Result := Format('vor %d s', [Seconds])
  else if Seconds < 3600 then
    Result := Format('vor %d min', [Seconds div 60])
  else if Seconds < 86400 then
    Result := Format('vor %d h', [Seconds div 3600])
  else
    Result := 'am ' + FormatDateTime('dd.mm.yyyy hh":"nn', ASaved);
end;

class function TLspProcesses.ProcessText(const AProcess: TIndexProcessInfo): string;
var
  Client: string;
begin
  Client := AProcess.Client;
  if Client = '' then
    Client := 'unbekannter Client';
  Result := Format('%s · %s (pid %d)', [AProcess.Kind, Client, AProcess.Pid]);
end;

class function TLspProcesses.ToMarkdown(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
  ANow: TDateTime): string;
var
  Builder: TStringBuilder;
  Workspace: TLspProcessWorkspace;
  Process, Holder: TIndexProcessInfo;
  Event: TIndexProcessEvent;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('## Prozesse am Projekt').Append(#10);
    if Length(AWorkspaces) = 0 then
      Builder.Append(#10).Append('Kein Index-Cache: Es ist noch kein Projekt geladen.').Append(#10);
    for Workspace in AWorkspaces do
    begin
      Builder.Append(#10).Append('### ').Append(Workspace.Name).Append(#10);
      Builder.Append('- Index-Cache: ').Append(Workspace.CacheName).Append(#10);
      if Workspace.Holder(Holder) then
        Builder.Append('- Sperre: ').Append(ProcessText(Holder)).Append(', schreibt').Append(#10)
      else
        Builder.Append('- Sperre: frei').Append(#10);
      Builder.Append(Format('- Stand: %s gespeichert · Format %d · %d Units',
        [Age(Workspace.Saved, ANow), Workspace.FormatVersion, Workspace.Units]));
      Builder.Append(#10);
      for Process in Workspace.Processes do
      begin
        Builder.Append('- ').Append(ProcessText(Process)).Append(': ').Append(Process.State);
        if Process.Pid = AOwnPid then
          Builder.Append(' (dieser Prozess)');
        Builder.Append(#10);
      end;
      if Workspace.BuiltOnce then
        Builder.Append(Format('- Index nur einmal aufgebaut, %d Prozesse', [Length(Workspace.Processes)]))
          .Append(#10);
      for Event in TIndexProcessLog.Events(Workspace.Processes) do
        Builder.Append('  - ').Append(FormatDateTime('hh":"nn":"ss', Event.Time)).Append(' ').Append(Event.Text)
          .Append(#10);
    end;
    Builder.Append(#10).Append('Ungespeicherte Stände bleiben je Prozess getrennt: Andere Prozesse sehen den ' +
      'gespeicherten Stand, bis der Editor speichert.').Append(#10);
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
      Item.AddPair('lockHolder', ProcessText(Holder))
    else
      Item.AddPair('lockHolder', '');
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

end.
