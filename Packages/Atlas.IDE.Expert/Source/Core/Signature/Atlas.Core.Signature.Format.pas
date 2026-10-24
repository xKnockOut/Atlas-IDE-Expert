unit Atlas.Core.Signature.Format;

// Platzhalter im Parameter-Hint (#451), ohne Fenster: was die Hint-Zeile zum Eintrag am Cursor sagt und welche
// Stellen im Editor welche Farbe bekommen. Die Daten liefert der Server (TAtlasSignatureFormat).
// - Zeile: Problem zuerst (ungültiger Platzhalter, überzähliges Argument, Typkonflikt mit einem Literal), dann
//   der Platzhalter des Eintrags am Cursor („Platzhalter 2 von 2 erwartet ganzzahlig“), bei "*" Breite bzw.
//   Genauigkeit, ohne Platzhalter „kommt nicht vor“.
// - Farben: Platzhalter i und sein Argument bekommen Farbe i mod SlotCount; ein Argument, das nur Breite oder
//   Genauigkeit liefert, die Farbe seines Platzhalters. Nur einzeilige Stellen; leere Einträge nicht.

interface

uses
  System.SysUtils,
  Atlas.Core.Signature.Contract;

type
  {$SCOPEDENUMS ON}
  TAtlasFormatLineKind = (None, Placeholder, Width, Precision, Unused, Problem);
  {$SCOPEDENUMS OFF}

  /// <summary>Inhalt der Hint-Zeile; die Texte baut die Oberfläche.</summary>
  TAtlasFormatLine = record
    Kind: TAtlasFormatLineKind;
    /// <summary>Platzhalter ab 0 und ihre Zahl.</summary>
    Placeholder: Integer;
    Count: Integer;
    /// <summary>Typbuchstabe des Platzhalters bzw. "*" für Breite und Genauigkeit.</summary>
    TypeChar: Char;
    PlaceholderText: string;
    /// <summary>Argument ab 0 (Unused, Problem).</summary>
    Argument: Integer;
    Problem: TAtlasFormatProblem;
    /// <summary>Art des Literals beim Typkonflikt.</summary>
    ProblemKind: string;
    function IsError: Boolean;
  end;

  /// <summary>Eine einzufärbende Stelle in einer Zeile (Zeichen ab 0, Stop exklusiv).</summary>
  TAtlasFormatMark = record
    Line: Integer;
    Start: Integer;
    Stop: Integer;
    Slot: Integer;
  end;

  TAtlasSignatureFormats = record
  public const
    /// <summary>Zahl der Farben; danach wiederholen sie sich.</summary>
    SlotCount = 6;
  public
    /// <summary>Zeile zum Eintrag AArgument (-1 außerhalb der Liste: nur ein Problem).</summary>
    class function Line(const AFormat: TAtlasSignatureFormat; AArgument: Integer): TAtlasFormatLine; static;
    /// <summary>Alle einzufärbenden Stellen, nach Zeile und Anfang sortiert.</summary>
    class function Marks(const AFormat: TAtlasSignatureFormat): TArray<TAtlasFormatMark>; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

{ TAtlasFormatLine }

function TAtlasFormatLine.IsError: Boolean;
begin
  Result := Kind in [TAtlasFormatLineKind.Problem, TAtlasFormatLineKind.Unused];
end;

{ TAtlasSignatureFormats }

class function TAtlasSignatureFormats.Line(const AFormat: TAtlasSignatureFormat; AArgument: Integer): TAtlasFormatLine;
var
  Index: Integer;
  Placeholder: TAtlasFormatPlaceholder;
begin
  Result := Default(TAtlasFormatLine);
  Result.Placeholder := -1;
  Result.Argument := AArgument;
  Result.Count := Length(AFormat.Placeholders);
  if not AFormat.Found then
    Exit;
  if AFormat.Problem <> TAtlasFormatProblem.None then
  begin
    Result.Kind := TAtlasFormatLineKind.Problem;
    Result.Problem := AFormat.Problem;
    Result.Placeholder := AFormat.ProblemPlaceholder;
    Result.Argument := AFormat.ProblemArgument;
    Result.ProblemKind := AFormat.ProblemKind;
    if (Result.Placeholder >= 0) and (Result.Placeholder < Result.Count) then
    begin
      Result.TypeChar := AFormat.Placeholders[Result.Placeholder].TypeChar;
      Result.PlaceholderText := AFormat.Placeholders[Result.Placeholder].Text;
      // Konflikt beim "*": Breite bzw. Genauigkeit erwartet eine Ganzzahl.
      if (AFormat.Problem = TAtlasFormatProblem.TypeConflict) and
        (AFormat.Placeholders[Result.Placeholder].Argument <> Result.Argument) then
        Result.TypeChar := '*';
    end;
    Exit;
  end;
  if AArgument < 0 then
    Exit;
  for Index := 0 to High(AFormat.Placeholders) do
  begin
    Placeholder := AFormat.Placeholders[Index];
    if Placeholder.Argument = AArgument then
      Result.Kind := TAtlasFormatLineKind.Placeholder
    else if Placeholder.WidthArgument = AArgument then
      Result.Kind := TAtlasFormatLineKind.Width
    else if Placeholder.PrecisionArgument = AArgument then
      Result.Kind := TAtlasFormatLineKind.Precision
    else
      Continue;
    Result.Placeholder := Index;
    Result.PlaceholderText := Placeholder.Text;
    if Result.Kind = TAtlasFormatLineKind.Placeholder then
      Result.TypeChar := Placeholder.TypeChar
    else
      Result.TypeChar := '*';
    Exit;
  end;
  // Kein Platzhalter für diesen Eintrag (bei bekannter Zuordnung).
  if AFormat.ArgumentCount >= 0 then
    Result.Kind := TAtlasFormatLineKind.Unused;
end;

class function TAtlasSignatureFormats.Marks(const AFormat: TAtlasSignatureFormat): TArray<TAtlasFormatMark>;
var
  List: TList<TAtlasFormatMark>;
  Index: Integer;
  Placeholder: TAtlasFormatPlaceholder;
  Slots: TArray<Integer>;
  Range: TAtlasFormatRange;

  procedure Add(const ARange: TAtlasFormatRange; ASlot: Integer);
  var
    Mark: TAtlasFormatMark;
  begin
    if (ARange.StartLine <> ARange.EndLine) or (ARange.StartCharacter >= ARange.EndCharacter) or
      (ARange.StartLine < 0) then
      Exit;
    Mark.Line := ARange.StartLine;
    Mark.Start := ARange.StartCharacter;
    Mark.Stop := ARange.EndCharacter;
    Mark.Slot := ASlot mod SlotCount;
    List.Add(Mark);
  end;

  procedure Take(AArgument, APlaceholder: Integer);
  begin
    if (AArgument >= 0) and (AArgument <= High(Slots)) and (Slots[AArgument] < 0) then
      Slots[AArgument] := APlaceholder;
  end;

begin
  Result := nil;
  if not AFormat.Found then
    Exit;
  SetLength(Slots, Length(AFormat.Arguments));
  for Index := 0 to High(Slots) do
    Slots[Index] := -1;
  // Erst der Wert, dann Breite und Genauigkeit: ein Argument bekommt die Farbe des Platzhalters, den es füllt.
  for Index := 0 to High(AFormat.Placeholders) do
    Take(AFormat.Placeholders[Index].Argument, Index);
  for Index := 0 to High(AFormat.Placeholders) do
  begin
    Take(AFormat.Placeholders[Index].WidthArgument, Index);
    Take(AFormat.Placeholders[Index].PrecisionArgument, Index);
  end;
  List := TList<TAtlasFormatMark>.Create;
  try
    for Index := 0 to High(AFormat.Placeholders) do
    begin
      Placeholder := AFormat.Placeholders[Index];
      if Placeholder.Valid and Placeholder.HasRange then
        Add(Placeholder.Range, Index);
    end;
    for Index := 0 to High(AFormat.Arguments) do
    begin
      Range := AFormat.Arguments[Index];
      if Slots[Index] >= 0 then
        Add(Range, Slots[Index]);
    end;
    List.Sort(TComparer<TAtlasFormatMark>.Construct(
      function(const A, B: TAtlasFormatMark): Integer
      begin
        Result := A.Line - B.Line;
        if Result = 0 then
          Result := A.Start - B.Start;
        if Result = 0 then
          Result := A.Stop - B.Stop;
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
