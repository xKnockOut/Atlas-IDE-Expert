unit Atlas.Core.Assistants.LinkState;

// Assistenten-Kopplung (#2377), Zustand ohne IDE:
// - TAtlasLinkSelections: welche Auswahl als selection_changed hinausgeht und welche getLatestSelection nennt.
//   Gemeldet wird erst, wenn eine neue Auswahl TAtlasContextPace.cQuietMs ruht (wie der IDE-Zustand, #2050);
//   Ziehen mit der Maus erzeugt so eine Meldung, nicht viele.
// - TAtlasLinkDiffs: offene Vorschläge aus openDiff. Jeder bekommt eine Nummer und wird genau einmal entschieden
//   (angenommen, abgelehnt, per close_tab oder closeAllDiffTabs geschlossen, beim Trennen verworfen); erst dann
//   geht die Antwort an den Assistenten. Jeder gehört der Verbindung, die ihn geschickt hat; trennt sie, werden ihre
//   Vorschläge abgelehnt.
// - TAtlasLinkText: Stellen im Text für openFile (Bereich von startText bis endText), Zeilenzahl und Zeilenenden
//   des Vorschlags wie in der Datei.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Assistants.ContextState,
  Atlas.Core.Assistants.Contract.Link;

type
  TAtlasLinkSelections = class
  private
    FPace: TAtlasContextPace;
    FLatest: TAtlasLinkSelection;
    FHasLatest: Boolean;
  public
    /// <summary>Auswahl ASelection zum Zeitpunkt ANowMs; True = jetzt als selection_changed melden.</summary>
    function Due(const ASelection: TAtlasLinkSelection; ANowMs: UInt64): Boolean;
    /// <summary>Letzte bekannte Auswahl mit Datei; Known = False, solange es keine gab.</summary>
    function Latest: TAtlasLinkSelection;
    /// <summary>Nach dem Verbinden: die nächste Auswahl wird gemeldet, auch wenn sie gleich ist.</summary>
    procedure Forget;
  end;

  /// <summary>Ein offener Vorschlag.</summary>
  TAtlasLinkDiff = record
    Id: Integer;
    /// <summary>Verbindung, die den Vorschlag geschickt hat.</summary>
    Owner: Integer;
    Request: TAtlasLinkDiffRequest;
    /// <summary>Stand der Datei, gegen den der Vorschlag gezeigt wird.</summary>
    OldText: string;
    Done: TAtlasLinkDiffDone;
  end;

  /// <summary>Bereich im Text; Found = False, wenn startText nicht vorkommt.</summary>
  TAtlasLinkRange = record
    Found: Boolean;
    Start: TAtlasLinkPosition;
    Stop: TAtlasLinkPosition;
  end;

  TAtlasLinkText = class
  public
    /// <summary>Zeilen von AText (CRLF, LF oder CR); ein leerer Text hat eine Zeile.</summary>
    class function LineCount(const AText: string): Integer; static;
    /// <summary>Zeile und Zeichen (0-basiert) zum Zeichenindex AOffset (0-basiert) in AText.</summary>
    class function PositionOf(const AText: string; AOffset: Integer): TAtlasLinkPosition; static;
    /// <summary>Bereich vom ersten AStartText bis zum Ende des ersten AEndText dahinter (ohne AEndText bis zum Ende
    /// von AStartText); ASelectToEndOfLine verlängert bis zum Zeilenende.</summary>
    class function FindRange(const AText, AStartText, AEndText: string; ASelectToEndOfLine: Boolean):
      TAtlasLinkRange; static;
    /// <summary>ANew mit den Zeilenenden von AOld: Steht in AOld CRLF und in ANew nur LF, wird jedes LF zu CRLF.
    /// </summary>
    class function MatchBreaks(const AOld, ANew: string): string; static;
  end;

  TAtlasLinkDiffs = class
  private
    FItems: TList<TAtlasLinkDiff>;
    FNextId: Integer;
    function IndexOf(AId: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Vorschlag aufnehmen; Ergebnis seine Nummer.</summary>
    function Add(AOwner: Integer; const ARequest: TAtlasLinkDiffRequest; const AOldText: string;
      const ADone: TAtlasLinkDiffDone): Integer;
    function Find(AId: Integer; out ADiff: TAtlasLinkDiff): Boolean;
    /// <summary>Datei hat sich seit dem Zeigen geändert: Vorschlag AId gilt nun gegen AOldText. False, wenn er
    /// schon entschieden ist.</summary>
    function Rebase(AId: Integer; const AOldText: string): Boolean;
    /// <summary>Vorschlag AId entscheiden: Antwort senden und entfernen. False, wenn er schon entschieden ist.
    /// </summary>
    function Decide(AId: Integer; AAccepted: Boolean; const AText: string): Boolean;
    /// <summary>Nummern der Vorschläge mit dem Namen ATabName.</summary>
    function IdsNamed(const ATabName: string): TArray<Integer>;
    /// <summary>Nummern aller offenen Vorschläge.</summary>
    function Ids: TArray<Integer>;
    /// <summary>Nummern der Vorschläge der Verbindung AOwner.</summary>
    function IdsOf(AOwner: Integer): TArray<Integer>;
    /// <summary>Alle offenen Vorschläge ablehnen; Ergebnis ihre Zahl.</summary>
    function RejectAll: Integer;
    function Count: Integer;
  end;

implementation

uses
  System.Math;

{ TAtlasLinkSelections }

function TAtlasLinkSelections.Due(const ASelection: TAtlasLinkSelection; ANowMs: UInt64): Boolean;
begin
  if ASelection.Known then
  begin
    FLatest := ASelection;
    FHasLatest := True;
  end;
  Result := FPace.Due(ASelection.Key, ANowMs) and ASelection.Known;
end;

function TAtlasLinkSelections.Latest: TAtlasLinkSelection;
begin
  Result := Default(TAtlasLinkSelection);
  if FHasLatest then
  begin
    Result := FLatest;
  end;
end;

procedure TAtlasLinkSelections.Forget;
begin
  FPace.Forget;
end;

{ TAtlasLinkText }

function IsBreak(ACharacter: Char): Boolean;
begin
  Result := (ACharacter = #10) or (ACharacter = #13);
end;

class function TAtlasLinkText.LineCount(const AText: string): Integer;
begin
  Result := PositionOf(AText, Length(AText)).Line + 1;
end;

class function TAtlasLinkText.PositionOf(const AText: string; AOffset: Integer): TAtlasLinkPosition;
var
  mIndex: Integer;
  mLineStart: Integer;
begin
  Result := TAtlasLinkPosition.At(0, 0);
  mLineStart := 0;
  mIndex := 1;
  while (mIndex <= AOffset) and (mIndex <= Length(AText)) do
  begin
    if IsBreak(AText[mIndex]) then
    begin
      // CRLF zählt als ein Umbruch.
      if (AText[mIndex] = #13) and (mIndex < Length(AText)) and (AText[mIndex + 1] = #10) then
      begin
        Inc(mIndex);
      end;
      Inc(Result.Line);
      mLineStart := mIndex;
    end;
    Inc(mIndex);
  end;
  Result.Character := Min(AOffset, Length(AText)) - mLineStart;
end;

class function TAtlasLinkText.FindRange(const AText, AStartText, AEndText: string; ASelectToEndOfLine: Boolean):
  TAtlasLinkRange;
var
  mStart: Integer;
  mStop: Integer;
  mEnd: Integer;
begin
  Result := Default(TAtlasLinkRange);
  if AStartText = '' then
  begin
    Exit;
  end;
  mStart := Pos(AStartText, AText);
  if mStart = 0 then
  begin
    Exit;
  end;
  mStop := mStart + Length(AStartText) - 1;
  if AEndText <> '' then
  begin
    mEnd := Pos(AEndText, AText, mStart + Length(AStartText));
    if mEnd > 0 then
    begin
      mStop := mEnd + Length(AEndText) - 1;
    end;
  end;
  if ASelectToEndOfLine then
  begin
    while (mStop < Length(AText)) and not IsBreak(AText[mStop + 1]) do
    begin
      Inc(mStop);
    end;
  end;
  Result.Found := True;
  Result.Start := PositionOf(AText, mStart - 1);
  Result.Stop := PositionOf(AText, mStop);
end;

class function TAtlasLinkText.MatchBreaks(const AOld, ANew: string): string;
begin
  Result := ANew;
  if (Pos(#13#10, AOld) > 0) and (Pos(#13#10, ANew) = 0) and (Pos(#13, ANew) = 0) then
  begin
    Result := ANew.Replace(#10, #13#10);
  end;
end;

{ TAtlasLinkDiffs }

constructor TAtlasLinkDiffs.Create;
begin
  inherited Create;
  FItems := TList<TAtlasLinkDiff>.Create;
end;

destructor TAtlasLinkDiffs.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

function TAtlasLinkDiffs.IndexOf(AId: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to FItems.Count - 1 do
  begin
    if FItems[mIndex].Id = AId then
    begin
      Result := mIndex;
      Exit;
    end;
  end;
  Result := -1;
end;

function TAtlasLinkDiffs.Add(AOwner: Integer; const ARequest: TAtlasLinkDiffRequest; const AOldText: string;
  const ADone: TAtlasLinkDiffDone): Integer;
var
  mDiff: TAtlasLinkDiff;
begin
  Inc(FNextId);
  mDiff := Default(TAtlasLinkDiff);
  mDiff.Id := FNextId;
  mDiff.Owner := AOwner;
  mDiff.Request := ARequest;
  mDiff.OldText := AOldText;
  mDiff.Done := ADone;
  FItems.Add(mDiff);
  Result := mDiff.Id;
end;

function TAtlasLinkDiffs.Find(AId: Integer; out ADiff: TAtlasLinkDiff): Boolean;
var
  mIndex: Integer;
begin
  ADiff := Default(TAtlasLinkDiff);
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if Result then
  begin
    ADiff := FItems[mIndex];
  end;
end;

function TAtlasLinkDiffs.Rebase(AId: Integer; const AOldText: string): Boolean;
var
  mIndex: Integer;
  mDiff: TAtlasLinkDiff;
begin
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if Result then
  begin
    mDiff := FItems[mIndex];
    mDiff.OldText := AOldText;
    FItems[mIndex] := mDiff;
  end;
end;

function TAtlasLinkDiffs.Decide(AId: Integer; AAccepted: Boolean; const AText: string): Boolean;
var
  mIndex: Integer;
  mDone: TAtlasLinkDiffDone;
begin
  mIndex := IndexOf(AId);
  Result := mIndex >= 0;
  if not Result then
  begin
    Exit;
  end;
  // Erst entfernen, dann antworten: Die Antwort darf keinen zweiten Entscheid auslösen.
  mDone := FItems[mIndex].Done;
  FItems.Delete(mIndex);
  if Assigned(mDone) then
  begin
    mDone(AAccepted, AText);
  end;
end;

function TAtlasLinkDiffs.IdsNamed(const ATabName: string): TArray<Integer>;
var
  mDiff: TAtlasLinkDiff;
begin
  Result := nil;
  for mDiff in FItems do
  begin
    if mDiff.Request.TabName = ATabName then
    begin
      Result := Result + [mDiff.Id];
    end;
  end;
end;

function TAtlasLinkDiffs.Ids: TArray<Integer>;
var
  mDiff: TAtlasLinkDiff;
begin
  Result := nil;
  for mDiff in FItems do
  begin
    Result := Result + [mDiff.Id];
  end;
end;

function TAtlasLinkDiffs.IdsOf(AOwner: Integer): TArray<Integer>;
var
  mDiff: TAtlasLinkDiff;
begin
  Result := nil;
  for mDiff in FItems do
  begin
    if mDiff.Owner = AOwner then
    begin
      Result := Result + [mDiff.Id];
    end;
  end;
end;

function TAtlasLinkDiffs.RejectAll: Integer;
var
  mId: Integer;
begin
  Result := 0;
  for mId in Ids do
  begin
    if Decide(mId, False, '') then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasLinkDiffs.Count: Integer;
begin
  Result := FItems.Count;
end;

end.
