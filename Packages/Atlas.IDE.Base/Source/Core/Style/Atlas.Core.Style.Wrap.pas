unit Atlas.Core.Style.Wrap;

// Umbruch an Leerzeichen über kumulierte Breiten: Die Breite eines
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
  mIndex, mLineStart, mLast, mLimit, mCount, mCandidate: Integer;

  procedure Add(AStart, AStop: Integer);
  begin
    if mCount = Length(Result) then
    begin
      SetLength(Result, 2 * mCount + 4);
    end;
    Result[mCount] := Point(AStart, AStop);
    Inc(mCount);
  end;

  function Width(AFrom, ATill: Integer): Integer;
  begin
    Result := ACum[ATill] - ACum[AFrom];
  end;

  procedure Consider(ACandidate: Integer);
  begin
    if mCount = 0 then
    begin
      mLimit := AWidth;
    end
    else
    begin
      mLimit := AWidth - AIndent;
    end;
    if (mLast > mLineStart) and (Width(mLineStart, ACandidate) > mLimit) then
    begin
      Add(mLineStart, mLast);
      mLineStart := mLast;
    end;
    mLast := ACandidate;
  end;

begin
  Result := nil;
  mCount := 0;
  if Length(ACum) < Length(AText) + 1 then
  begin
    Exit;
  end;
  mLineStart := 0;
  mLast := -1;
  // Kandidaten wie bisher: hinter jedem Leerzeichen (außer dem letzten Zeichen) und das Textende.
  for mIndex := 1 to Length(AText) - 1 do
  begin
    if AText[mIndex] = ' ' then
    begin
      mCandidate := mIndex;
      Consider(mCandidate);
    end;
  end;
  Consider(Length(AText));
  if mLineStart < Length(AText) then
  begin
    Add(mLineStart, Length(AText));
  end;
  SetLength(Result, mCount);
end;

end.
