unit Atlas.Core.Editor.LineTracking;

// Marken folgen ihrer Zeile sofort (#1818, editor.trackLines), ohne VCL und
// Open Tools API. Die IDE verfolgt Zeilen eines Puffers (IOTAEditLineTracker)
// und meldet jede Verschiebung mit dem Wert, den Atlas beim Anmelden der Zeile
// mitgab. Dieser Wert ist die Kennung der Marke: Kanal (wer die Marke setzt,
// etwa die Befunde) und Quellzeile (Zeile im Stand, auf den sich die Daten des
// Kanals beziehen, z. B. der Text der letzten Serverantwort).
// - TAtlasTrackedLines hält je Datei und Kanal die Zuordnung Quellzeile →
//   aktuelle Zeile. Reset setzt sie mit einem neuen Stand (Stamp) zurück, Moved
//   führt eine Meldung der IDE nach, ein negatives Ziel heißt „Zeile gelöscht“.
//   SourceAt beantwortet die Frage des Zeichners „welche Quellzeile steht jetzt
//   in Zeile X?“. Ohne Verschiebung seit Reset gilt die Zeile selbst.
// - Die Umkehrung baut SourceAt erst bei Bedarf neu auf: Zeilen einfügen meldet
//   jede verfolgte Zeile darunter einzeln, das Zeichnen fragt danach.
// - TAtlasLineTracking verwaltet die Zuordnungen aller Dateien und Kanäle.
// Der Server bleibt die Quelle: Die Zuordnung überbrückt nur die Zeit, bis der
// Kanal einen neuen Stand hat.
// Alle Zeilen 0-basiert. Nur im Hauptthread verwenden.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  /// <summary>Zuordnung Quellzeile → aktuelle Zeile für eine Datei und einen Kanal.</summary>
  TAtlasTrackedLines = class
  private
    FStamp: Integer;
    FMoved: Boolean;
    FCurrent: TDictionary<Integer, Integer>;
    FSourceAt: TDictionary<Integer, Integer>;
    FSourceAtValid: Boolean;
    procedure BuildSourceAt;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neuer Stand AStamp mit den verfolgten Quellzeilen ALines (jede steht an ihrer Zeile).</summary>
    procedure Reset(AStamp: Integer; const ALines: TArray<Integer>);
    /// <summary>Meldung der IDE: Quellzeile ASource steht jetzt in ANewLine; ANewLine &lt; 0 = gelöscht.
    /// Unbekannte Quellzeilen bleiben unbeachtet.</summary>
    procedure Moved(ASource, ANewLine: Integer);
    /// <summary>Welche Quellzeile steht jetzt in Zeile ACurrent? False, wenn dort keine verfolgte Zeile steht
    /// (weggerückt oder gelöscht). Ohne Verschiebung seit Reset: ACurrent selbst.</summary>
    function SourceAt(ACurrent: Integer; out ASource: Integer): Boolean;
    /// <summary>Aktuelle Zeile der Quellzeile ASource; False, wenn gelöscht. Unverfolgte Zeilen: unverändert.</summary>
    function CurrentOf(ASource: Integer; out ACurrent: Integer): Boolean;
    /// <summary>Verfolgte Quellzeilen.</summary>
    function Lines: TArray<Integer>;
    /// <summary>Stand, mit dem Reset zuletzt lief.</summary>
    property Stamp: Integer read FStamp;
    /// <summary>Hat sich seit Reset eine Zeile verschoben oder ist eine gelöscht worden?</summary>
    property HasMoved: Boolean read FMoved;
  end;

  /// <summary>Zuordnungen aller Dateien und Kanäle; Kennungen der IDE-Zeilen (Encode, Decode).</summary>
  TAtlasLineTracking = class
  public const
    /// <summary>Kanal der Befunde (Wellenlinie, Randmarke, Fehlertext am Zeilenende).</summary>
    cProblems = 1;
    /// <summary>Höchster Kanal.</summary>
    cMaxChannel = 31;
    /// <summary>Höchste Quellzeile, die eine Kennung tragen kann.</summary>
    cMaxLine = $3FFFFF;
  private const
    // Bits 27..30 kennzeichnen Atlas, 22..26 den Kanal, 0..21 die Zeile: auch unter Win32 positiv.
    cTag = NativeInt($50000000);
    cTagMask = NativeInt($78000000);
    // Alles über Bit 30 (Win64) muss frei sein.
    cPositive = NativeInt($7FFFFFFF);
    cChannelShift = 22;
  private
    FLines: TObjectDictionary<string, TAtlasTrackedLines>;
    class function Key(const AFileName: string; AChannel: Integer): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Kennung der Quellzeile ALine im Kanal AChannel für die IDE; 0, wenn außerhalb der Grenzen.</summary>
    class function Encode(AChannel, ALine: Integer): NativeInt; static;
    /// <summary>Kanal und Quellzeile aus einer Kennung; False bei fremden Kennungen.</summary>
    class function Decode(AData: NativeInt; out AChannel, ALine: Integer): Boolean; static;
    /// <summary>Zuordnung der Datei im Kanal; nil ohne.</summary>
    function Find(const AFileName: string; AChannel: Integer): TAtlasTrackedLines;
    /// <summary>Zuordnung der Datei im Kanal, bei Bedarf neu (Stand 0, nichts verfolgt).</summary>
    function Ensure(const AFileName: string; AChannel: Integer): TAtlasTrackedLines;
    /// <summary>Meldung der IDE für AFileName mit der Kennung AData weiterreichen; fremde Kennungen bleiben
    /// unbeachtet. ANewLine 0-basiert, negativ = gelöscht.</summary>
    procedure Changed(const AFileName: string; AData: NativeInt; ANewLine: Integer);
    /// <summary>Alle Kanäle der Datei vergessen (Puffer geschlossen).</summary>
    procedure Remove(const AFileName: string);
    procedure Clear;
  end;

implementation

{ TAtlasTrackedLines }

constructor TAtlasTrackedLines.Create;
begin
  inherited Create;
  FCurrent := TDictionary<Integer, Integer>.Create;
  FSourceAt := TDictionary<Integer, Integer>.Create;
end;

destructor TAtlasTrackedLines.Destroy;
begin
  FSourceAt.Free;
  FCurrent.Free;
  inherited Destroy;
end;

procedure TAtlasTrackedLines.Reset(AStamp: Integer; const ALines: TArray<Integer>);
var
  mLine: Integer;
begin
  FStamp := AStamp;
  FMoved := False;
  FCurrent.Clear;
  FSourceAt.Clear;
  FSourceAtValid := False;
  for mLine in ALines do
  begin
    if mLine >= 0 then
    begin
      FCurrent.AddOrSetValue(mLine, mLine);
    end;
  end;
end;

procedure TAtlasTrackedLines.Moved(ASource, ANewLine: Integer);
var
  mOld: Integer;
begin
  if not FCurrent.TryGetValue(ASource, mOld) then
  begin
    Exit;
  end;
  if ANewLine < 0 then
  begin
    ANewLine := -1;
  end;
  if mOld = ANewLine then
  begin
    Exit;
  end;
  FCurrent[ASource] := ANewLine;
  FMoved := True;
  FSourceAtValid := False;
end;

procedure TAtlasTrackedLines.BuildSourceAt;
var
  mPair: TPair<Integer, Integer>;
  mHeld: Integer;
begin
  FSourceAt.Clear;
  for mPair in FCurrent do
  begin
    if mPair.Value < 0 then
    begin
      Continue;
    end;
    // Zwei Quellzeilen in einer Zeile (Zeilen zusammengeführt): die kleinere gilt, damit das Ergebnis nicht von
    // der Reihenfolge im Wörterbuch abhängt.
    if not FSourceAt.TryGetValue(mPair.Value, mHeld) or (mPair.Key < mHeld) then
    begin
      FSourceAt.AddOrSetValue(mPair.Value, mPair.Key);
    end;
  end;
  FSourceAtValid := True;
end;

function TAtlasTrackedLines.SourceAt(ACurrent: Integer; out ASource: Integer): Boolean;
begin
  if not FMoved then
  begin
    ASource := ACurrent;
    Exit(True);
  end;
  if not FSourceAtValid then
  begin
    BuildSourceAt;
  end;
  Result := FSourceAt.TryGetValue(ACurrent, ASource);
  if not Result then
  begin
    ASource := -1;
  end;
end;

function TAtlasTrackedLines.CurrentOf(ASource: Integer; out ACurrent: Integer): Boolean;
begin
  if not FCurrent.TryGetValue(ASource, ACurrent) then
  begin
    ACurrent := ASource;
  end;
  Result := ACurrent >= 0;
end;

function TAtlasTrackedLines.Lines: TArray<Integer>;
begin
  Result := FCurrent.Keys.ToArray;
end;

{ TAtlasLineTracking }

constructor TAtlasLineTracking.Create;
begin
  inherited Create;
  FLines := TObjectDictionary<string, TAtlasTrackedLines>.Create([doOwnsValues]);
end;

destructor TAtlasLineTracking.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

class function TAtlasLineTracking.Key(const AFileName: string; AChannel: Integer): string;
begin
  Result := AnsiUpperCase(AFileName) + '|' + IntToStr(AChannel);
end;

class function TAtlasLineTracking.Encode(AChannel, ALine: Integer): NativeInt;
begin
  Result := 0;
  if (AChannel < 1) or (AChannel > cMaxChannel) or (ALine < 0) or (ALine > cMaxLine) then
  begin
    Exit;
  end;
  Result := cTag or (NativeInt(AChannel) shl cChannelShift) or NativeInt(ALine);
end;

class function TAtlasLineTracking.Decode(AData: NativeInt; out AChannel, ALine: Integer): Boolean;
begin
  AChannel := 0;
  ALine := -1;
  Result := ((AData and not cPositive) = 0) and ((AData and cTagMask) = cTag);
  if not Result then
  begin
    Exit;
  end;
  AChannel := Integer((AData shr cChannelShift) and cMaxChannel);
  ALine := Integer(AData and cMaxLine);
  Result := AChannel >= 1;
end;

function TAtlasLineTracking.Find(const AFileName: string; AChannel: Integer): TAtlasTrackedLines;
begin
  if not FLines.TryGetValue(Key(AFileName, AChannel), Result) then
  begin
    Result := nil;
  end;
end;

function TAtlasLineTracking.Ensure(const AFileName: string; AChannel: Integer): TAtlasTrackedLines;
var
  mKey: string;
begin
  mKey := Key(AFileName, AChannel);
  if not FLines.TryGetValue(mKey, Result) then
  begin
    Result := TAtlasTrackedLines.Create;
    FLines.Add(mKey, Result);
  end;
end;

procedure TAtlasLineTracking.Changed(const AFileName: string; AData: NativeInt; ANewLine: Integer);
var
  mChannel, mLine: Integer;
  mLines: TAtlasTrackedLines;
begin
  if not Decode(AData, mChannel, mLine) then
  begin
    Exit;
  end;
  mLines := Find(AFileName, mChannel);
  if mLines <> nil then
  begin
    mLines.Moved(mLine, ANewLine);
  end;
end;

procedure TAtlasLineTracking.Remove(const AFileName: string);
var
  mChannel: Integer;
begin
  for mChannel := 1 to cMaxChannel do
  begin
    FLines.Remove(Key(AFileName, mChannel));
  end;
end;

procedure TAtlasLineTracking.Clear;
begin
  FLines.Clear;
end;

end.
