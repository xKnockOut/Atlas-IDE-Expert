unit Atlas.Core.Completion.Placeholders;

// Platzhalter-Modus nach dem Einsetzen einer Vorlage (#51), ohne Editor: Lage
// der Platzhalter im Dokument, Tab-Reihenfolge und verknüpfte Platzhalter.
//
// Positionen sind 0-basierte Offsets in UTF-16-Einheiten im ganzen Text. Nach
// jeder Änderung bekommt Update den neuen Text. Liegt die Änderung ganz in
// einem Platzhalter der aktuellen Nummer, wächst oder schrumpft dieser und
// alles dahinter verschiebt sich; sonst endet der Modus. MirrorEdits liefert
// danach die Änderungen, die die verknüpften Platzhalter angleichen; nach dem
// Schreiben meldet Applied sie zurück.

interface

uses
  System.SysUtils,
  Atlas.Core.Completion.Snippets;

type
  TAtlasPlaceholderField = record
    Number: Integer;
    Start: Integer;
    Length: Integer;
    function Stop: Integer;
  end;

  /// <summary>Ersetzt Start bis Stop (Offsets im Text vor der Änderung) durch Text.</summary>
  TAtlasPlaceholderEdit = record
    Start: Integer;
    Stop: Integer;
    Text: string;
  end;

  TAtlasPlaceholderEdits = TArray<TAtlasPlaceholderEdit>;

  TAtlasPlaceholderSession = class
  private
    FText: string;
    FFields: TArray<TAtlasPlaceholderField>;
    /// <summary>Nummern in Tab-Reihenfolge: 1, 2, … aufsteigend, zuletzt 0.</summary>
    FOrder: TArray<Integer>;
    FCurrent: Integer;
    /// <summary>Zuletzt bearbeiteter Platzhalter der aktuellen Nummer; Vorlage für die verknüpften.</summary>
    FPrimary: Integer;
    procedure Shift(AFrom, ADelta, AExcept: Integer);
    function FirstOf(ANumber: Integer): Integer;
  public
    /// <summary>ADocument: Text nach dem Einsetzen; AOffset: Anfang des eingesetzten Texts darin.
    /// Ohne $0 endet die Vorlage hinter ihrem Text.</summary>
    constructor Create(const ADocument: string; AOffset: Integer; const AExpansion: TAtlasSnippetExpansion);
    /// <summary>Weiterer Platzhalter außerhalb der Vorlage (Offset im ganzen Text, #473), verknüpft mit den
    /// gleich nummerierten; ohne solche Nummer oder mit Nummer 0 übergangen. Der Cursor bleibt in der Vorlage.
    /// </summary>
    procedure Link(const AField: TAtlasPlaceholderField);
    /// <summary>Nummer des aktuellen Platzhalters; 0 = Endposition (Modus vorbei).</summary>
    function CurrentNumber: Integer;
    /// <summary>Stelle des aktuellen Platzhalters ab 1 und Zahl der nummerierten, für die Fußzeile.</summary>
    function Position: Integer;
    function Count: Integer;
    /// <summary>Der Platzhalter, in dem der Cursor steht (zuletzt bearbeitet bzw. erster der Nummer).</summary>
    function Current: TAtlasPlaceholderField;
    /// <summary>Alle Platzhalter ohne die Endposition, in Textreihenfolge.</summary>
    function Fields: TArray<TAtlasPlaceholderField>;
    /// <summary>Endposition ($0 bzw. Ende der Vorlage).</summary>
    function FinalOffset: Integer;
    /// <summary>Tab: zum nächsten Platzhalter. False, wenn danach nur noch die Endposition kommt.</summary>
    function Next: Boolean;
    /// <summary>Umschalt+Tab: zum vorigen; am ersten bleibt es dort.</summary>
    procedure Previous;
    /// <summary>Text geändert. False, wenn die Änderung nicht in einem Platzhalter der aktuellen Nummer liegt.</summary>
    function Update(const ADocument: string): Boolean;
    /// <summary>Änderungen, die die verknüpften Platzhalter an den aktuellen angleichen; aufsteigend.</summary>
    function MirrorEdits: TAtlasPlaceholderEdits;
    /// <summary>Die Änderungen aus MirrorEdits sind geschrieben.</summary>
    procedure Applied(const AEdits: TAtlasPlaceholderEdits);
    function FieldText(const AField: TAtlasPlaceholderField): string;
    /// <summary>Zeile und Zeichen (0-basiert) zum Offset AOffset in AText; Zeilen enden mit #10.</summary>
    class procedure Locate(const AText: string; AOffset: Integer; out ALine, ACharacter: Integer); static;
    property Text: string read FText;
  end;

implementation

uses
  System.Math;

type
  /// <summary>Änderung des Texts: gleicher Anfang und gleiches Ende (unabhängig voneinander), alte Länge,
  /// Längenunterschied.</summary>
  TTextChange = record
    Prefix: Integer;
    Suffix: Integer;
    OldLength: Integer;
    Delta: Integer;
  end;

function HasNumber(const ANumbers: TArray<Integer>; ANumber: Integer): Boolean;
var
  mNumber: Integer;
begin
  for mNumber in ANumbers do
  begin
    if mNumber = ANumber then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Nummern der Platzhalter ohne Endposition, ohne doppelte, aufsteigend.</summary>
function SortedNumbers(const AStops: TArray<TAtlasSnippetStop>): TArray<Integer>;
var
  mStop: TAtlasSnippetStop;
  mIndex, mInner, mSwap: Integer;
begin
  Result := nil;
  for mStop in AStops do
  begin
    if (mStop.Number > 0) and not HasNumber(Result, mStop.Number) then
    begin
      Result := Result + [mStop.Number];
    end;
  end;
  // Aufsteigend sortieren (wenige Einträge).
  for mIndex := 1 to High(Result) do
  begin
    for mInner := mIndex downto 1 do
    begin
      if Result[mInner] < Result[mInner - 1] then
      begin
        mSwap := Result[mInner];
        Result[mInner] := Result[mInner - 1];
        Result[mInner - 1] := mSwap;
      end;
    end;
  end;
end;

/// <summary>Gleicher Anfang und gleiches Ende von AOld und ANew, unabhängig voneinander: Bei "aa" → "aaa" ist jede
/// Stelle möglich.</summary>
function ChangeOf(const AOld, ANew: string): TTextChange;
var
  mLimit: Integer;
begin
  Result.OldLength := Length(AOld);
  Result.Delta := Length(ANew) - Length(AOld);
  mLimit := Min(Length(AOld), Length(ANew));
  Result.Prefix := 0;
  while (Result.Prefix < mLimit) and (AOld[Result.Prefix + 1] = ANew[Result.Prefix + 1]) do
  begin
    Inc(Result.Prefix);
  end;
  Result.Suffix := 0;
  while (Result.Suffix < mLimit) and (AOld[Length(AOld) - Result.Suffix] = ANew[Length(ANew) - Result.Suffix]) do
  begin
    Inc(Result.Suffix);
  end;
end;

/// <summary>Die Änderung liegt ganz in AField.</summary>
function Fits(const AField: TAtlasPlaceholderField; const AChange: TTextChange): Boolean;
begin
  Result := (AChange.Prefix >= AField.Start) and (AChange.Suffix >= AChange.OldLength - AField.Stop) and
    (AField.Length + AChange.Delta >= 0);
end;

/// <summary>Index des Platzhalters der Nummer ANumber, in dem die Änderung liegt: erst APrimary, dann die übrigen;
/// -1, wenn keiner passt.</summary>
function FittingField(const AFields: TArray<TAtlasPlaceholderField>; APrimary, ANumber: Integer;
  const AChange: TTextChange): Integer;
var
  mIndex: Integer;
begin
  if Fits(AFields[APrimary], AChange) then
  begin
    Exit(APrimary);
  end;
  for mIndex := 0 to High(AFields) do
  begin
    if (mIndex <> APrimary) and (AFields[mIndex].Number = ANumber) and Fits(AFields[mIndex], AChange) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TAtlasPlaceholderField }

function TAtlasPlaceholderField.Stop: Integer;
begin
  Result := Start + Length;
end;

{ TAtlasPlaceholderSession }

constructor TAtlasPlaceholderSession.Create(const ADocument: string; AOffset: Integer;
  const AExpansion: TAtlasSnippetExpansion);
var
  mStop: TAtlasSnippetStop;
  mField: TAtlasPlaceholderField;
  mHasEnd: Boolean;
begin
  inherited Create;
  FText := ADocument;
  mHasEnd := False;
  for mStop in AExpansion.Stops do
  begin
    // Die Endposition gilt nur einmal (die erste).
    if (mStop.Number = 0) and mHasEnd then
    begin
      Continue;
    end;
    mHasEnd := mHasEnd or (mStop.Number = 0);
    mField.Number := mStop.Number;
    mField.Start := AOffset + mStop.Start;
    mField.Length := mStop.Length;
    FFields := FFields + [mField];
  end;
  if not mHasEnd then
  begin
    mField.Number := 0;
    mField.Start := AOffset + System.Length(AExpansion.Text);
    mField.Length := 0;
    FFields := FFields + [mField];
  end;
  FOrder := SortedNumbers(AExpansion.Stops) + [0];
  FCurrent := 0;
  FPrimary := FirstOf(FOrder[0]);
end;

procedure TAtlasPlaceholderSession.Link(const AField: TAtlasPlaceholderField);
begin
  // Hinten anhängen: FirstOf findet zuerst die Platzhalter der Vorlage, dort steht der Cursor.
  if (AField.Number > 0) and (FirstOf(AField.Number) >= 0) then
  begin
    FFields := FFields + [AField];
  end;
end;

function TAtlasPlaceholderSession.FirstOf(ANumber: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FFields) do
  begin
    if FFields[mIndex].Number = ANumber then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasPlaceholderSession.CurrentNumber: Integer;
begin
  Result := FOrder[FCurrent];
end;

function TAtlasPlaceholderSession.Position: Integer;
begin
  Result := FCurrent + 1;
end;

function TAtlasPlaceholderSession.Count: Integer;
begin
  Result := High(FOrder);
end;

function TAtlasPlaceholderSession.Current: TAtlasPlaceholderField;
begin
  Result := FFields[FPrimary];
end;

function TAtlasPlaceholderSession.Fields: TArray<TAtlasPlaceholderField>;
var
  mField: TAtlasPlaceholderField;
begin
  Result := nil;
  for mField in FFields do
  begin
    if mField.Number > 0 then
    begin
      Result := Result + [mField];
    end;
  end;
end;

function TAtlasPlaceholderSession.FinalOffset: Integer;
begin
  Result := FFields[FirstOf(0)].Start;
end;

function TAtlasPlaceholderSession.Next: Boolean;
begin
  if FCurrent < High(FOrder) then
  begin
    Inc(FCurrent);
  end;
  FPrimary := FirstOf(FOrder[FCurrent]);
  Result := FOrder[FCurrent] <> 0;
end;

procedure TAtlasPlaceholderSession.Previous;
begin
  if (FCurrent > 0) and (FOrder[FCurrent] <> 0) then
  begin
    Dec(FCurrent);
  end;
  FPrimary := FirstOf(FOrder[FCurrent]);
end;

function TAtlasPlaceholderSession.FieldText(const AField: TAtlasPlaceholderField): string;
begin
  Result := Copy(FText, AField.Start + 1, AField.Length);
end;

class procedure TAtlasPlaceholderSession.Locate(const AText: string; AOffset: Integer; out ALine,
  ACharacter: Integer);
var
  mIndex, mLineStart: Integer;
begin
  ALine := 0;
  mLineStart := 0;
  if AOffset > Length(AText) then
  begin
    AOffset := Length(AText);
  end;
  for mIndex := 1 to AOffset do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(ALine);
      mLineStart := mIndex;
    end;
  end;
  ACharacter := AOffset - mLineStart;
end;

procedure TAtlasPlaceholderSession.Shift(AFrom, ADelta, AExcept: Integer);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FFields) do
  begin
    if (mIndex <> AExcept) and (FFields[mIndex].Start >= AFrom) then
    begin
      Inc(FFields[mIndex].Start, ADelta);
    end;
  end;
end;

function TAtlasPlaceholderSession.Update(const ADocument: string): Boolean;
var
  mChange: TTextChange;
  mIndex: Integer;
begin
  if ADocument = FText then
  begin
    Exit(True);
  end;
  Result := False;
  if CurrentNumber = 0 then
  begin
    Exit;
  end;
  mChange := ChangeOf(FText, ADocument);
  mIndex := FittingField(FFields, FPrimary, CurrentNumber, mChange);
  if mIndex < 0 then
  begin
    Exit;
  end;
  FPrimary := mIndex;
  Shift(FFields[FPrimary].Stop, mChange.Delta, FPrimary);
  // Eine leere Endposition direkt am Anfang des Platzhalters bleibt davor.
  Inc(FFields[FPrimary].Length, mChange.Delta);
  FText := ADocument;
  Result := True;
end;

function TAtlasPlaceholderSession.MirrorEdits: TAtlasPlaceholderEdits;
var
  mIndex, mInner: Integer;
  mValue: string;
  mEdit: TAtlasPlaceholderEdit;
begin
  Result := nil;
  if CurrentNumber = 0 then
  begin
    Exit;
  end;
  mValue := FieldText(FFields[FPrimary]);
  for mIndex := 0 to High(FFields) do
  begin
    if (mIndex <> FPrimary) and (FFields[mIndex].Number = CurrentNumber) and (FieldText(FFields[mIndex]) <> mValue) then
    begin
      mEdit.Start := FFields[mIndex].Start;
      mEdit.Stop := FFields[mIndex].Stop;
      mEdit.Text := mValue;
      Result := Result + [mEdit];
    end;
  end;
  // Aufsteigend: Verknüpfte Platzhalter außerhalb der Vorlage (#473) können vor ihr liegen.
  for mIndex := 1 to High(Result) do
  begin
    for mInner := mIndex downto 1 do
    begin
      if Result[mInner].Start < Result[mInner - 1].Start then
      begin
        mEdit := Result[mInner];
        Result[mInner] := Result[mInner - 1];
        Result[mInner - 1] := mEdit;
      end;
    end;
  end;
end;

procedure TAtlasPlaceholderSession.Applied(const AEdits: TAtlasPlaceholderEdits);
var
  mEdit: TAtlasPlaceholderEdit;
  mIndex, mOffset, mDelta: Integer;
begin
  // Rückwärts, damit die Offsets der früheren Änderungen gelten.
  for mIndex := High(AEdits) downto 0 do
  begin
    mEdit := AEdits[mIndex];
    mDelta := Length(mEdit.Text) - (mEdit.Stop - mEdit.Start);
    FText := Copy(FText, 1, mEdit.Start) + mEdit.Text + Copy(FText, mEdit.Stop + 1, MaxInt);
    for mOffset := 0 to High(FFields) do
    begin
      if (FFields[mOffset].Start = mEdit.Start) and (FFields[mOffset].Stop = mEdit.Stop) and
        (FFields[mOffset].Number = CurrentNumber) then
      begin
        FFields[mOffset].Length := Length(mEdit.Text);
      end
      else if FFields[mOffset].Start >= mEdit.Stop then
      begin
        Inc(FFields[mOffset].Start, mDelta);
      end;
    end;
  end;
end;

end.
