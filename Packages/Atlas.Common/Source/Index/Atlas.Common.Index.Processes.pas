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
    cStateBuilding = 'baut Index';
    cStateReading = 'liest Cache';
    cStateReady = 'bereit';
    cKindLsp = 'LSP';
    cKindMcp = 'MCP';
    /// <summary>Kommandozeilen-Linter --check mit Symbolindex (#1112).</summary>
    cKindCheck = 'Check';
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
    /// <summary>Letzte Ereignisse, älteste zuerst, höchstens TIndexProcessEntry.cMaxEvents (Adapter).</summary>
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
  mItems: TJSONArray;
  mEvent: TIndexProcessEvent;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('pid', TJSONNumber.Create(Pid));
  Result.AddPair('kind', Kind);
  Result.AddPair('client', Client);
  Result.AddPair('workspace', Workspace);
  Result.AddPair('state', State);
  Result.AddPair('writer', TJSONBool.Create(Writer));
  Result.AddPair('started', DateToISO8601(Started, False));
  mItems := TJSONArray.Create;
  for mEvent in Events do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('time', DateToISO8601(mEvent.Time, False));
    mItem.AddPair('text', mEvent.Text);
    mItems.AddElement(mItem);
  end;
  Result.AddPair('events', mItems);
end;

function ReadTime(AObject: TJSONObject; const AName: string): TDateTime;
var
  mText: string;
begin
  Result := 0;
  if AObject.TryGetValue<string>(AName, mText) and (mText <> '') then
    try
      Result := ISO8601ToDate(mText, False);
    except
      on Exception do
        Result := 0;
    end;
end;

/// <summary>Ereignisse mit Text aus "events".</summary>
function ReadEvents(AItems: TJSONArray): TArray<TIndexProcessEvent>;
var
  mValue: TJSONValue;
  mEvent: TIndexProcessEvent;
begin
  Result := nil;
  for mValue in AItems do
  begin
    if not (mValue is TJSONObject) then
    begin
      Continue;
    end;
    mEvent.Time := ReadTime(TJSONObject(mValue), 'time');
    mEvent.Text := TJSONObject(mValue).GetValue<string>('text', '');
    if mEvent.Text <> '' then
    begin
      Result := Result + [mEvent];
    end;
  end;
end;

class function TIndexProcessInfo.FromJson(const AText: string; out AInfo: TIndexProcessInfo): Boolean;
var
  mRoot: TJSONValue;
  mItem: TJSONObject;
  mItems: TJSONArray;
  mPid: Integer;
begin
  AInfo := Default(TIndexProcessInfo);
  try
    mRoot := TJSONObject.ParseJSONValue(AText);
  except
    on Exception do
      mRoot := nil;
  end;
  try
    Result := (mRoot is TJSONObject) and TJSONObject(mRoot).TryGetValue<Integer>('pid', mPid);
    if not Result then
    begin
      Exit;
    end;
    mItem := TJSONObject(mRoot);
    AInfo.Pid := Cardinal(mPid);
    AInfo.Kind := mItem.GetValue<string>('kind', '');
    AInfo.Client := mItem.GetValue<string>('client', '');
    AInfo.Workspace := mItem.GetValue<string>('workspace', '');
    AInfo.State := mItem.GetValue<string>('state', '');
    AInfo.Writer := (mItem.GetValue('writer') is TJSONBool) and TJSONBool(mItem.GetValue('writer')).AsBoolean;
    AInfo.Started := ReadTime(mItem, 'started');
    if mItem.TryGetValue<TJSONArray>('events', mItems) then
    begin
      AInfo.Events := ReadEvents(mItems);
    end;
  finally
    mRoot.Free;
  end;
end;

{ TIndexProcessLog }

class function TIndexProcessLog.Events(const AProcesses: TArray<TIndexProcessInfo>): TArray<TIndexProcessEvent>;
var
  mProcess: TIndexProcessInfo;
  mEvent, mItem: TIndexProcessEvent;
  mKinds: TDictionary<string, Integer>;
  mCount, mIndex: Integer;
begin
  Result := nil;
  // Zwei Prozesse derselben Art unterscheidet die Prozessnummer.
  mKinds := TDictionary<string, Integer>.Create;
  try
    for mProcess in AProcesses do
    begin
      if not mKinds.TryGetValue(mProcess.Kind, mCount) then
      begin
        mCount := 0;
      end;
      mKinds.AddOrSetValue(mProcess.Kind, mCount + 1);
    end;
    for mProcess in AProcesses do
    begin
      for mEvent in mProcess.Events do
      begin
        mItem.Time := mEvent.Time;
        if mKinds[mProcess.Kind] > 1 then
        begin
          mItem.Text := Format('%s %d: %s', [mProcess.Kind, mProcess.Pid, mEvent.Text]);
        end
        else
        begin
          mItem.Text := mProcess.Kind + ': ' + mEvent.Text;
        end;
        // Stabil einsortieren: Gleichzeitige Ereignisse eines Prozesses behalten ihre Reihenfolge.
        mIndex := Length(Result);
        while (mIndex > 0) and (Result[mIndex - 1].Time > mItem.Time) do
        begin
          Dec(mIndex);
        end;
        Insert(mItem, Result, mIndex);
      end;
    end;
  finally
    mKinds.Free;
  end;
end;

end.
