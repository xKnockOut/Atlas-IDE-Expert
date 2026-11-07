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
  cProcessesCommand = 'atlas.server.processes';

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
  mProcess: TIndexProcessInfo;
begin
  for mProcess in Processes do
  begin
    if mProcess.Writer then
    begin
      AProcess := mProcess;
      Exit(True);
    end;
  end;
  AProcess := Default(TIndexProcessInfo);
  Result := False;
end;

function TLspProcessWorkspace.BuiltOnce: Boolean;
var
  mProcess: TIndexProcessInfo;
  mWriters: Integer;
begin
  mWriters := 0;
  for mProcess in Processes do
  begin
    if mProcess.Writer then
    begin
      Inc(mWriters);
    end;
  end;
  Result := (mWriters = 1) and (Length(Processes) > 1);
end;

{ TLspProcesses }

class function TLspProcesses.Age(ASaved, ANow: TDateTime): string;
var
  mSeconds: Int64;
begin
  if ASaved = 0 then
  begin
    Exit(cTexts[TProcessesText.NotSavedYet].Text);
  end;
  mSeconds := SecondsBetween(ANow, ASaved);
  if mSeconds < 60 then
  begin
    Result := Format('vor %d s', [mSeconds]);
  end
  else if mSeconds < 3600 then
  begin
    Result := Format('vor %d min', [mSeconds div 60]);
  end
  else if mSeconds < 86400 then
  begin
    Result := Format('vor %d h', [mSeconds div 3600]);
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
  if AState = TIndexProcessInfo.cStateBuilding then
  begin
    Result := cTexts[TProcessesText.StateBuilding].Text;
  end
  else if AState = TIndexProcessInfo.cStateReading then
  begin
    Result := cTexts[TProcessesText.StateReading].Text;
  end
  else if AState = TIndexProcessInfo.cStateReady then
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
  mClient: string;
begin
  mClient := AProcess.Client;
  if mClient = '' then
  begin
    mClient := cTexts[TProcessesText.UnknownClient].Text;
  end;
  Result := Format('%s · %s (pid %d)', [AProcess.Kind, mClient, AProcess.Pid]);
end;

class function TLspProcesses.ToMarkdown(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
  ANow: TDateTime): string;
begin
  Result := TLogMarks.Plain(MarkedMarkdown(AWorkspaces, AOwnPid, ANow));
end;

class function TLspProcesses.MarkedMarkdown(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
  ANow: TDateTime): string;
var
  mBuilder: TStringBuilder;
  mWorkspace: TLspProcessWorkspace;
  mProcess, mHolder: TIndexProcessInfo;
  mEvent: TIndexProcessEvent;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(cTexts[TProcessesText.ProcessesOnTheProject].Text).Append(#10);
    if Length(AWorkspaces) = 0 then
    begin
      mBuilder.Append(#10).Append(cTexts[TProcessesText.NoIndexCacheNoProject].Text).Append(#10);
    end;
    for mWorkspace in AWorkspaces do
    begin
      mBuilder.Append(#10).Append('### ').Append(TLogMarks.Name(mWorkspace.Name)).Append(#10);
      mBuilder.Append('- Index-Cache: ').Append(TLogMarks.Path(mWorkspace.CacheName)).Append(#10);
      if mWorkspace.Holder(mHolder) then
      begin
        mBuilder.Append(cTexts[TProcessesText.Lock].Text).Append(ProcessText(mHolder))
          .Append(cTexts[TProcessesText.Writes].Text).Append(#10);
      end
      else
      begin
        mBuilder.Append(cTexts[TProcessesText.LockFree].Text).Append(#10);
      end;
      mBuilder.Append(cTexts[TProcessesText.StateSavedFormatUnits].Fmt([Age(mWorkspace.Saved, ANow),
        mWorkspace.FormatVersion, mWorkspace.Units]));
      mBuilder.Append(#10);
      for mProcess in mWorkspace.Processes do
      begin
        mBuilder.Append('- ').Append(ProcessText(mProcess)).Append(': ').Append(StateText(mProcess.State));
        if mProcess.Pid = AOwnPid then
        begin
          mBuilder.Append(cTexts[TProcessesText.ThisProcess].Text);
        end;
        mBuilder.Append(#10);
      end;
      if mWorkspace.BuiltOnce then
      begin
        mBuilder.Append(cTexts[TProcessesText.IndexBuiltOnlyOnceProcesses].Fmt([Length(mWorkspace.Processes)]))
          .Append(#10);
      end;
      for mEvent in TIndexProcessLog.Events(mWorkspace.Processes) do
      begin
        mBuilder.Append('  - ').Append(FormatDateTime('hh":"nn":"ss', mEvent.Time)).Append(' ').Append(mEvent.Text)
          .Append(#10);
      end;
    end;
    mBuilder.Append(#10).Append(cTexts[TProcessesText.UnsavedStatesStaySeparatePer].Text).Append(#10);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

class function TLspProcesses.ToJson(const AWorkspaces: TArray<TLspProcessWorkspace>; AOwnPid: Cardinal;
  ANow: TDateTime): TJSONObject;
var
  mItems, mProcesses, mEvents: TJSONArray;
  mItem, mEntry: TJSONObject;
  mWorkspace: TLspProcessWorkspace;
  mProcess, mHolder: TIndexProcessInfo;
  mEvent: TIndexProcessEvent;
begin
  Result := TJSONObject.Create;
  mItems := TJSONArray.Create;
  Result.AddPair('workspaces', mItems);
  for mWorkspace in AWorkspaces do
  begin
    mItem := TJSONObject.Create;
    mItems.AddElement(mItem);
    mItem.AddPair('name', mWorkspace.Name);
    mItem.AddPair('project', mWorkspace.Project);
    mItem.AddPair('cache', mWorkspace.CacheName);
    mItem.AddPair('format', TJSONNumber.Create(mWorkspace.FormatVersion));
    mItem.AddPair('saved', Age(mWorkspace.Saved, ANow));
    mItem.AddPair('units', TJSONNumber.Create(mWorkspace.Units));
    if mWorkspace.Holder(mHolder) then
    begin
      mItem.AddPair('lockHolder', ProcessText(mHolder));
    end
    else
    begin
      mItem.AddPair('lockHolder', '');
    end;
    mItem.AddPair('builtOnce', TJSONBool.Create(mWorkspace.BuiltOnce));
    mProcesses := TJSONArray.Create;
    mItem.AddPair('processes', mProcesses);
    for mProcess in mWorkspace.Processes do
    begin
      mEntry := TJSONObject.Create;
      mProcesses.AddElement(mEntry);
      mEntry.AddPair('pid', TJSONNumber.Create(mProcess.Pid));
      mEntry.AddPair('kind', mProcess.Kind);
      mEntry.AddPair('client', mProcess.Client);
      mEntry.AddPair('state', mProcess.State);
      mEntry.AddPair('writer', TJSONBool.Create(mProcess.Writer));
      mEntry.AddPair('own', TJSONBool.Create(mProcess.Pid = AOwnPid));
    end;
    mEvents := TJSONArray.Create;
    mItem.AddPair('events', mEvents);
    for mEvent in TIndexProcessLog.Events(mWorkspace.Processes) do
    begin
      mEntry := TJSONObject.Create;
      mEvents.AddElement(mEntry);
      mEntry.AddPair('time', FormatDateTime('hh":"nn":"ss', mEvent.Time));
      mEntry.AddPair('text', mEvent.Text);
    end;
  end;
  Result.AddPair('markdown', ToMarkdown(AWorkspaces, AOwnPid, ANow));
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Processes', cTexts);

end.
