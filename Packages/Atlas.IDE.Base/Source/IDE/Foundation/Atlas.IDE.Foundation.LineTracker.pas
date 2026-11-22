unit Atlas.IDE.Foundation.LineTracker;

// Anbindung der Zeilenverfolgung der IDE (#1818, editor.trackLines): je
// Puffer ein IOTAEditLineTracker mit einem Beobachter (IOTAEditLineNotifier).
// Ein Kanal (etwa die Befunde) meldet mit Follow die Quellzeilen seiner Marken
// zu einem Stand an; die IDE verschiebt sie bei jeder Bearbeitung, die sie
// kennt (Tippen, Einfügen, Rückgängig, Blockoperationen), und meldet jede
// Verschiebung mit der Kennung der Zeile (TAtlasLineTracking.Encode). Die
// Zuordnung Quellzeile → aktuelle Zeile hält der Kern
// (Atlas.Core.Editor.LineTracking); der Zeichner fragt sie mit SourceAt.
// - Neu angemeldet wird nur, wenn der Stand des Kanals wechselt und der Text des
//   Stands dem Puffer entspricht (sonst stünden die Zeilen falsch); bis dahin gilt
//   jede Zeile als sie selbst, wie ohne Verfolgung. Dasselbe gilt nach einem
//   Fehler beim Anmelden (GiveUp): Bis zum nächsten Stand versucht es niemand neu.
// - Zeilen anderer Kanäle und anderer Experten im selben Tracker bleiben unberührt.
// - Beim Anmelden meldete die IDE einmal eine Zugriffsverletzung in boreditu.dll
//   (Stapel: Zeichnen → Follow → AddLine → Vergrößern der Zeilentabelle). Drei
//   Vorkehrungen kamen zugleich; welche davon die Ursache trifft, ist nicht
//   eingegrenzt, jede gilt vorsorglich:
//   1. Angemeldet werden nur Zeilen, die der Puffer hat, aufsteigend und jede
//      einmal (TAtlasLineTracking.Trackable).
//   2. Follow verändert die Tabelle der IDE und läuft nicht beim Zeichnen (das
//      Zeichnen kommt auch aus WM_PRINTCLIENT, etwa beim Hover). Der Zeichner
//      fragt nur Current und meldet über einen Zeitgeber danach an.
//   3. Ein gemerkter Tracker wird nur angefasst, solange er der des geöffneten
//      Puffers ist (EnsureBuffer, Uninstall); veraltete werden nur losgelassen.
// - Schließt die IDE den Puffer, meldet der Tracker Destroyed: Die Anmeldung
//   dieses Beobachters und die Zuordnung entfallen, die eines späteren Puffers
//   gleichen Namens bleibt (Seriennummer, TAtlasLineBuffers). Uninstall meldet
//   alle Beobachter ab und entfernt die Zeilen von Atlas.
// Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Editor.LineTracking;

type
  TAtlasIdeLineTracker = class
  public
    /// <summary>Quellzeilen ALines des Kanals AChannel für den Puffer von AView zum Stand AStamp verfolgen.
    /// ASourceText liefert den Text des Stands; nur wenn er dem Puffer entspricht, wird neu angemeldet. Liefert die
    /// Zuordnung oder nil (ausgeschaltet, kein Puffer, Stand passt nicht).</summary>
    class function Follow(const AView: IOTAEditView; AChannel, AStamp: Integer; const ALines: TFunc<TArray<Integer>>;
      const ASourceText: TFunc<string>): TAtlasTrackedLines; static;
    /// <summary>Follow für die Datei AFileName im obersten Editorfenster ihres Puffers, auch wenn sie nicht vorn
    /// liegt (weiteres Editorfenster); nil, wenn sie nicht offen ist.</summary>
    class function FollowFile(const AFileName: string; AChannel, AStamp: Integer;
      const ALines: TFunc<TArray<Integer>>; const ASourceText: TFunc<string>): TAtlasTrackedLines; static;
    /// <summary>Stand AStamp des Kanals für AFileName ohne Verfolgung (jede Zeile ist sie selbst), etwa nach einem
    /// Fehler in Follow: Bis zum nächsten Stand meldet niemand neu an. Fasst die IDE nicht an.</summary>
    class procedure GiveUp(const AFileName: string; AChannel, AStamp: Integer); static;
    /// <summary>Zuordnung des Kanals für AFileName, nur wenn sie zum Stand AStamp angemeldet ist (Leser ohne Ansicht,
    /// etwa die Randspalte); sonst nil.</summary>
    class function Current(const AFileName: string; AChannel, AStamp: Integer): TAtlasTrackedLines; static;
    /// <summary>Welche Quellzeile des Kanals steht jetzt in Zeile AEditorLine (0-basiert)? Ohne Zuordnung:
    /// AEditorLine selbst.</summary>
    class function SourceAt(ALines: TAtlasTrackedLines; AEditorLine: Integer; out ASource: Integer): Boolean; static;
    /// <summary>Alle Beobachter abmelden, Zeilen von Atlas entfernen, Zuordnungen vergessen.</summary>
    class procedure Uninstall; static;
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.ToolsApi.Files.Service;

type
  /// <summary>Beobachter eines Trackers; gehört zu einer Anmeldung (Seriennummer).</summary>
  TLineNotifier = class(TNotifierObject, IOTANotifier, IOTAEditLineNotifier)
  private
    FFileName: string;
    FSerial: Integer;
  public
    constructor Create(const AFileName: string; ASerial: Integer);
    procedure LineChanged(OldLine, NewLine: Integer; Data: NativeInt);
    procedure Destroyed;
  end;

  // Die Tracker stehen als gezählte Referenz in den Anmeldungen: So verlangt es die Open Tools API für jedes
  // Interface der IDE. Hält die IDE sich daran, bleibt ein veralteter Tracker gültig, bis seine Anmeldung ersetzt
  // oder gelöscht wird, und seine Adresse geht nicht an einen neuen Tracker. Eine ungezählte Referenz ließe einen
  // neuen Tracker an der Adresse eines freigegebenen als „derselbe“ erscheinen; Uninstall riefe dann RemoveNotifier
  // mit der Nummer eines fremden Beobachters. Angefasst wird ein gemerkter Tracker trotzdem nur, solange er der des
  // geöffneten Puffers ist; ob die IDE einen veralteten Tracker freigibt, obwohl er noch gezählt wird, ist in der
  // IDE nicht geprüft.
  TBufferEntry = TAtlasLineBuffer<IOTAEditLineTracker>;
  TBuffers = TAtlasLineBuffers<IOTAEditLineTracker>;

var
  GTracking: TAtlasLineTracking;
  GBuffers: TBuffers;

function Tracking: TAtlasLineTracking;
begin
  if GTracking = nil then
  begin
    GTracking := TAtlasLineTracking.Create;
  end;
  Result := GTracking;
end;

function Buffers: TBuffers;
begin
  if GBuffers = nil then
  begin
    GBuffers := TBuffers.Create;
  end;
  Result := GBuffers;
end;

{ TLineNotifier }

constructor TLineNotifier.Create(const AFileName: string; ASerial: Integer);
begin
  inherited Create;
  FFileName := AFileName;
  FSerial := ASerial;
end;

procedure TLineNotifier.LineChanged(OldLine, NewLine: Integer; Data: NativeInt);
begin
  try
    // Die IDE zählt ab 1; eine gelöschte Zeile meldet sie mit einer Zeile unter 1.
    if GTracking <> nil then
    begin
      GTracking.Changed(FFileName, Data, NewLine - 1);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

procedure TLineNotifier.Destroyed;
begin
  try
    // Nur die eigene Anmeldung: Unter demselben Dateinamen kann längst ein neuer Puffer angemeldet sein, dessen
    // Anmeldung und Zuordnung bleiben.
    if (GBuffers <> nil) and GBuffers.Forget(FFileName, FSerial) and (GTracking <> nil) then
    begin
      GTracking.Remove(FFileName);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Problems, E);
  end;
end;

/// <summary>Anmeldung des Puffers, bei Bedarf mit neuem Beobachter; False, wenn die IDE keinen Tracker liefert.
/// </summary>
function EnsureBuffer(const ABuffer: IOTAEditBuffer; out AEntry: TBufferEntry): Boolean;
var
  mTracker: IOTAEditLineTracker;
begin
  AEntry := Default(TBufferEntry);
  mTracker := ABuffer.GetEditLineTracker;
  if mTracker = nil then
  begin
    Exit(False);
  end;
  // Eine Anmeldung mit anderem Tracker gehört zu einem früheren Puffer gleichen Namens, dessen Ende nicht gemeldet
  // wurde: nicht mehr anfassen, nur ersetzen.
  if Buffers.TryGet(ABuffer.FileName, AEntry) and (AEntry.Tracker = mTracker) then
  begin
    Exit(True);
  end;
  AEntry := Default(TBufferEntry);
  AEntry.FileName := ABuffer.FileName;
  AEntry.Tracker := mTracker;
  AEntry.Serial := Buffers.NextSerial;
  AEntry.NotifierIndex := mTracker.AddNotifier(TLineNotifier.Create(AEntry.FileName, AEntry.Serial));
  Buffers.Put(AEntry);
  Result := True;
end;

/// <summary>Zeilen des Kanals AChannel (bzw. aller Kanäle bei 0) aus dem Tracker entfernen.</summary>
procedure DropLines(const ATracker: IOTAEditLineTracker; AChannel: Integer);
var
  mIndex, mChannel, mLine: Integer;
begin
  for mIndex := ATracker.GetCount - 1 downto 0 do
  begin
    if TAtlasLineTracking.Decode(ATracker.GetData(mIndex), mChannel, mLine) and
      ((AChannel = 0) or (mChannel = AChannel)) then
    begin
      ATracker.Delete(mIndex);
    end;
  end;
end;

/// <summary>Ist der Tracker der Anmeldung noch der des geöffneten Puffers gleichen Namens?</summary>
function StillOpen(const AEntry: TBufferEntry): Boolean;
var
  mBuffer: IOTAEditBuffer;
begin
  mBuffer := TAtlasIdeFiles.BufferOf(AEntry.FileName);
  Result := (mBuffer <> nil) and (mBuffer.GetEditLineTracker = AEntry.Tracker);
end;

{ TAtlasIdeLineTracker }

class function TAtlasIdeLineTracker.Follow(const AView: IOTAEditView; AChannel, AStamp: Integer;
  const ALines: TFunc<TArray<Integer>>; const ASourceText: TFunc<string>): TAtlasTrackedLines;
var
  mEntry: TBufferEntry;
  mLines: TArray<Integer>;
  mLine: Integer;
begin
  Result := nil;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  Result := Tracking.Current(AView.Buffer.FileName, AChannel, AStamp);
  if Result <> nil then
  begin
    Exit;
  end;
  // Neuer Stand: nur anmelden, wenn seine Zeilen zum Puffer passen. Sonst bis zum nächsten Stand ohne Verfolgung
  // (jede Zeile ist sie selbst), ohne den Text bei jeder Zeile erneut zu vergleichen.
  if (ASourceText() <> TAtlasEditorSnapshots.Get(AView).Text) or not EnsureBuffer(AView.Buffer, mEntry) then
  begin
    Exit(Tracking.Untracked(AView.Buffer.FileName, AChannel, AStamp));
  end;
  DropLines(mEntry.Tracker, AChannel);
  mLines := TAtlasLineTracking.Trackable(ALines(), AView.Buffer.GetLinesInBuffer);
  for mLine in mLines do
  begin
    if TAtlasLineTracking.Encode(AChannel, mLine) <> 0 then
    begin
      mEntry.Tracker.AddLine(mLine + 1, TAtlasLineTracking.Encode(AChannel, mLine));
    end;
  end;
  Result := Tracking.Ensure(AView.Buffer.FileName, AChannel);
  Result.Reset(AStamp, mLines);
end;

class function TAtlasIdeLineTracker.FollowFile(const AFileName: string; AChannel, AStamp: Integer;
  const ALines: TFunc<TArray<Integer>>; const ASourceText: TFunc<string>): TAtlasTrackedLines;
var
  mBuffer: IOTAEditBuffer;
begin
  Result := nil;
  mBuffer := TAtlasIdeFiles.BufferOf(AFileName);
  if mBuffer <> nil then
  begin
    Result := Follow(mBuffer.TopView, AChannel, AStamp, ALines, ASourceText);
  end;
end;

class procedure TAtlasIdeLineTracker.GiveUp(const AFileName: string; AChannel, AStamp: Integer);
begin
  Tracking.Untracked(AFileName, AChannel, AStamp);
end;

class function TAtlasIdeLineTracker.Current(const AFileName: string; AChannel, AStamp: Integer): TAtlasTrackedLines;
begin
  Result := nil;
  if GTracking <> nil then
  begin
    Result := GTracking.Current(AFileName, AChannel, AStamp);
  end;
end;

class function TAtlasIdeLineTracker.SourceAt(ALines: TAtlasTrackedLines; AEditorLine: Integer;
  out ASource: Integer): Boolean;
begin
  if ALines = nil then
  begin
    ASource := AEditorLine;
    Exit(True);
  end;
  Result := ALines.SourceAt(AEditorLine, ASource);
end;

class procedure TAtlasIdeLineTracker.Uninstall;
var
  mBuffers: TBuffers;
  mEntry: TBufferEntry;
begin
  // Erst aus den globalen Variablen lösen: Meldet die IDE beim Abmelden Destroyed, findet der Beobachter nichts mehr.
  mBuffers := GBuffers;
  GBuffers := nil;
  FreeAndNil(GTracking);
  if mBuffers = nil then
  begin
    Exit;
  end;
  try
    for mEntry in mBuffers.Entries do
    begin
      try
        // Nur Tracker geöffneter Puffer: Einen veralteten fasst Atlas nicht an, er wird nur losgelassen.
        if StillOpen(mEntry) then
        begin
          DropLines(mEntry.Tracker, 0);
          mEntry.Tracker.RemoveNotifier(mEntry.NotifierIndex);
        end;
      except
        on E: Exception do
          TAtlasGuard.Report(TAtlasFeature.Problems, E);
      end;
    end;
  finally
    mBuffers.Free;
  end;
end;

end.
