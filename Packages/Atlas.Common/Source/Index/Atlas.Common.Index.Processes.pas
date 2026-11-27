unit Atlas.Common.Index.Processes;

// Anmeldung eines Server-Prozesses an einem Index-Cache (#62) als Datensatz:
// Art (LSP, MCP), Client, Zustand ("baut Index", "liest Cache", "bereit"), ob
// er die Cache-Sperre hält, und seine letzten Sperr- und Cache-Ereignisse; dazu
// das Zusammenführen der Ereignisse aller Prozesse nach Zeit. Dateien und
// Sperren liegen in Atlas.Common.Index.ProcessFiles.

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
    /// <summary>Kurze Kennung des Prozesses (#2616, SessionOf): unterscheidet zwei Prozesse desselben Clients; ''
    /// = unbekannt (ältere Server).</summary>
    Session: string;
    /// <summary>Arbeitsbereich (Projektname), zu dem die Anmeldung gehört.</summary>
    Workspace: string;
    State: string;
    /// <summary>Hält die Cache-Sperre und schreibt den Cache.</summary>
    Writer: Boolean;
    Started: TDateTime;
    /// <summary>Letzte Ereignisse, älteste zuerst, höchstens TIndexProcessEntry.cMaxEvents (Adapter).</summary>
    Events: TArray<TIndexProcessEvent>;
    function ToJson: TJSONObject;
    /// <summary>Kurze Kennung aus Prozessnummer und Startzeit (#2616): vier Kleinbuchstaben-Hexziffern, gleich für
    /// gleiche Werte.</summary>
    class function SessionOf(APid: Cardinal; AStarted: TDateTime): string; static;
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
  System.DateUtils,
  Atlas.Text.Json;

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
  if Session <> '' then
  begin
    Result.AddPair('session', Session);
  end;
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

// FNV-1a rechnet modulo 2^32: die Überlaufprüfung ist nur hier aus, danach wie vorher.
{$IFOPT Q+}{$DEFINE ATLAS_HASH_UEBERLAUF}{$Q-}{$ENDIF}
{$IFOPT R+}{$DEFINE ATLAS_HASH_BEREICH}{$R-}{$ENDIF}
class function TIndexProcessInfo.SessionOf(APid: Cardinal; AStarted: TDateTime): string;
const
  cMask = $FFFF;
var
  mHash: UInt32;
  mMs: Int64;
begin
  mMs := Trunc(AStarted * MSecsPerDay);
  mHash := 2166136261;
  mHash := (mHash xor UInt32(APid)) * 16777619;
  mHash := (mHash xor UInt32(mMs and $FFFFFFFF)) * 16777619;
  mHash := (mHash xor UInt32((mMs shr 32) and $FFFFFFFF)) * 16777619;
  Result := LowerCase(IntToHex(Integer((mHash xor (mHash shr 16)) and cMask), 4));
end;
{$IFDEF ATLAS_HASH_BEREICH}{$R+}{$UNDEF ATLAS_HASH_BEREICH}{$ENDIF}
{$IFDEF ATLAS_HASH_UEBERLAUF}{$Q+}{$UNDEF ATLAS_HASH_UEBERLAUF}{$ENDIF}

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
    mEvent.Time := TJsonRead.IsoTime(TJSONObject(mValue), 'time', False);
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
  mRoot := TJsonRead.Parse(AText);
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
    AInfo.Session := mItem.GetValue<string>('session', '');
    AInfo.Workspace := mItem.GetValue<string>('workspace', '');
    AInfo.State := mItem.GetValue<string>('state', '');
    AInfo.Writer := (mItem.GetValue('writer') is TJSONBool) and TJSONBool(mItem.GetValue('writer')).AsBoolean;
    AInfo.Started := TJsonRead.IsoTime(mItem, 'started', False);
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
