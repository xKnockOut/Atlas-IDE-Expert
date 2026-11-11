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
//   jede Zeile als sie selbst, wie ohne Verfolgung.
// - Zeilen anderer Kanäle und anderer Experten im selben Tracker bleiben unberührt.
// - Schließt die IDE den Puffer, meldet der Tracker Destroyed: Eintrag und
//   Zuordnung entfallen. Uninstall meldet alle Beobachter ab und entfernt die
//   Zeilen von Atlas.
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
  System.Generics.Collections,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Foundation.EditorSnapshot;

type
  /// <summary>Beobachter eines Trackers; gehört zu einem Puffer.</summary>
  TLineNotifier = class(TNotifierObject, IOTANotifier, IOTAEditLineNotifier)
  private
    FFileName: string;
  public
    constructor Create(const AFileName: string);
    procedure LineChanged(OldLine, NewLine: Integer; Data: NativeInt);
    procedure Destroyed;
  end;

  TBufferEntry = record
    Tracker: IOTAEditLineTracker;
    NotifierIndex: Integer;
  end;

var
  GTracking: TAtlasLineTracking;
  GBuffers: TDictionary<string, TBufferEntry>;

function Tracking: TAtlasLineTracking;
begin
  if GTracking = nil then
  begin
    GTracking := TAtlasLineTracking.Create;
  end;
  Result := GTracking;
end;

function Buffers: TDictionary<string, TBufferEntry>;
begin
  if GBuffers = nil then
  begin
    GBuffers := TDictionary<string, TBufferEntry>.Create;
  end;
  Result := GBuffers;
end;

function KeyOf(const AFileName: string): string;
begin
  Result := AnsiUpperCase(AFileName);
end;

{ TLineNotifier }

constructor TLineNotifier.Create(const AFileName: string);
begin
  inherited Create;
  FFileName := AFileName;
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
  // Puffer geschlossen: Der Tracker geht, mit ihm Eintrag und Zuordnung.
  if GBuffers <> nil then
  begin
    GBuffers.Remove(KeyOf(FFileName));
  end;
  if GTracking <> nil then
  begin
    GTracking.Remove(FFileName);
  end;
end;

/// <summary>Eintrag des Puffers, bei Bedarf mit neuem Beobachter; False, wenn die IDE keinen Tracker liefert.
/// </summary>
function EnsureBuffer(const ABuffer: IOTAEditBuffer; out AEntry: TBufferEntry): Boolean;
var
  mKey: string;
begin
  mKey := KeyOf(ABuffer.FileName);
  if Buffers.TryGetValue(mKey, AEntry) then
  begin
    Exit(True);
  end;
  AEntry := Default(TBufferEntry);
  AEntry.Tracker := ABuffer.GetEditLineTracker;
  Result := AEntry.Tracker <> nil;
  if Result then
  begin
    AEntry.NotifierIndex := AEntry.Tracker.AddNotifier(TLineNotifier.Create(ABuffer.FileName));
    Buffers.Add(mKey, AEntry);
  end;
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
  Result := Tracking.Find(AView.Buffer.FileName, AChannel);
  if (Result <> nil) and (Result.Stamp = AStamp) then
  begin
    Exit;
  end;
  // Neuer Stand: nur anmelden, wenn seine Zeilen zum Puffer passen. Sonst bis zum nächsten Stand ohne Verfolgung
  // (jede Zeile ist sie selbst), ohne den Text bei jeder Zeile erneut zu vergleichen.
  if (ASourceText() <> TAtlasEditorSnapshots.Get(AView).Text) or not EnsureBuffer(AView.Buffer, mEntry) then
  begin
    Result := Tracking.Ensure(AView.Buffer.FileName, AChannel);
    Result.Reset(AStamp, nil);
    Exit;
  end;
  DropLines(mEntry.Tracker, AChannel);
  mLines := ALines();
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

class function TAtlasIdeLineTracker.Current(const AFileName: string; AChannel, AStamp: Integer): TAtlasTrackedLines;
begin
  Result := nil;
  if GTracking <> nil then
  begin
    Result := GTracking.Find(AFileName, AChannel);
  end;
  if (Result <> nil) and (Result.Stamp <> AStamp) then
  begin
    Result := nil;
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
  mBuffers: TDictionary<string, TBufferEntry>;
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
    for mEntry in mBuffers.Values.ToArray do
    begin
      try
        DropLines(mEntry.Tracker, 0);
        mEntry.Tracker.RemoveNotifier(mEntry.NotifierIndex);
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
