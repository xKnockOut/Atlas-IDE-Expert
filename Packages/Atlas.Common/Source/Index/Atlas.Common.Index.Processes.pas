unit Atlas.Common.Index.Processes;

// Anmeldung eines Server-Prozesses an einem Index-Cache (#62) als Datensatz:
// Art (LSP, MCP), Client, Zustand ("baut Index", "liest Cache", "bereit"), ob
// er die Cache-Sperre hält, und seine letzten Sperr- und Cache-Ereignisse; dazu
// das Zusammenführen der Ereignisse aller Prozesse nach Zeit. Dateien und
// Sperren liegen in Atlas.Common.Index.Adapters.Processes.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  TIndexProcessEvent = record
    Time: TDateTime;
    Text: string;
  end;

  TIndexProcessInfo = record
  public const
    StateBuilding = 'baut Index';
    StateReading = 'liest Cache';
    StateReady = 'bereit';
    KindLsp = 'LSP';
    KindMcp = 'MCP';
    /// <summary>Kommandozeilen-Linter --check mit Symbolindex (#1112).</summary>
    KindCheck = 'Check';
  public
    Pid: Cardinal;
    /// <summary>KindLsp, KindMcp oder KindCheck.</summary>
    Kind: string;
    /// <summary>Name des Clients aus initialize (z. B. "Atlas IDE Expert"); '' = unbekannt.</summary>
    Client: string;
    /// <summary>Arbeitsbereich (Projektname), zu dem die Anmeldung gehört.</summary>
    Workspace: string;
    State: string;
    /// <summary>Hält die Cache-Sperre und schreibt den Cache.</summary>
    Writer: Boolean;
    Started: TDateTime;
    /// <summary>Letzte Ereignisse, älteste zuerst, höchstens TIndexProcessEntry.MaxEvents (Adapter).</summary>
    Events: TArray<TIndexProcessEvent>;
    function ToJson: TJSONObject;
    /// <summary>False bei ungültigem Inhalt (z. B. mitten im Schreiben gelesen).</summary>
    class function FromJson(const AText: string; out AInfo: TIndexProcessInfo): Boolean; static;
  end;

  TIndexProcessLog = class
  public
    /// <summary>Ereignisse aller Prozesse nach Zeit, je mit dem Prozess davor ("MCP: …").</summary>
    class function Events(const AProcesses: TArray<TIndexProcessInfo>): TArray<TIndexProcessEvent>; static;
  end;

implementation

uses
  System.DateUtils;

{ TIndexProcessInfo }

function TIndexProcessInfo.ToJson: TJSONObject;
var
  Items: TJSONArray;
  Event: TIndexProcessEvent;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('pid', TJSONNumber.Create(Pid));
  Result.AddPair('kind', Kind);
  Result.AddPair('client', Client);
  Result.AddPair('workspace', Workspace);
  Result.AddPair('state', State);
  Result.AddPair('writer', TJSONBool.Create(Writer));
  Result.AddPair('started', DateToISO8601(Started, False));
  Items := TJSONArray.Create;
  for Event in Events do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('time', DateToISO8601(Event.Time, False));
    Item.AddPair('text', Event.Text);
    Items.AddElement(Item);
  end;
  Result.AddPair('events', Items);
end;

function ReadTime(AObject: TJSONObject; const AName: string): TDateTime;
var
  Text: string;
begin
  Result := 0;
  if AObject.TryGetValue<string>(AName, Text) and (Text <> '') then
    try
      Result := ISO8601ToDate(Text, False);
    except
      on Exception do
        Result := 0;
    end;
end;

class function TIndexProcessInfo.FromJson(const AText: string; out AInfo: TIndexProcessInfo): Boolean;
var
  Root: TJSONValue;
  Item: TJSONObject;
  Items: TJSONArray;
  Value: TJSONValue;
  Event: TIndexProcessEvent;
  Pid: Integer;
begin
  AInfo := Default(TIndexProcessInfo);
  try
    Root := TJSONObject.ParseJSONValue(AText);
  except
    on Exception do
      Root := nil;
  end;
  try
    Result := (Root is TJSONObject) and TJSONObject(Root).TryGetValue<Integer>('pid', Pid);
    if not Result then
      Exit;
    Item := TJSONObject(Root);
    AInfo.Pid := Cardinal(Pid);
    AInfo.Kind := Item.GetValue<string>('kind', '');
    AInfo.Client := Item.GetValue<string>('client', '');
    AInfo.Workspace := Item.GetValue<string>('workspace', '');
    AInfo.State := Item.GetValue<string>('state', '');
    AInfo.Writer := (Item.GetValue('writer') is TJSONBool) and TJSONBool(Item.GetValue('writer')).AsBoolean;
    AInfo.Started := ReadTime(Item, 'started');
    if Item.TryGetValue<TJSONArray>('events', Items) then
      for Value in Items do
        if Value is TJSONObject then
        begin
          Event.Time := ReadTime(TJSONObject(Value), 'time');
          Event.Text := TJSONObject(Value).GetValue<string>('text', '');
          if Event.Text <> '' then
            AInfo.Events := AInfo.Events + [Event];
        end;
  finally
    Root.Free;
  end;
end;

{ TIndexProcessLog }

class function TIndexProcessLog.Events(const AProcesses: TArray<TIndexProcessInfo>): TArray<TIndexProcessEvent>;
var
  Process: TIndexProcessInfo;
  Event, Item: TIndexProcessEvent;
  Kinds: TDictionary<string, Integer>;
  Count, Index: Integer;
begin
  Result := nil;
  // Zwei Prozesse derselben Art unterscheidet die Prozessnummer.
  Kinds := TDictionary<string, Integer>.Create;
  try
    for Process in AProcesses do
    begin
      if not Kinds.TryGetValue(Process.Kind, Count) then
        Count := 0;
      Kinds.AddOrSetValue(Process.Kind, Count + 1);
    end;
    for Process in AProcesses do
      for Event in Process.Events do
      begin
        Item.Time := Event.Time;
        if Kinds[Process.Kind] > 1 then
          Item.Text := Format('%s %d: %s', [Process.Kind, Process.Pid, Event.Text])
        else
          Item.Text := Process.Kind + ': ' + Event.Text;
        // Stabil einsortieren: Gleichzeitige Ereignisse eines Prozesses behalten ihre Reihenfolge.
        Index := Length(Result);
        while (Index > 0) and (Result[Index - 1].Time > Item.Time) do
          Dec(Index);
        Insert(Item, Result, Index);
      end;
  finally
    Kinds.Free;
  end;
end;

end.
