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

{ TAtlasPlaceholderField }

function TAtlasPlaceholderField.Stop: Integer;
begin
  Result := Start + Length;
end;

{ TAtlasPlaceholderSession }

constructor TAtlasPlaceholderSession.Create(const ADocument: string; AOffset: Integer;
  const AExpansion: TAtlasSnippetExpansion);
var
  Stop: TAtlasSnippetStop;
  Field: TAtlasPlaceholderField;
  Numbers: TArray<Integer>;
  Number, Index, Swap: Integer;
  HasEnd, Seen: Boolean;
begin
  inherited Create;
  FText := ADocument;
  HasEnd := False;
  Numbers := nil;
  for Stop in AExpansion.Stops do
  begin
    // Die Endposition gilt nur einmal (die erste).
    if Stop.Number = 0 then
      if HasEnd then
        Continue
      else
        HasEnd := True;
    Field.Number := Stop.Number;
    Field.Start := AOffset + Stop.Start;
    Field.Length := Stop.Length;
    FFields := FFields + [Field];
    Seen := False;
    for Number in Numbers do
      if Number = Stop.Number then
        Seen := True;
    if not Seen and (Stop.Number > 0) then
      Numbers := Numbers + [Stop.Number];
  end;
  if not HasEnd then
  begin
    Field.Number := 0;
    Field.Start := AOffset + System.Length(AExpansion.Text);
    Field.Length := 0;
    FFields := FFields + [Field];
  end;
  // Aufsteigend sortieren (wenige Einträge).
  for Index := 1 to High(Numbers) do
    for Number := Index downto 1 do
      if Numbers[Number] < Numbers[Number - 1] then
      begin
        Swap := Numbers[Number];
        Numbers[Number] := Numbers[Number - 1];
        Numbers[Number - 1] := Swap;
      end;
  FOrder := Numbers + [0];
  FCurrent := 0;
  FPrimary := FirstOf(FOrder[0]);
end;

function TAtlasPlaceholderSession.FirstOf(ANumber: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FFields) do
    if FFields[Index].Number = ANumber then
      Exit(Index);
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
  Field: TAtlasPlaceholderField;
begin
  Result := nil;
  for Field in FFields do
    if Field.Number > 0 then
      Result := Result + [Field];
end;

function TAtlasPlaceholderSession.FinalOffset: Integer;
begin
  Result := FFields[FirstOf(0)].Start;
end;

function TAtlasPlaceholderSession.Next: Boolean;
begin
  if FCurrent < High(FOrder) then
    Inc(FCurrent);
  FPrimary := FirstOf(FOrder[FCurrent]);
  Result := FOrder[FCurrent] <> 0;
end;

procedure TAtlasPlaceholderSession.Previous;
begin
  if (FCurrent > 0) and (FOrder[FCurrent] <> 0) then
    Dec(FCurrent);
  FPrimary := FirstOf(FOrder[FCurrent]);
end;

function TAtlasPlaceholderSession.FieldText(const AField: TAtlasPlaceholderField): string;
begin
  Result := Copy(FText, AField.Start + 1, AField.Length);
end;

class procedure TAtlasPlaceholderSession.Locate(const AText: string; AOffset: Integer; out ALine,
  ACharacter: Integer);
var
  Index, LineStart: Integer;
begin
  ALine := 0;
  LineStart := 0;
  if AOffset > Length(AText) then
    AOffset := Length(AText);
  for Index := 1 to AOffset do
    if AText[Index] = #10 then
    begin
      Inc(ALine);
      LineStart := Index;
    end;
  ACharacter := AOffset - LineStart;
end;

procedure TAtlasPlaceholderSession.Shift(AFrom, ADelta, AExcept: Integer);
var
  Index: Integer;
begin
  for Index := 0 to High(FFields) do
    if (Index <> AExcept) and (FFields[Index].Start >= AFrom) then
      Inc(FFields[Index].Start, ADelta);
end;

function TAtlasPlaceholderSession.Update(const ADocument: string): Boolean;
var
  Prefix, Suffix, OldLength, NewLength, Delta, Index, Limit: Integer;
  Field: TAtlasPlaceholderField;
begin
  if ADocument = FText then
    Exit(True);
  Result := False;
  if CurrentNumber = 0 then
    Exit;
  OldLength := Length(FText);
  NewLength := Length(ADocument);
  Delta := NewLength - OldLength;
  // Gleicher Anfang und gleiches Ende, unabhängig voneinander: Bei "aa" → "aaa" ist jede Stelle möglich.
  Limit := OldLength;
  if NewLength < Limit then
    Limit := NewLength;
  Prefix := 0;
  while (Prefix < Limit) and (FText[Prefix + 1] = ADocument[Prefix + 1]) do
    Inc(Prefix);
  Suffix := 0;
  while (Suffix < Limit) and (FText[OldLength - Suffix] = ADocument[NewLength - Suffix]) do
    Inc(Suffix);
  // Erst der Platzhalter mit dem Cursor, dann die übrigen der Nummer.
  for Index := -1 to High(FFields) do
  begin
    if Index < 0 then
      Field := FFields[FPrimary]
    else if (Index = FPrimary) or (FFields[Index].Number <> CurrentNumber) then
      Continue
    else
      Field := FFields[Index];
    if (Prefix >= Field.Start) and (Suffix >= OldLength - Field.Stop) and (Field.Length + Delta >= 0) then
    begin
      if Index >= 0 then
        FPrimary := Index;
      Shift(FFields[FPrimary].Stop, Delta, FPrimary);
      // Eine leere Endposition direkt am Anfang des Platzhalters bleibt davor.
      Inc(FFields[FPrimary].Length, Delta);
      FText := ADocument;
      Exit(True);
    end;
  end;
end;

function TAtlasPlaceholderSession.MirrorEdits: TAtlasPlaceholderEdits;
var
  Index: Integer;
  Value: string;
  Edit: TAtlasPlaceholderEdit;
begin
  Result := nil;
  if CurrentNumber = 0 then
    Exit;
  Value := FieldText(FFields[FPrimary]);
  for Index := 0 to High(FFields) do
    if (Index <> FPrimary) and (FFields[Index].Number = CurrentNumber) and (FieldText(FFields[Index]) <> Value) then
    begin
      Edit.Start := FFields[Index].Start;
      Edit.Stop := FFields[Index].Stop;
      Edit.Text := Value;
      Result := Result + [Edit];
    end;
end;

procedure TAtlasPlaceholderSession.Applied(const AEdits: TAtlasPlaceholderEdits);
var
  Edit: TAtlasPlaceholderEdit;
  Index, Offset, Delta: Integer;
begin
  // Rückwärts, damit die Offsets der früheren Änderungen gelten.
  for Index := High(AEdits) downto 0 do
  begin
    Edit := AEdits[Index];
    Delta := Length(Edit.Text) - (Edit.Stop - Edit.Start);
    FText := Copy(FText, 1, Edit.Start) + Edit.Text + Copy(FText, Edit.Stop + 1, MaxInt);
    for Offset := 0 to High(FFields) do
      if (FFields[Offset].Start = Edit.Start) and (FFields[Offset].Stop = Edit.Stop) and
        (FFields[Offset].Number = CurrentNumber) then
        FFields[Offset].Length := Length(Edit.Text)
      else if FFields[Offset].Start >= Edit.Stop then
        Inc(FFields[Offset].Start, Delta);
  end;
end;

end.
