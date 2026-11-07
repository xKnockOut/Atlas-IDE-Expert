unit Atlas.Core.Diagnostics.Processes;

// „Atlas › Hilfe und Diagnose › Prozesse am Projekt“ (#62): liest die Antwort
// von atlas.server.processes (Index-Cache, Sperre, Stand, angemeldete LSP- und
// MCP-Prozesse, Protokoll) in Datensätze für das Fenster. Dazu die Namen der
// ungespeicherten Dateien: Was die IDE geändert, aber nicht gespeichert hat,
// sieht nur dieser Prozess; ein MCP-Prozess (KI-Assistent) arbeitet mit dem
// gespeicherten Stand, bis die IDE speichert.

interface

uses
  System.SysUtils,
  System.Types,
  System.JSON;

type
  TAtlasProcessRow = record
    Pid: Integer;
    /// <summary>"LSP" oder "MCP".</summary>
    Kind: string;
    Client: string;
    /// <summary>"baut Index", "liest Cache", "bereit" …</summary>
    State: string;
    Writer: Boolean;
    /// <summary>Der Server dieser IDE.</summary>
    Own: Boolean;
    /// <summary>"Client (pid N)"; ohne Client "unbekannter Client (pid N)".</summary>
    function Caption: string;
  end;

  TAtlasProcessLogLine = record
    Time: string;
    Text: string;
  end;

  TAtlasProcessWorkspace = record
    Name: string;
    Project: string;
    /// <summary>Hash-Ordner\Datei.</summary>
    Cache: string;
    Format: Integer;
    /// <summary>"vor 12 s" bzw. "noch nicht gespeichert".</summary>
    Saved: string;
    Units: Integer;
    /// <summary>"LSP · Client (pid N)"; '' = frei.</summary>
    LockHolder: string;
    BuiltOnce: Boolean;
    Processes: TArray<TAtlasProcessRow>;
    Events: TArray<TAtlasProcessLogLine>;
    /// <summary>Ein MCP-Prozess ist angemeldet.</summary>
    function HasMcp: Boolean;
  end;

  TAtlasProcessesView = class
  public const
    /// <summary>Befehl des Servers (Atlas.Common.Lsp.Processes).</summary>
    cCommand = 'atlas.server.processes';
  private
    class function ParseRows(const AList: TJSONValue): TArray<TAtlasProcessRow>; static;
    class function ParseEvents(const AList: TJSONValue): TArray<TAtlasProcessLogLine>; static;
    class function ParseWorkspace(const AItem: TJSONObject): TAtlasProcessWorkspace; static;
  public
    /// <summary>Arbeitsbereiche aus der Antwort; leer bei nil oder unbekanntem Format.</summary>
    class function Parse(const AAnswer: TJSONValue): TArray<TAtlasProcessWorkspace>; static;
    /// <summary>Markdown der Antwort für die Meldungsansicht; '' ohne.</summary>
    class function Markdown(const AAnswer: TJSONValue): string; static;
    /// <summary>Gruppe für den Fenstertitel: Name des ersten Arbeitsbereichs; '' ohne.</summary>
    class function GroupName(const AWorkspaces: TArray<TAtlasProcessWorkspace>): string; static;
    /// <summary>Alle Prozesse aller Arbeitsbereiche (für die Zählung im Fuß).</summary>
    class function ProcessCount(const AWorkspaces: TArray<TAtlasProcessWorkspace>): Integer; static;
    /// <summary>Dateinamen ohne Pfad der ungespeicherten Dateien, sortiert und ohne Doppelte.</summary>
    class function DirtyNames(const AModifiedFiles: TArray<string>): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Classes;

{ TAtlasProcessRow }

function TAtlasProcessRow.Caption: string;
var
  mName: string;
begin
  mName := Client;
  if mName = '' then
  begin
    mName := 'unbekannter Client';
  end;
  Result := System.SysUtils.Format('%s (pid %d)', [mName, Pid]);
end;

{ TAtlasProcessWorkspace }

function TAtlasProcessWorkspace.HasMcp: Boolean;
var
  mRow: TAtlasProcessRow;
begin
  for mRow in Processes do
  begin
    if SameText(mRow.Kind, 'MCP') then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasProcessesView }

class function TAtlasProcessesView.ParseRows(const AList: TJSONValue): TArray<TAtlasProcessRow>;
var
  mEntry: TJSONValue;
  mRow: TAtlasProcessRow;
begin
  Result := nil;
  if not (AList is TJSONArray) then
  begin
    Exit;
  end;
  for mEntry in TJSONArray(AList) do
  begin
    if mEntry is TJSONObject then
    begin
      mRow.Pid := TJSONObject(mEntry).GetValue<Integer>('pid', 0);
      mRow.Kind := TJSONObject(mEntry).GetValue<string>('kind', '');
      mRow.Client := TJSONObject(mEntry).GetValue<string>('client', '');
      mRow.State := TJSONObject(mEntry).GetValue<string>('state', '');
      mRow.Writer := TJSONObject(mEntry).GetValue<Boolean>('writer', False);
      mRow.Own := TJSONObject(mEntry).GetValue<Boolean>('own', False);
      Result := Result + [mRow];
    end;
  end;
end;

class function TAtlasProcessesView.ParseEvents(const AList: TJSONValue): TArray<TAtlasProcessLogLine>;
var
  mEntry: TJSONValue;
  mLine: TAtlasProcessLogLine;
begin
  Result := nil;
  if not (AList is TJSONArray) then
  begin
    Exit;
  end;
  for mEntry in TJSONArray(AList) do
  begin
    if mEntry is TJSONObject then
    begin
      mLine.Time := TJSONObject(mEntry).GetValue<string>('time', '');
      mLine.Text := TJSONObject(mEntry).GetValue<string>('text', '');
      Result := Result + [mLine];
    end;
  end;
end;

class function TAtlasProcessesView.ParseWorkspace(const AItem: TJSONObject): TAtlasProcessWorkspace;
begin
  Result := Default(TAtlasProcessWorkspace);
  Result.Name := AItem.GetValue<string>('name', '');
  Result.Project := AItem.GetValue<string>('project', '');
  Result.Cache := AItem.GetValue<string>('cache', '');
  Result.Format := AItem.GetValue<Integer>('format', 0);
  Result.Saved := AItem.GetValue<string>('saved', '');
  Result.Units := AItem.GetValue<Integer>('units', 0);
  Result.LockHolder := AItem.GetValue<string>('lockHolder', '');
  Result.BuiltOnce := AItem.GetValue<Boolean>('builtOnce', False);
  Result.Processes := ParseRows(AItem.GetValue('processes'));
  Result.Events := ParseEvents(AItem.GetValue('events'));
end;

class function TAtlasProcessesView.Parse(const AAnswer: TJSONValue): TArray<TAtlasProcessWorkspace>;
var
  mItems, mItem: TJSONValue;
begin
  Result := nil;
  if not (AAnswer is TJSONObject) then
  begin
    Exit;
  end;
  mItems := TJSONObject(AAnswer).GetValue('workspaces');
  if not (mItems is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(mItems) do
  begin
    if mItem is TJSONObject then
    begin
      Result := Result + [ParseWorkspace(TJSONObject(mItem))];
    end;
  end;
end;

class function TAtlasProcessesView.Markdown(const AAnswer: TJSONValue): string;
begin
  Result := '';
  if AAnswer is TJSONObject then
  begin
    Result := TJSONObject(AAnswer).GetValue<string>('markdown', '');
  end;
end;

class function TAtlasProcessesView.GroupName(const AWorkspaces: TArray<TAtlasProcessWorkspace>): string;
begin
  Result := '';
  if Length(AWorkspaces) > 0 then
  begin
    Result := AWorkspaces[0].Name;
  end;
end;

class function TAtlasProcessesView.ProcessCount(const AWorkspaces: TArray<TAtlasProcessWorkspace>): Integer;
var
  mWorkspace: TAtlasProcessWorkspace;
begin
  Result := 0;
  for mWorkspace in AWorkspaces do
  begin
    Inc(Result, Length(mWorkspace.Processes));
  end;
end;

class function TAtlasProcessesView.DirtyNames(const AModifiedFiles: TArray<string>): TArray<string>;
var
  mNames: TStringList;
  mFileName: string;
  mIndex: Integer;
begin
  mNames := TStringList.Create;
  try
    mNames.Sorted := True;
    mNames.Duplicates := dupIgnore;
    mNames.CaseSensitive := False;
    for mFileName in AModifiedFiles do
    begin
      if mFileName <> '' then
      begin
        mNames.Add(ExtractFileName(mFileName));
      end;
    end;
    SetLength(Result, mNames.Count);
    for mIndex := 0 to mNames.Count - 1 do
    begin
      Result[mIndex] := mNames[mIndex];
    end;
  finally
    mNames.Free;
  end;
end;

end.
