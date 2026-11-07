unit Atlas.Core.Welcome.Greeting;

// Grußzeile im Kopf der Atlas-Willkommensseite (#753), ohne VCL und Windows:
// Tageszeit aus der Stunde und Vorname aus dem Anzeigenamen bzw. dem
// Anmeldenamen des Windows-Kontos. Den Text („Guten Abend, Marco“) baut die
// UI-Schicht in der Sprache der IDE; der Name verlässt den Rechner nie.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Night 0–4 Uhr, Morning 5–10, Day 11–17, Evening 18–23.</summary>
  TAtlasDayTime = (Night, Morning, Day, Evening);
{$SCOPEDENUMS OFF}

  TAtlasWelcomeGreeting = class
  public
    class function DayTimeOf(AHour: Integer): TAtlasDayTime; static;
    /// <summary>Vorname aus ADisplayName („Marco Bähring“, „Bähring, Marco“), sonst aus AUserName
    /// („marco.baehring“, „DOMÄNE\marco“); '' ohne beides.</summary>
    class function FirstName(const ADisplayName, AUserName: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasWelcomeGreeting }

class function TAtlasWelcomeGreeting.DayTimeOf(AHour: Integer): TAtlasDayTime;
begin
  case AHour of
    5..10:
      Result := TAtlasDayTime.Morning;
    11..17:
      Result := TAtlasDayTime.Day;
    18..23:
      Result := TAtlasDayTime.Evening;
  else
    Result := TAtlasDayTime.Night;
  end;
end;

function Capitalized(const AText: string): string;
begin
  Result := AText;
  if Result <> '' then
  begin
    Result := UpperCase(Copy(Result, 1, 1)) + Copy(Result, 2, MaxInt);
  end;
end;

/// <summary>Erstes Wort bis zu einem der Trennzeichen.</summary>
function FirstWord(const AText: string; const ASeparators: array of Char): string;
var
  mIndex: Integer;
  mCh: Char;
begin
  Result := Trim(AText);
  for mIndex := 1 to Length(Result) do
  begin
    for mCh in ASeparators do
    begin
      if Result[mIndex] = mCh then
      begin
        Exit(Copy(Result, 1, mIndex - 1));
      end;
    end;
  end;
end;

class function TAtlasWelcomeGreeting.FirstName(const ADisplayName, AUserName: string): string;
var
  mName: string;
  mComma: Integer;
begin
  mName := Trim(ADisplayName);
  if mName <> '' then
  begin
    // „Nachname, Vorname“ (Active Directory).
    mComma := Pos(',', mName);
    if mComma > 0 then
    begin
      mName := Trim(Copy(mName, mComma + 1, MaxInt));
    end;
    Result := FirstWord(mName, [' ']);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  mName := Trim(AUserName);
  // Domäne bzw. UPN abschneiden.
  if LastDelimiter('\', mName) > 0 then
  begin
    mName := Copy(mName, LastDelimiter('\', mName) + 1, MaxInt);
  end;
  if Pos('@', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('@', mName) - 1);
  end;
  Result := Capitalized(FirstWord(mName, ['.', '_', '-', ' ']));
end;

end.
