unit Atlas.Core.Assistants.EditMarks;

// Randmarken an Zeilen, die ein KI-Assistent geändert hat (#2616, Stufe 2), ohne Windows und VCL: Jede angewendete
// Änderung (Edited) markiert die Zeilen ihres neuen Blocks (TAtlasEditChange.Between) mit Assistent, Nummer seiner
// Sitzung (Farbe) und Zeit; eine reine Löschung markiert die Zeile danach. Bis die Datei gespeichert wird (Saved),
// wandern die Marken mit: Track vergleicht den aktuellen Text mit dem zuletzt bekannten, Zeilen vor dem geänderten
// Block bleiben, Zeilen dahinter verschieben sich, Zeilen im Block behalten ihre Marke nur, wenn ihr Text gleich
// geblieben ist. Speichert der Eingang selbst (Datei war ungeändert), kommt die Meldung dieses Speicherns verzögert
// (Prüfung der Zeitstempel); Saved übergeht sie daher bis cOwnSaveMs nach der Änderung. Die Marken leben mit dem
// Modul.

interface

uses
  System.Generics.Collections,
  Atlas.Text.AssistantOrigin,
  Atlas.Core.Assistants.Sessions;

type
  /// <summary>Angewendete Änderung eines Assistenten an AFileName von ABefore nach AAfter; ASaved: der Eingang hat
  /// die Datei danach selbst gespeichert.</summary>
  TAtlasEditedProc = reference to procedure(const AFileName: string; const AOrigin: TAtlasAssistantOrigin;
    const ABefore, AAfter: string; ASaved: Boolean);

  /// <summary>Uhr in Millisekunden (fortlaufend).</summary>
  TAtlasEditMarksClock = reference to function: UInt64;

  TAtlasEditMark = record
    /// <summary>Zeile ab 0 im aktuellen Text.</summary>
    Line: Integer;
    /// <summary>Text der Zeile ohne Zeilenende, zum Nachprüfen im Editor.</summary>
    Text: string;
    Origin: TAtlasAssistantOrigin;
    /// <summary>Nummer des Assistenten (TAtlasAssistantSessions), -1 unbekannt.</summary>
    Assistant: Integer;
    At: TDateTime;
    /// <summary>Reine Löschung vor dieser Zeile: so viele Zeilen entfernt; sonst 0.</summary>
    Removed: Integer;
  end;

  TAtlasEditMarks = class
  public const
    /// <summary>So lange nach einer selbst gespeicherten Änderung gilt eine Meldung „gespeichert“ als die eigene.
    /// </summary>
    cOwnSaveMs = 5000;
  private type
    TFileState = class
    public
      Text: string;
      Marks: TDictionary<Integer, TAtlasEditMark>;
      IgnoreSavesUntil: UInt64;
      constructor Create;
      destructor Destroy; override;
    end;
  private
    FFiles: TObjectDictionary<string, TFileState>;
    FSessions: TAtlasAssistantSessions;
    FClock: TAtlasEditMarksClock;
    function StateOf(const AFileName: string): TFileState;
    class function KeyOf(const AFileName: string): string; static;
    class procedure Shift(AState: TFileState; const ANewText: string); static;
    /// <summary>Zeilen des neuen Blocks von AChange in AAfter mit AMark (Herkunft, Zeit) markieren.</summary>
    class procedure MarkBlock(AState: TFileState; AFirstLine, AAdded, ARemoved: Integer; const AAfter: string;
      AMark: TAtlasEditMark); static;
  public
    /// <summary>ASessions vergibt die Nummern (darf nil sein: alle -1); AClock für das eigene Speichern.</summary>
    constructor Create(ASessions: TAtlasAssistantSessions; const AClock: TAtlasEditMarksClock);
    destructor Destroy; override;
    /// <summary>Änderung angewendet: Zeilen des neuen Blocks markieren, vorhandene Marken nachführen.</summary>
    procedure Edited(const AFileName: string; const AOrigin: TAtlasAssistantOrigin; const ABefore, AAfter: string;
      ASaved: Boolean; AAt: TDateTime);
    /// <summary>AFileName gespeichert: Marken weg, außer es ist das eigene Speichern des Eingangs.</summary>
    procedure Saved(const AFileName: string);
    /// <summary>Aktueller Text von AFileName: Marken nachführen.</summary>
    procedure Track(const AFileName, AText: string);
    function HasMarks(const AFileName: string): Boolean;
    /// <summary>Marke an ALine (ab 0); mit AHasText nur, wenn ALineText noch der markierte Text ist.</summary>
    function MarkAt(const AFileName: string; ALine: Integer; const ALineText: string; AHasText: Boolean;
      out AMark: TAtlasEditMark): Boolean;
    /// <summary>Zahl der Marken in AFileName.</summary>
    function CountIn(const AFileName: string): Integer;
    procedure Clear;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Text.Lines,
  Atlas.Core.Assistants.EditChange;

{ TAtlasEditMarks.TFileState }

constructor TAtlasEditMarks.TFileState.Create;
begin
  inherited Create;
  Marks := TDictionary<Integer, TAtlasEditMark>.Create;
end;

destructor TAtlasEditMarks.TFileState.Destroy;
begin
  Marks.Free;
  inherited Destroy;
end;

{ TAtlasEditMarks }

constructor TAtlasEditMarks.Create(ASessions: TAtlasAssistantSessions; const AClock: TAtlasEditMarksClock);
begin
  inherited Create;
  FFiles := TObjectDictionary<string, TFileState>.Create([doOwnsValues]);
  FSessions := ASessions;
  FClock := AClock;
end;

destructor TAtlasEditMarks.Destroy;
begin
  FFiles.Free;
  inherited Destroy;
end;

class function TAtlasEditMarks.KeyOf(const AFileName: string): string;
begin
  Result := AnsiLowerCase(AFileName);
end;

function TAtlasEditMarks.StateOf(const AFileName: string): TFileState;
begin
  if not FFiles.TryGetValue(KeyOf(AFileName), Result) then
  begin
    Result := nil;
  end;
end;

class procedure TAtlasEditMarks.Shift(AState: TFileState; const ANewText: string);
var
  mChange: TAtlasEditChange;
  mLines: TArray<string>;
  mMarks: TArray<TAtlasEditMark>;
  mMark: TAtlasEditMark;
  mStart, mOldEnd, mLine, mIndex: Integer;
begin
  if AState.Text = ANewText then
  begin
    Exit;
  end;
  mChange := TAtlasEditChange.Between(AState.Text, ANewText);
  AState.Text := ANewText;
  if mChange.IsEmpty or (AState.Marks.Count = 0) then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitAtLineFeed(ANewText);
  mStart := mChange.FirstLine - 1;
  mOldEnd := mStart + mChange.Removed;
  mMarks := AState.Marks.Values.ToArray;
  AState.Marks.Clear;
  for mIndex := 0 to High(mMarks) do
  begin
    mMark := mMarks[mIndex];
    if mMark.Line < mStart then
    begin
      mLine := mMark.Line;
    end
    else if mMark.Line >= mOldEnd then
    begin
      mLine := mMark.Line + mChange.Added - mChange.Removed;
    end
    else
    begin
      // Im geänderten Block: gleiche Stelle, sofern sie noch zum neuen Block gehört.
      mLine := mMark.Line;
      if mLine - mStart >= mChange.Added then
      begin
        Continue;
      end;
    end;
    // Nur, wenn die Zeile noch den markierten Text trägt.
    if (mLine >= 0) and (mLine <= High(mLines)) and (mLines[mLine] = mMark.Text) then
    begin
      mMark.Line := mLine;
      AState.Marks.AddOrSetValue(mLine, mMark);
    end;
  end;
end;

class procedure TAtlasEditMarks.MarkBlock(AState: TFileState; AFirstLine, AAdded, ARemoved: Integer;
  const AAfter: string; AMark: TAtlasEditMark);
var
  mLines: TArray<string>;
  mIndex, mStart: Integer;
begin
  mLines := TTextLines.SplitAtLineFeed(AAfter);
  mStart := AFirstLine - 1;
  if AAdded = 0 then
  begin
    // Reine Löschung: die Zeile, die jetzt an der Stelle steht (am Ende die letzte).
    AMark.Line := Min(mStart, High(mLines));
    if AMark.Line >= 0 then
    begin
      AMark.Text := mLines[AMark.Line];
      AMark.Removed := ARemoved;
      AState.Marks.AddOrSetValue(AMark.Line, AMark);
    end;
    Exit;
  end;
  for mIndex := mStart to Min(mStart + AAdded - 1, High(mLines)) do
  begin
    AMark.Line := mIndex;
    AMark.Text := mLines[mIndex];
    AState.Marks.AddOrSetValue(mIndex, AMark);
  end;
end;

procedure TAtlasEditMarks.Edited(const AFileName: string; const AOrigin: TAtlasAssistantOrigin; const ABefore,
  AAfter: string; ASaved: Boolean; AAt: TDateTime);
var
  mState: TFileState;
  mChange: TAtlasEditChange;
  mMark: TAtlasEditMark;
begin
  mChange := TAtlasEditChange.Between(ABefore, AAfter);
  mState := StateOf(AFileName);
  if mState = nil then
  begin
    if mChange.IsEmpty then
    begin
      Exit;
    end;
    mState := TFileState.Create;
    mState.Text := ABefore;
    FFiles.Add(KeyOf(AFileName), mState);
  end;
  // Stand des Editors vor der Änderung, dann die Änderung selbst.
  Shift(mState, ABefore);
  Shift(mState, AAfter);
  if ASaved then
  begin
    mState.IgnoreSavesUntil := FClock() + cOwnSaveMs;
  end;
  if mChange.IsEmpty then
  begin
    Exit;
  end;
  mMark := Default(TAtlasEditMark);
  mMark.Origin := AOrigin;
  mMark.Assistant := -1;
  if FSessions <> nil then
  begin
    mMark.Assistant := FSessions.IndexOf(AOrigin);
  end;
  mMark.At := AAt;
  MarkBlock(mState, mChange.FirstLine, mChange.Added, mChange.Removed, AAfter, mMark);
end;

procedure TAtlasEditMarks.Saved(const AFileName: string);
var
  mState: TFileState;
begin
  mState := StateOf(AFileName);
  if (mState = nil) or (FClock() < mState.IgnoreSavesUntil) then
  begin
    Exit;
  end;
  FFiles.Remove(KeyOf(AFileName));
end;

procedure TAtlasEditMarks.Track(const AFileName, AText: string);
var
  mState: TFileState;
begin
  mState := StateOf(AFileName);
  if mState <> nil then
  begin
    Shift(mState, AText);
  end;
end;

function TAtlasEditMarks.HasMarks(const AFileName: string): Boolean;
var
  mState: TFileState;
begin
  mState := StateOf(AFileName);
  Result := (mState <> nil) and (mState.Marks.Count > 0);
end;

function TAtlasEditMarks.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean; out AMark: TAtlasEditMark): Boolean;
var
  mState: TFileState;
  mMark: TAtlasEditMark;
begin
  AMark := Default(TAtlasEditMark);
  mState := StateOf(AFileName);
  if (mState = nil) or not mState.Marks.TryGetValue(ALine, mMark) then
  begin
    Exit(False);
  end;
  // Im Editor schon weiter getippt: Die Marke wartet auf die nächste Verankerung.
  Result := not AHasText or (ALineText = mMark.Text);
  if Result then
  begin
    AMark := mMark;
  end;
end;

function TAtlasEditMarks.CountIn(const AFileName: string): Integer;
var
  mState: TFileState;
begin
  Result := 0;
  mState := StateOf(AFileName);
  if mState <> nil then
  begin
    Result := mState.Marks.Count;
  end;
end;

procedure TAtlasEditMarks.Clear;
begin
  FFiles.Clear;
end;

end.
