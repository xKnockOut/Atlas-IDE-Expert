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
    cSlotCount = 6;
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

/// <summary>Zeile bei einem Problem des Formats.</summary>
procedure ProblemLine(const AFormat: TAtlasSignatureFormat; var ALine: TAtlasFormatLine);
begin
  ALine.Kind := TAtlasFormatLineKind.Problem;
  ALine.Problem := AFormat.Problem;
  ALine.Placeholder := AFormat.ProblemPlaceholder;
  ALine.Argument := AFormat.ProblemArgument;
  ALine.ProblemKind := AFormat.ProblemKind;
  if (ALine.Placeholder >= 0) and (ALine.Placeholder < ALine.Count) then
  begin
    ALine.TypeChar := AFormat.Placeholders[ALine.Placeholder].TypeChar;
    ALine.PlaceholderText := AFormat.Placeholders[ALine.Placeholder].Text;
    // Konflikt beim "*": Breite bzw. Genauigkeit erwartet eine Ganzzahl.
    if (AFormat.Problem = TAtlasFormatProblem.TypeConflict) and
      (AFormat.Placeholders[ALine.Placeholder].Argument <> ALine.Argument) then
    begin
      ALine.TypeChar := '*';
    end;
  end;
end;

/// <summary>Was AArgument für APlaceholder liefert; None, wenn nichts.</summary>
function RoleOf(const APlaceholder: TAtlasFormatPlaceholder; AArgument: Integer): TAtlasFormatLineKind;
begin
  if APlaceholder.Argument = AArgument then
  begin
    Result := TAtlasFormatLineKind.Placeholder;
  end
  else if APlaceholder.WidthArgument = AArgument then
  begin
    Result := TAtlasFormatLineKind.Width;
  end
  else if APlaceholder.PrecisionArgument = AArgument then
  begin
    Result := TAtlasFormatLineKind.Precision;
  end
  else
  begin
    Result := TAtlasFormatLineKind.None;
  end;
end;

/// <summary>Zeile zum Eintrag AArgument ohne Problem: sein Platzhalter oder (bei bekannter Zuordnung) Unused.
/// </summary>
procedure ArgumentLine(const AFormat: TAtlasSignatureFormat; AArgument: Integer; var ALine: TAtlasFormatLine);
var
  mIndex: Integer;
  mKind: TAtlasFormatLineKind;
begin
  for mIndex := 0 to High(AFormat.Placeholders) do
  begin
    mKind := RoleOf(AFormat.Placeholders[mIndex], AArgument);
    if mKind <> TAtlasFormatLineKind.None then
    begin
      ALine.Kind := mKind;
      ALine.Placeholder := mIndex;
      ALine.PlaceholderText := AFormat.Placeholders[mIndex].Text;
      ALine.TypeChar := '*';
      if mKind = TAtlasFormatLineKind.Placeholder then
      begin
        ALine.TypeChar := AFormat.Placeholders[mIndex].TypeChar;
      end;
      Exit;
    end;
  end;
  // Kein Platzhalter für diesen Eintrag (bei bekannter Zuordnung).
  if AFormat.ArgumentCount >= 0 then
  begin
    ALine.Kind := TAtlasFormatLineKind.Unused;
  end;
end;

/// <summary>Platzhalter, dessen Farbe ein Argument bekommt; -1 ohne. Erst der Wert, dann Breite und
/// Genauigkeit: ein Argument bekommt die Farbe des Platzhalters, den es füllt.</summary>
function SlotsOf(const AFormat: TAtlasSignatureFormat): TArray<Integer>;

  procedure Take(var ASlots: TArray<Integer>; AArgument, APlaceholder: Integer);
  begin
    if (AArgument >= 0) and (AArgument <= High(ASlots)) and (ASlots[AArgument] < 0) then
    begin
      ASlots[AArgument] := APlaceholder;
    end;
  end;

var
  mIndex: Integer;
begin
  SetLength(Result, Length(AFormat.Arguments));
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := -1;
  end;
  for mIndex := 0 to High(AFormat.Placeholders) do
  begin
    Take(Result, AFormat.Placeholders[mIndex].Argument, mIndex);
  end;
  for mIndex := 0 to High(AFormat.Placeholders) do
  begin
    Take(Result, AFormat.Placeholders[mIndex].WidthArgument, mIndex);
    Take(Result, AFormat.Placeholders[mIndex].PrecisionArgument, mIndex);
  end;
end;

/// <summary>Nur einzeilige, nicht leere Stellen.</summary>
procedure AddMark(var AMarks: TArray<TAtlasFormatMark>; const ARange: TAtlasFormatRange; ASlot: Integer);
var
  mMark: TAtlasFormatMark;
begin
  if (ARange.StartLine <> ARange.EndLine) or (ARange.StartCharacter >= ARange.EndCharacter) or
    (ARange.StartLine < 0) then
  begin
    Exit;
  end;
  mMark.Line := ARange.StartLine;
  mMark.Start := ARange.StartCharacter;
  mMark.Stop := ARange.EndCharacter;
  mMark.Slot := ASlot mod TAtlasSignatureFormats.cSlotCount;
  AMarks := AMarks + [mMark];
end;

function MarkOrder(const A, B: TAtlasFormatMark): Integer;
begin
  Result := A.Line - B.Line;
  if Result = 0 then
  begin
    Result := A.Start - B.Start;
  end;
  if Result = 0 then
  begin
    Result := A.Stop - B.Stop;
  end;
end;

{ TAtlasSignatureFormats }

class function TAtlasSignatureFormats.Line(const AFormat: TAtlasSignatureFormat; AArgument: Integer): TAtlasFormatLine;
begin
  Result := Default(TAtlasFormatLine);
  Result.Placeholder := -1;
  Result.Argument := AArgument;
  Result.Count := Length(AFormat.Placeholders);
  if not AFormat.Found then
  begin
    Exit;
  end;
  if AFormat.Problem <> TAtlasFormatProblem.None then
  begin
    ProblemLine(AFormat, Result);
  end
  else if AArgument >= 0 then
  begin
    ArgumentLine(AFormat, AArgument, Result);
  end;
end;

class function TAtlasSignatureFormats.Marks(const AFormat: TAtlasSignatureFormat): TArray<TAtlasFormatMark>;
var
  mIndex: Integer;
  mPlaceholder: TAtlasFormatPlaceholder;
  mSlots: TArray<Integer>;
begin
  Result := nil;
  if not AFormat.Found then
  begin
    Exit;
  end;
  mSlots := SlotsOf(AFormat);
  for mIndex := 0 to High(AFormat.Placeholders) do
  begin
    mPlaceholder := AFormat.Placeholders[mIndex];
    if mPlaceholder.Valid and mPlaceholder.HasRange then
    begin
      AddMark(Result, mPlaceholder.Range, mIndex);
    end;
  end;
  for mIndex := 0 to High(AFormat.Arguments) do
  begin
    if mSlots[mIndex] >= 0 then
    begin
      AddMark(Result, AFormat.Arguments[mIndex], mSlots[mIndex]);
    end;
  end;
  TArray.Sort<TAtlasFormatMark>(Result, TComparer<TAtlasFormatMark>.Construct(MarkOrder));
end;

end.
