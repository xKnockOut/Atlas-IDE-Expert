unit Atlas.Text.Timestamps;

// Zeitstempel der Form "yyyy-mm-dd hh:nn:ss" lesen (gemeinsam für Server und Plugin).
// Der eine Leser für Protokollzeilen, JSON-Dateien und Ausgaben von git/svn: Er prüft jede
// Ziffer selbst und kann darum keinen negativen Teil an TryEncodeDate/TryEncodeTime
// (Word-Parameter) weitergeben; mit Bereichsprüfung löste das sonst ERangeError aus statt False.

interface

type
  TTextTimestamp = class
  public
    /// <summary>Liest "yyyy-mm-dd hh:nn:ss" oder "yyyy-mm-ddThh:nn:ss" am Anfang von AText (Leerraum außen wird
    /// übergangen). Bruchteile der Sekunde (".123456") zählen bis auf Millisekunden; was danach folgt ("Z",
    /// "+01:00"), bleibt unbeachtet, die Zeitzone wird nicht umgerechnet. False bei anderer Form oder ungültigen
    /// Teilen, AStamp ist dann 0.</summary>
    class function TryParse(const AText: string; out AStamp: TDateTime): Boolean; static;
    /// <summary>Wie TryParse, aber 0 statt False.</summary>
    class function ParseOrZero(const AText: string): TDateTime; static;
    /// <summary>Liest das Datum "yyyy-mm-dd" am Anfang von AText (Leerraum außen wird übergangen); False bei anderer
    /// Form oder ungültigem Datum, ADate ist dann 0.</summary>
    class function TryParseDate(const AText: string; out ADate: TDateTime): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

const
  // Stellen in "yyyy-mm-ddThh:nn:ss.zzz".
  cYearDigits = 4;
  cPartDigits = 2;
  cMonthStart = 6;
  cDayStart = 9;
  cHourStart = 12;
  cMinuteStart = 15;
  cSecondStart = 18;
  cDateLength = 10;
  cStampLength = 19;
  cFractionStart = 20;
  cMilliDigits = 3;

/// <summary>ACount Ziffern ab AStart als Zahl; False, wenn eine fehlt oder keine Ziffer ist.</summary>
function TryDigits(const AText: string; AStart, ACount: Integer; out AValue: Word): Boolean;
var
  mIndex: Integer;
begin
  AValue := 0;
  Result := AStart + ACount - 1 <= Length(AText);
  mIndex := AStart;
  while Result and (mIndex < AStart + ACount) do
  begin
    Result := CharInSet(AText[mIndex], ['0'..'9']);
    if Result then
    begin
      AValue := AValue * 10 + Word(Ord(AText[mIndex]) - Ord('0'));
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Millisekunden aus ".ddd…" ab Position 20; weitere Stellen werden abgeschnitten. 0 ohne Punkt, False bei
/// einem Punkt ohne Ziffer.</summary>
function TryFraction(const AText: string; out AMilli: Word): Boolean;
var
  mIndex, mDigits: Integer;
begin
  AMilli := 0;
  Result := True;
  if (Length(AText) < cFractionStart) or (AText[cFractionStart] <> '.') then
  begin
    Exit;
  end;
  mIndex := cFractionStart + 1;
  mDigits := 0;
  while (mIndex <= Length(AText)) and CharInSet(AText[mIndex], ['0'..'9']) do
  begin
    if mDigits < cMilliDigits then
    begin
      AMilli := AMilli * 10 + Word(Ord(AText[mIndex]) - Ord('0'));
      Inc(mDigits);
    end;
    Inc(mIndex);
  end;
  Result := mIndex > cFractionStart + 1;
  while Result and (mDigits < cMilliDigits) do
  begin
    AMilli := AMilli * 10;
    Inc(mDigits);
  end;
end;

/// <summary>Trenner von "yyyy-mm-dd" an ihrer Stelle.</summary>
function IsDateShape(const AText: string): Boolean;
begin
  Result := (Length(AText) >= cDateLength) and (AText[cMonthStart - 1] = '-') and (AText[cDayStart - 1] = '-');
end;

/// <summary>Trenner von "yyyy-mm-ddThh:nn:ss" an ihrer Stelle, "T", "t" oder Leerzeichen zwischen Datum und Zeit.
/// </summary>
function IsStampShape(const AText: string): Boolean;
begin
  Result := (Length(AText) >= cStampLength) and IsDateShape(AText) and
    CharInSet(AText[cHourStart - 1], ['T', 't', ' ']) and (AText[cMinuteStart - 1] = ':') and
    (AText[cSecondStart - 1] = ':');
end;

function TryDatePart(const AText: string; out ADate: TDateTime): Boolean;
var
  mYear, mMonth, mDay: Word;
begin
  ADate := 0;
  Result := IsDateShape(AText) and TryDigits(AText, 1, cYearDigits, mYear) and
    TryDigits(AText, cMonthStart, cPartDigits, mMonth) and TryDigits(AText, cDayStart, cPartDigits, mDay) and
    TryEncodeDate(mYear, mMonth, mDay, ADate);
end;

function TryTimePart(const AText: string; out ATime: TDateTime): Boolean;
var
  mHour, mMinute, mSecond, mMilli: Word;
begin
  ATime := 0;
  Result := TryDigits(AText, cHourStart, cPartDigits, mHour) and
    TryDigits(AText, cMinuteStart, cPartDigits, mMinute) and TryDigits(AText, cSecondStart, cPartDigits, mSecond) and
    TryFraction(AText, mMilli) and
    TryEncodeTime(mHour, mMinute, mSecond, mMilli, ATime);
end;

{ TTextTimestamp }

class function TTextTimestamp.TryParse(const AText: string; out AStamp: TDateTime): Boolean;
var
  mText: string;
  mDate, mTime: TDateTime;
begin
  AStamp := 0;
  mText := Trim(AText);
  Result := IsStampShape(mText) and TryDatePart(mText, mDate) and TryTimePart(mText, mTime);
  if Result then
  begin
    AStamp := mDate + mTime;
  end;
end;

class function TTextTimestamp.ParseOrZero(const AText: string): TDateTime;
begin
  if not TryParse(AText, Result) then
  begin
    Result := 0;
  end;
end;

class function TTextTimestamp.TryParseDate(const AText: string; out ADate: TDateTime): Boolean;
begin
  Result := TryDatePart(Trim(AText), ADate);
end;

end.
