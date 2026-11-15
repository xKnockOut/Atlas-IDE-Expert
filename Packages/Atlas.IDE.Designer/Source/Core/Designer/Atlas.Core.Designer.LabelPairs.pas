unit Atlas.Core.Designer.LabelPairs;

// Label und Eingabefeld als Paar im Designer (#729), ohne VCL und Windows.
// - Paar: Label links neben dem Feld (Lücke 0 bis ADistance, senkrecht
//   überlappend) oder darüber (Lücke 0 bis ADistance, linke Kanten höchstens
//   ADistance auseinander); bei mehreren das nächste, links vor darüber.
// - Grundlinie: Ein Label links rückt so, dass seine Textgrundlinie auf der
//   des Felds liegt; darüber rückt seine linke Kante auf die Textkante im Feld.
// - Neues Label: Text aus dem Feldnamen ohne Präfix (kleine Buchstaben am
//   Anfang), Wörter an Großbuchstaben getrennt, Abkürzungen aus der Liste in
//   ihrer Schreibweise, mit Doppelpunkt: edtPlz → „PLZ:“, cbxZahlungsart →
//   „Zahlungsart:“; Name „lbl“ + Rest (lblPlz).
// - Tastenkürzel: erster Buchstabe der Caption, der in AUsed noch frei ist.
// - Mitziehen: Snapped (Lage am Feld), Follow (mit dem Feld verschoben);
//   NewSide/GapOf für neue Labels.

interface

uses
  System.Types;

type
{$SCOPEDENUMS ON}
  TAtlasPairSide = (None, Left, Above);
{$SCOPEDENUMS OFF}

  TAtlasPairMatch = record
    /// <summary>Index in den Feldern; -1 ohne Paar.</summary>
    Field: Integer;
    Side: TAtlasPairSide;
  end;

  TAtlasLabelPairs = class
  public const
    cDefaultAbbreviations = 'PLZ, IBAN, BIC, USt, ID';
    cLabelPrefix = 'lbl';
    /// <summary>Linke Textkante im Feld: Rahmen und Innenabstand bei 96 dpi.</summary>
    cTextIndent = 3;
    /// <summary>Abstand eines neuen Labels links vom Feld bzw. darüber.</summary>
    cLeftGap = 8;
    cAboveGap = 3;
  public
    /// <summary>Feld zu einem Label in ALabel; Field -1 ohne.</summary>
    class function FindField(const ALabel: TRect; const AFields: TArray<TRect>;
      ADistance: Integer): TAtlasPairMatch; static;
    /// <summary>Top des Labels, damit seine Grundlinie (ALabelAscent unter Top) auf AFieldBaseline liegt.</summary>
    class function BaselineTop(AFieldBaseline, ALabelAscent: Integer): Integer; static;
    /// <summary>Lage eines neuen Labels der Größe ASize links oder über dem Feld, AGap Abstand.</summary>
    class function Place(const AField: TRect; const ASize: TSize; ASide: TAtlasPairSide;
      AGap, AFieldBaseline, ALabelAscent: Integer): TPoint; static;
    /// <summary>Feldname ohne Präfix: edtPlz → Plz; ohne kleinen Anfang unverändert.</summary>
    class function StripPrefix(const AName: string): string; static;
    /// <summary>Caption für ein neues Label mit Doppelpunkt.</summary>
    class function CaptionFor(const AFieldName, AAbbreviations: string): string; static;
    /// <summary>Name für ein neues Label: lbl + Feldname ohne Präfix.</summary>
    class function NameFor(const AFieldName: string): string; static;
    /// <summary>Caption mit „&amp;“ vor dem ersten freien Buchstaben; leer, wenn schon eins da ist oder keiner
    /// frei.</summary>
    class function FreeAccelerator(const ACaption, AUsed: string): string; static;
    /// <summary>Tastenkürzel einer Caption (Zeichen nach dem ersten „&amp;“) als Großbuchstabe; leer ohne.</summary>
    class function AcceleratorOf(const ACaption: string): string; static;
    /// <summary>Lage des Labels ALabel an seinem Feld: darüber auf die Textkante, links auf die Grundlinie
    /// (ALabelAscent: Grundlinie unter Top; ohne Grundlinien, Werte unter 0, bleibt Top).</summary>
    class function Snapped(const ALabel, AField: TRect; ASide: TAtlasPairSide;
      ALabelAscent, AFieldBaseline: Integer): TPoint; static;
    /// <summary>Lage des Labels, wenn sein Feld von AOldField nach ANewField wandert: um denselben Weg.</summary>
    class function Follow(const ALabel, AOldField, ANewField: TRect): TPoint; static;
    /// <summary>Seite neuer Labels: darüber oder links (designer.labelPairs.newLabelPosition).</summary>
    class function NewSide(AAbove: Boolean): TAtlasPairSide; static;
    /// <summary>Abstand eines neuen Labels zur Seite ASide.</summary>
    class function GapOf(ASide: TAtlasPairSide): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Character;

{ TAtlasLabelPairs }

function LeftGap(const ALabel, AField: TRect; ADistance: Integer): Integer;
begin
  Result := AField.Left - ALabel.Right;
  if (Result < 0) or (Result > ADistance) or (ALabel.Top >= AField.Bottom) or (ALabel.Bottom <= AField.Top) then
  begin
    Result := -1;
  end;
end;

function AboveGap(const ALabel, AField: TRect; ADistance: Integer): Integer;
begin
  Result := AField.Top - ALabel.Bottom;
  if (Result < 0) or (Result > ADistance) or (Abs(ALabel.Left - AField.Left) > ADistance) then
  begin
    Result := -1;
  end;
end;

{ TAtlasLabelPairs }

class function TAtlasLabelPairs.FindField(const ALabel: TRect; const AFields: TArray<TRect>;
  ADistance: Integer): TAtlasPairMatch;
var
  mIndex, mGap, mBest: Integer;
begin
  Result.Field := -1;
  Result.Side := TAtlasPairSide.None;
  mBest := MaxInt;
  for mIndex := 0 to High(AFields) do
  begin
    mGap := LeftGap(ALabel, AFields[mIndex], ADistance);
    if (mGap >= 0) and ((mGap < mBest) or (Result.Side = TAtlasPairSide.Above)) then
    begin
      mBest := mGap;
      Result.Field := mIndex;
      Result.Side := TAtlasPairSide.Left;
      Continue;
    end;
    mGap := AboveGap(ALabel, AFields[mIndex], ADistance);
    if (mGap >= 0) and (mGap < mBest) and (Result.Side <> TAtlasPairSide.Left) then
    begin
      mBest := mGap;
      Result.Field := mIndex;
      Result.Side := TAtlasPairSide.Above;
    end;
  end;
end;

class function TAtlasLabelPairs.BaselineTop(AFieldBaseline, ALabelAscent: Integer): Integer;
begin
  Result := AFieldBaseline - ALabelAscent;
end;

class function TAtlasLabelPairs.Place(const AField: TRect; const ASize: TSize; ASide: TAtlasPairSide;
  AGap, AFieldBaseline, ALabelAscent: Integer): TPoint;
begin
  if ASide = TAtlasPairSide.Above then
  begin
    Result := Point(AField.Left + cTextIndent, AField.Top - AGap - ASize.cy);
  end
  else
  begin
    Result := Point(AField.Left - AGap - ASize.cx, BaselineTop(AFieldBaseline, ALabelAscent));
  end;
end;

class function TAtlasLabelPairs.StripPrefix(const AName: string): string;
var
  mIndex: Integer;
begin
  mIndex := 1;
  while (mIndex <= Length(AName)) and AName[mIndex].IsLower do
  begin
    Inc(mIndex);
  end;
  if (mIndex = 1) or (mIndex > Length(AName)) then
  begin
    Exit(AName);
  end;
  Result := Copy(AName, mIndex, MaxInt);
end;

/// <summary>Wörter an Großbuchstaben nach Kleinbuchstaben oder Ziffern getrennt.</summary>
function WordsOf(const AText: string): TArray<string>;
var
  mIndex, mStart: Integer;
begin
  Result := nil;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '_' then
    begin
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end
    else if (mIndex > mStart) and AText[mIndex].IsUpper and not AText[mIndex - 1].IsUpper then
    begin
      // Neues Wort ab einem Großbuchstaben nach einem kleinen (CamelCase).
      Result := Result + [Copy(AText, mStart, mIndex - mStart)];
      mStart := mIndex;
    end;
  end;
  Result := Result + [Copy(AText, mStart, MaxInt)];
end;

function Abbreviated(const AWord, AAbbreviations: string): string;
var
  mItem: string;
begin
  for mItem in AAbbreviations.Split([',', ';']) do
  begin
    if SameText(Trim(mItem), AWord) then
    begin
      Exit(Trim(mItem));
    end;
  end;
  Result := AWord;
end;

class function TAtlasLabelPairs.CaptionFor(const AFieldName, AAbbreviations: string): string;
var
  mWord: string;
begin
  Result := '';
  for mWord in WordsOf(StripPrefix(AFieldName)) do
  begin
    if mWord = '' then
    begin
      Continue;
    end;
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + Abbreviated(mWord, AAbbreviations);
  end;
  if Result <> '' then
  begin
    Result[1] := Result[1].ToUpper;
  end;
  Result := Result + ':';
end;

class function TAtlasLabelPairs.NameFor(const AFieldName: string): string;
begin
  Result := cLabelPrefix + StripPrefix(AFieldName);
end;

class function TAtlasLabelPairs.FreeAccelerator(const ACaption, AUsed: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  if Pos('&', ACaption) > 0 then
  begin
    Exit;
  end;
  for mIndex := 1 to Length(ACaption) do
  begin
    if ACaption[mIndex].IsLetter and (Pos(ACaption[mIndex].ToUpper, AUsed.ToUpper) = 0) then
    begin
      Exit(Copy(ACaption, 1, mIndex - 1) + '&' + Copy(ACaption, mIndex, MaxInt));
    end;
  end;
end;

class function TAtlasLabelPairs.AcceleratorOf(const ACaption: string): string;
var
  mPos: Integer;
begin
  Result := '';
  mPos := Pos('&', ACaption);
  if mPos > 0 then
  begin
    Result := UpperCase(Copy(ACaption, mPos + 1, 1));
  end;
end;

class function TAtlasLabelPairs.Snapped(const ALabel, AField: TRect; ASide: TAtlasPairSide;
  ALabelAscent, AFieldBaseline: Integer): TPoint;
begin
  Result := ALabel.TopLeft;
  if ASide = TAtlasPairSide.Above then
  begin
    Result.X := AField.Left + cTextIndent;
  end
  else if (ALabelAscent >= 0) and (AFieldBaseline >= 0) then
  begin
    Result.Y := BaselineTop(AFieldBaseline, ALabelAscent);
  end;
end;

class function TAtlasLabelPairs.Follow(const ALabel, AOldField, ANewField: TRect): TPoint;
begin
  Result := Point(ALabel.Left + ANewField.Left - AOldField.Left, ALabel.Top + ANewField.Top - AOldField.Top);
end;

class function TAtlasLabelPairs.NewSide(AAbove: Boolean): TAtlasPairSide;
begin
  Result := TAtlasPairSide.Left;
  if AAbove then
  begin
    Result := TAtlasPairSide.Above;
  end;
end;

class function TAtlasLabelPairs.GapOf(ASide: TAtlasPairSide): Integer;
begin
  Result := cLeftGap;
  if ASide = TAtlasPairSide.Above then
  begin
    Result := cAboveGap;
  end;
end;

end.
