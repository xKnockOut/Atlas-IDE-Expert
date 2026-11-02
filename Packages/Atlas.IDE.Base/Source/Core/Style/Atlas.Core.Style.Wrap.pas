unit Atlas.Core.Style.Wrap;

// Umbruch an Leerzeichen über kumulierte Breiten (P-09): Die Breite eines
// Bereichs ist die Differenz zweier Präfixsummen; gemessen wird der Text nur
// einmal, nicht je Umbruchkandidat ab Zeilenanfang neu. Ohne VCL; die
// Präfixsummen liefert der Aufrufer (z. B. TAtlasStyledText.PrefixWidths).

interface

uses
  System.Types;

type
  TAtlasWrap = class
  public
    /// <summary>Zeilen (X = Start, Y = Stop exklusiv, 0-basiert) bei Umbruch hinter Leerzeichen.
    /// ACum[i] = Breite von AText[0..i), Länge Length(AText) + 1. Folgezeilen sind um AIndent schmaler;
    /// ein Wort, das allein nicht passt, steht allein. Leerer Text ergibt keine Zeile.</summary>
    class function AtSpaces(const AText: string; const ACum: TArray<Integer>; AWidth, AIndent: Integer):
      TArray<TPoint>; static;
  end;

implementation

class function TAtlasWrap.AtSpaces(const AText: string; const ACum: TArray<Integer>; AWidth, AIndent: Integer):
  TArray<TPoint>;
var
  Index, LineStart, Last, Limit, Count, Candidate: Integer;

  procedure Add(AStart, AStop: Integer);
  begin
    if Count = Length(Result) then
      SetLength(Result, 2 * Count + 4);
    Result[Count] := Point(AStart, AStop);
    Inc(Count);
  end;

  function Width(AFrom, ATill: Integer): Integer;
  begin
    Result := ACum[ATill] - ACum[AFrom];
  end;

  procedure Consider(ACandidate: Integer);
  begin
    if Count = 0 then
      Limit := AWidth
    else
      Limit := AWidth - AIndent;
    if (Last > LineStart) and (Width(LineStart, ACandidate) > Limit) then
    begin
      Add(LineStart, Last);
      LineStart := Last;
    end;
    Last := ACandidate;
  end;

begin
  Result := nil;
  Count := 0;
  if Length(ACum) < Length(AText) + 1 then
    Exit;
  LineStart := 0;
  Last := -1;
  // Kandidaten wie bisher: hinter jedem Leerzeichen (außer dem letzten Zeichen) und das Textende.
  for Index := 1 to Length(AText) - 1 do
    if AText[Index] = ' ' then
    begin
      Candidate := Index;
      Consider(Candidate);
    end;
  Consider(Length(AText));
  if LineStart < Length(AText) then
    Add(LineStart, Length(AText));
  SetLength(Result, Count);
end;

end.
