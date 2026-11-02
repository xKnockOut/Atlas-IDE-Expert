unit Atlas.Core.Diagnostics.Processes;

// „Atlas › Hilfe und Diagnose › Prozesse am Projekt“ (#62): liest die Antwort
// von atlas.server.processes (Index-Cache, Sperre, Stand, angemeldete LSP- und
// MCP-Prozesse, Protokoll) in Datensätze für das Fenster. Dazu die Namen der
// ungespeicherten Dateien: Was die IDE geändert, aber nicht gespeichert hat,
// sieht nur dieser Prozess; ein MCP-Prozess (Claude Code) arbeitet mit dem
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
    Command = 'atlas.server.processes';
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
  Name: string;
begin
  Name := Client;
  if Name = '' then
    Name := 'unbekannter Client';
  Result := System.SysUtils.Format('%s (pid %d)', [Name, Pid]);
end;

{ TAtlasProcessWorkspace }

function TAtlasProcessWorkspace.HasMcp: Boolean;
var
  Row: TAtlasProcessRow;
begin
  for Row in Processes do
    if SameText(Row.Kind, 'MCP') then
      Exit(True);
  Result := False;
end;

{ TAtlasProcessesView }

class function TAtlasProcessesView.Parse(const AAnswer: TJSONValue): TArray<TAtlasProcessWorkspace>;
var
  Items, List: TJSONValue;
  Item, Entry: TJSONValue;
  Workspace: TAtlasProcessWorkspace;
  Row: TAtlasProcessRow;
  Line: TAtlasProcessLogLine;
begin
  Result := nil;
  if not (AAnswer is TJSONObject) then
    Exit;
  Items := TJSONObject(AAnswer).GetValue('workspaces');
  if not (Items is TJSONArray) then
    Exit;
  for Item in TJSONArray(Items) do
  begin
    if not (Item is TJSONObject) then
      Continue;
    Workspace := Default(TAtlasProcessWorkspace);
    Workspace.Name := TJSONObject(Item).GetValue<string>('name', '');
    Workspace.Project := TJSONObject(Item).GetValue<string>('project', '');
    Workspace.Cache := TJSONObject(Item).GetValue<string>('cache', '');
    Workspace.Format := TJSONObject(Item).GetValue<Integer>('format', 0);
    Workspace.Saved := TJSONObject(Item).GetValue<string>('saved', '');
    Workspace.Units := TJSONObject(Item).GetValue<Integer>('units', 0);
    Workspace.LockHolder := TJSONObject(Item).GetValue<string>('lockHolder', '');
    Workspace.BuiltOnce := TJSONObject(Item).GetValue<Boolean>('builtOnce', False);
    List := TJSONObject(Item).GetValue('processes');
    if List is TJSONArray then
      for Entry in TJSONArray(List) do
        if Entry is TJSONObject then
        begin
          Row.Pid := TJSONObject(Entry).GetValue<Integer>('pid', 0);
          Row.Kind := TJSONObject(Entry).GetValue<string>('kind', '');
          Row.Client := TJSONObject(Entry).GetValue<string>('client', '');
          Row.State := TJSONObject(Entry).GetValue<string>('state', '');
          Row.Writer := TJSONObject(Entry).GetValue<Boolean>('writer', False);
          Row.Own := TJSONObject(Entry).GetValue<Boolean>('own', False);
          Workspace.Processes := Workspace.Processes + [Row];
        end;
    List := TJSONObject(Item).GetValue('events');
    if List is TJSONArray then
      for Entry in TJSONArray(List) do
        if Entry is TJSONObject then
        begin
          Line.Time := TJSONObject(Entry).GetValue<string>('time', '');
          Line.Text := TJSONObject(Entry).GetValue<string>('text', '');
          Workspace.Events := Workspace.Events + [Line];
        end;
    Result := Result + [Workspace];
  end;
end;

class function TAtlasProcessesView.Markdown(const AAnswer: TJSONValue): string;
begin
  Result := '';
  if AAnswer is TJSONObject then
    Result := TJSONObject(AAnswer).GetValue<string>('markdown', '');
end;

class function TAtlasProcessesView.GroupName(const AWorkspaces: TArray<TAtlasProcessWorkspace>): string;
begin
  Result := '';
  if Length(AWorkspaces) > 0 then
    Result := AWorkspaces[0].Name;
end;

class function TAtlasProcessesView.ProcessCount(const AWorkspaces: TArray<TAtlasProcessWorkspace>): Integer;
var
  Workspace: TAtlasProcessWorkspace;
begin
  Result := 0;
  for Workspace in AWorkspaces do
    Inc(Result, Length(Workspace.Processes));
end;

class function TAtlasProcessesView.DirtyNames(const AModifiedFiles: TArray<string>): TArray<string>;
var
  Names: TStringList;
  FileName: string;
  Index: Integer;
begin
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    Names.CaseSensitive := False;
    for FileName in AModifiedFiles do
      if FileName <> '' then
        Names.Add(ExtractFileName(FileName));
    SetLength(Result, Names.Count);
    for Index := 0 to Names.Count - 1 do
      Result[Index] := Names[Index];
  finally
    Names.Free;
  end;
end;

end.
