unit Atlas.Core.Assistants.Log;

// Protokoll der Aufträge von KI-Assistenten in dieser IDE-Sitzung (#2049, Fenster „Atlas-KI-Protokoll“), ohne
// Windows und VCL. Die Eingänge des Moduls melden, was geschehen ist:
// - Edited: Änderung an einer offenen Datei angewendet (mit geändertem Zeilenblock, TAtlasEditChange),
// - Refused: abgelehnt (Grund), Held: zurückgehalten (#2605), Discarded: zurückgehaltene Änderung verworfen,
// - Build: Build für einen KI-Assistenten (Art, Ergebnis),
// - Question: Rückfrage (#2620) mit Antwort bzw. Ausgang,
// - Reverted: im Fenster zurückgenommen (der Eintrag der Änderung ist danach als zurückgenommen markiert).
// Jeder Eintrag nennt den Assistenten (Client und Sitzung, #2616); mit Sessions bekommt er dessen Nummer für die
// Farbe, Assistants liefert die Assistenten der Einträge für den Filter.
// Neueste Einträge kommen ans Ende; über Max hinaus fallen die ältesten weg. Ausgeschaltet (Enabled = False) nimmt
// das Protokoll nichts an und hält nichts. Nichts davon geht auf die Platte. Version zählt jede Änderung, damit das
// Fenster nur bei Bedarf neu füllt.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Text.AssistantOrigin,
  Atlas.Core.Assistants.Sessions,
  Atlas.Core.Assistants.EditChange;

type
  TAtlasAssistantsLogKind = (Edited, Refused, Held, Discarded, Build, Question, Reverted);

  /// <summary>Warum sich ein Eintrag nicht zurücknehmen lässt.</summary>
  TAtlasLogRevertBlock = (None, NoChange, AlreadyReverted, TooLarge, ChangedSince);

  TAtlasAssistantsLogEntry = record
    Id: Integer;
    /// <summary>Ortszeit.</summary>
    Time: TDateTime;
    Kind: TAtlasAssistantsLogKind;
    /// <summary>clientInfo.name des MCP-Clients; '' unbekannt.</summary>
    Client: string;
    /// <summary>Kennung des MCP-Prozesses (#2616); '' unbekannt.</summary>
    Session: string;
    /// <summary>Nummer des Assistenten in TAtlasAssistantSessions (Farbe); -1 unbekannt oder ohne Sessions.
    /// </summary>
    Assistant: Integer;
    /// <summary>Datei (Änderungen) bzw. Projekt (Build); '' bei Fragen.</summary>
    FileName: string;
    /// <summary>Methode an der Stelle aus der Gliederung; '' unbekannt.</summary>
    Method: string;
    /// <summary>Geänderter Zeilenblock (Edited, Held, Discarded, Reverted).</summary>
    Change: TAtlasEditChange;
    HasChange: Boolean;
    /// <summary>Ergebnis in Worten: Grund, Build-Ergebnis, Frage und Antwort.</summary>
    Detail: string;
    /// <summary>Edited: im Fenster zurückgenommen.</summary>
    Reverted: Boolean;
    function Origin: TAtlasAssistantOrigin;
  end;

  /// <summary>Zahlen für die Kopfzeile.</summary>
  TAtlasAssistantsLogCounts = record
    Edits: Integer;
    Builds: Integer;
    Refused: Integer;
    Held: Integer;
    Questions: Integer;
    Discarded: Integer;
    Reverted: Integer;
  end;

  TAtlasAssistantsLog = class
  public const
    cDefaultMax = 500;
    cMinMax = 50;
    cMaxMax = 5000;
    /// <summary>Kopf je Änderung im Unterschied der Sitzung: Datei, erste und letzte Zeile.</summary>
    cDiffHeader = '=== %s · %d–%d';
  private
    FEntries: TList<TAtlasAssistantsLogEntry>;
    FEnabled: Boolean;
    FMax: Integer;
    FNextId: Integer;
    FVersion: Integer;
    FSince: TDateTime;
    FSessions: TAtlasAssistantSessions;
    procedure SetEnabled(AValue: Boolean);
    procedure SetMax(AValue: Integer);
    procedure DropOldest;
    function IndexOf(AId: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Hängt AEntry an (Id und, wenn 0, Zeit setzt das Protokoll); liefert die Kennung, 0 ausgeschaltet.
    /// </summary>
    function Add(const AEntry: TAtlasAssistantsLogEntry): Integer;
    /// <summary>Eintrag für eine Änderung von ABefore nach AAfter an AFileName.</summary>
    class function EditEntry(AKind: TAtlasAssistantsLogKind; const AFileName: string;
      const AOrigin: TAtlasAssistantOrigin; const ABefore, AAfter: string): TAtlasAssistantsLogEntry; static;
    /// <summary>Eintrag ohne Änderung (Ablehnung, Build, Frage).</summary>
    class function PlainEntry(AKind: TAtlasAssistantsLogKind; const AFileName: string;
      const AOrigin: TAtlasAssistantOrigin; const ADetail: string): TAtlasAssistantsLogEntry; static;
    /// <summary>Assistenten der Einträge in der Reihenfolge ihres ersten Eintrags (Filter, #2616).</summary>
    function Assistants: TArray<TAtlasAssistantOrigin>;
    /// <summary>Assistenten von AEntries in der Reihenfolge ihres ersten Eintrags.</summary>
    class function AssistantsIn(const AEntries: TArray<TAtlasAssistantsLogEntry>): TArray<TAtlasAssistantOrigin>;
      static;
    /// <summary>Einträge von AEntries, die von AOrigin stammen (unbekannte Herkunft: die ohne Angaben).</summary>
    class function OfAssistant(const AEntries: TArray<TAtlasAssistantsLogEntry>;
      const AOrigin: TAtlasAssistantOrigin): TArray<TAtlasAssistantsLogEntry>; static;
    function Count: Integer;
    function Entries: TArray<TAtlasAssistantsLogEntry>;
    function TryGet(AId: Integer; out AEntry: TAtlasAssistantsLogEntry): Boolean;
    function Counts: TAtlasAssistantsLogCounts;
    /// <summary>Lässt sich AId zurücknehmen, wenn in der Datei jetzt ACurrent steht? ANewText ist dann der Text
    /// danach.</summary>
    function RevertPlan(AId: Integer; const ACurrent: string; out ANewText: string): TAtlasLogRevertBlock;
    /// <summary>AId ist zurückgenommen.</summary>
    procedure MarkReverted(AId: Integer);
    /// <summary>Zeilen für den Unterschied aller Änderungen dieser Sitzung, Datei für Datei.</summary>
    function SessionDiffLines: TArray<string>;
    procedure Clear;
    /// <summary>Aus: nichts annehmen, alles verwerfen.</summary>
    property Enabled: Boolean read FEnabled write SetEnabled;
    /// <summary>Höchstens so viele Einträge (cMinMax bis cMaxMax).</summary>
    property MaxEntries: Integer read FMax write SetMax;
    /// <summary>Zählt jede Änderung.</summary>
    property Version: Integer read FVersion;
    /// <summary>Zeit des ersten Eintrags seit dem letzten Leeren; 0 ohne.</summary>
    property Since: TDateTime read FSince;
    /// <summary>Nummern der Assistenten für die Farbe (gehört dem Modul); nil = ohne.</summary>
    property Sessions: TAtlasAssistantSessions read FSessions write FSessions;
  end;

implementation

uses
  System.Math;

{ TAtlasAssistantsLogEntry }

function TAtlasAssistantsLogEntry.Origin: TAtlasAssistantOrigin;
begin
  Result := TAtlasAssistantOrigin.Make(Client, Session);
end;

{ TAtlasAssistantsLog }

constructor TAtlasAssistantsLog.Create;
begin
  inherited Create;
  FEntries := TList<TAtlasAssistantsLogEntry>.Create;
  FMax := cDefaultMax;
end;

destructor TAtlasAssistantsLog.Destroy;
begin
  FEntries.Free;
  inherited Destroy;
end;

procedure TAtlasAssistantsLog.SetEnabled(AValue: Boolean);
begin
  if FEnabled = AValue then
  begin
    Exit;
  end;
  FEnabled := AValue;
  if not FEnabled then
  begin
    Clear;
  end;
end;

procedure TAtlasAssistantsLog.SetMax(AValue: Integer);
begin
  FMax := EnsureRange(AValue, cMinMax, cMaxMax);
  DropOldest;
end;

procedure TAtlasAssistantsLog.DropOldest;
var
  mExcess: Integer;
begin
  mExcess := FEntries.Count - FMax;
  if mExcess > 0 then
  begin
    FEntries.DeleteRange(0, mExcess);
    Inc(FVersion);
  end;
end;

function TAtlasAssistantsLog.IndexOf(AId: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    if FEntries[mIndex].Id = AId then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasAssistantsLog.Add(const AEntry: TAtlasAssistantsLogEntry): Integer;
var
  mEntry: TAtlasAssistantsLogEntry;
begin
  if not FEnabled then
  begin
    Exit(0);
  end;
  mEntry := AEntry;
  Inc(FNextId);
  mEntry.Id := FNextId;
  if mEntry.Time = 0 then
  begin
    mEntry.Time := Now;
  end;
  mEntry.Assistant := -1;
  if FSessions <> nil then
  begin
    mEntry.Assistant := FSessions.IndexOf(mEntry.Origin);
  end;
  if FEntries.Count = 0 then
  begin
    FSince := mEntry.Time;
  end;
  FEntries.Add(mEntry);
  Inc(FVersion);
  DropOldest;
  Result := mEntry.Id;
end;

class function TAtlasAssistantsLog.EditEntry(AKind: TAtlasAssistantsLogKind; const AFileName: string;
  const AOrigin: TAtlasAssistantOrigin; const ABefore, AAfter: string): TAtlasAssistantsLogEntry;
begin
  Result := Default(TAtlasAssistantsLogEntry);
  Result.Kind := AKind;
  Result.FileName := AFileName;
  Result.Client := AOrigin.Client;
  Result.Session := AOrigin.Session;
  Result.Assistant := -1;
  Result.Change := TAtlasEditChange.Between(ABefore, AAfter);
  Result.HasChange := True;
end;

class function TAtlasAssistantsLog.PlainEntry(AKind: TAtlasAssistantsLogKind; const AFileName: string;
  const AOrigin: TAtlasAssistantOrigin; const ADetail: string): TAtlasAssistantsLogEntry;
begin
  Result := Default(TAtlasAssistantsLogEntry);
  Result.Kind := AKind;
  Result.FileName := AFileName;
  Result.Client := AOrigin.Client;
  Result.Session := AOrigin.Session;
  Result.Assistant := -1;
  Result.Detail := ADetail;
end;

function TAtlasAssistantsLog.Assistants: TArray<TAtlasAssistantOrigin>;
begin
  Result := AssistantsIn(FEntries.ToArray);
end;

class function TAtlasAssistantsLog.OfAssistant(const AEntries: TArray<TAtlasAssistantsLogEntry>;
  const AOrigin: TAtlasAssistantOrigin): TArray<TAtlasAssistantsLogEntry>;
var
  mEntry: TAtlasAssistantsLogEntry;
  mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AEntries));
  mCount := 0;
  for mEntry in AEntries do
  begin
    if mEntry.Origin.SameAs(AOrigin) then
    begin
      Result[mCount] := mEntry;
      Inc(mCount);
    end;
  end;
  SetLength(Result, mCount);
end;

class function TAtlasAssistantsLog.AssistantsIn(
  const AEntries: TArray<TAtlasAssistantsLogEntry>): TArray<TAtlasAssistantOrigin>;
var
  mEntry: TAtlasAssistantsLogEntry;
  mOrigin, mSeen: TAtlasAssistantOrigin;
  mFound: Boolean;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    mOrigin := mEntry.Origin;
    mFound := False;
    for mSeen in Result do
    begin
      if mSeen.SameAs(mOrigin) then
      begin
        mFound := True;
        Break;
      end;
    end;
    if not mFound then
    begin
      Result := Result + [mOrigin];
    end;
  end;
end;

function TAtlasAssistantsLog.Count: Integer;
begin
  Result := FEntries.Count;
end;

function TAtlasAssistantsLog.Entries: TArray<TAtlasAssistantsLogEntry>;
begin
  Result := FEntries.ToArray;
end;

function TAtlasAssistantsLog.TryGet(AId: Integer; out AEntry: TAtlasAssistantsLogEntry): Boolean;
var
  mIndex: Integer;
begin
  AEntry := Default(TAtlasAssistantsLogEntry);
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if Result then
  begin
    AEntry := FEntries[mIndex];
  end;
end;

function TAtlasAssistantsLog.Counts: TAtlasAssistantsLogCounts;
var
  mEntry: TAtlasAssistantsLogEntry;
begin
  Result := Default(TAtlasAssistantsLogCounts);
  for mEntry in FEntries do
  begin
    case mEntry.Kind of
      TAtlasAssistantsLogKind.Edited:
        Inc(Result.Edits);
      TAtlasAssistantsLogKind.Refused:
        Inc(Result.Refused);
      TAtlasAssistantsLogKind.Held:
        Inc(Result.Held);
      TAtlasAssistantsLogKind.Build:
        Inc(Result.Builds);
      TAtlasAssistantsLogKind.Question:
        Inc(Result.Questions);
      TAtlasAssistantsLogKind.Discarded:
        Inc(Result.Discarded);
      TAtlasAssistantsLogKind.Reverted:
        Inc(Result.Reverted);
    end;
  end;
end;

function TAtlasAssistantsLog.RevertPlan(AId: Integer; const ACurrent: string;
  out ANewText: string): TAtlasLogRevertBlock;
var
  mEntry: TAtlasAssistantsLogEntry;
begin
  ANewText := '';
  if not TryGet(AId, mEntry) or (mEntry.Kind <> TAtlasAssistantsLogKind.Edited) or not mEntry.HasChange or
    mEntry.Change.IsEmpty then
  begin
    Exit(TAtlasLogRevertBlock.NoChange);
  end;
  if mEntry.Reverted then
  begin
    Exit(TAtlasLogRevertBlock.AlreadyReverted);
  end;
  if not mEntry.Change.Kept then
  begin
    Exit(TAtlasLogRevertBlock.TooLarge);
  end;
  if not mEntry.Change.RevertIn(ACurrent, ANewText) then
  begin
    Exit(TAtlasLogRevertBlock.ChangedSince);
  end;
  Result := TAtlasLogRevertBlock.None;
end;

procedure TAtlasAssistantsLog.MarkReverted(AId: Integer);
var
  mIndex: Integer;
  mEntry: TAtlasAssistantsLogEntry;
begin
  mIndex := IndexOf(AId);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mEntry := FEntries[mIndex];
  mEntry.Reverted := True;
  FEntries[mIndex] := mEntry;
  Inc(FVersion);
end;

function TAtlasAssistantsLog.SessionDiffLines: TArray<string>;
var
  mEntry: TAtlasAssistantsLogEntry;
begin
  Result := nil;
  for mEntry in FEntries do
  begin
    if (mEntry.Kind = TAtlasAssistantsLogKind.Edited) and mEntry.HasChange and not mEntry.Reverted then
    begin
      if Result <> nil then
      begin
        Result := Result + [''];
      end;
      Result := Result + [Format(cDiffHeader, [mEntry.FileName, mEntry.Change.FirstLine,
        mEntry.Change.LastLine])] + mEntry.Change.DiffLines;
    end;
  end;
end;

procedure TAtlasAssistantsLog.Clear;
begin
  FEntries.Clear;
  FSince := 0;
  Inc(FVersion);
end;

end.
