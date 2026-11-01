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
  if (AHour >= 5) and (AHour <= 10) then
    Result := TAtlasDayTime.Morning
  else if (AHour >= 11) and (AHour <= 17) then
    Result := TAtlasDayTime.Day
  else if (AHour >= 18) and (AHour <= 23) then
    Result := TAtlasDayTime.Evening
  else
    Result := TAtlasDayTime.Night;
end;

function Capitalized(const AText: string): string;
begin
  Result := AText;
  if Result <> '' then
    Result := UpperCase(Copy(Result, 1, 1)) + Copy(Result, 2, MaxInt);
end;

/// <summary>Erstes Wort bis zu einem der Trennzeichen.</summary>
function FirstWord(const AText: string; const ASeparators: array of Char): string;
var
  Index: Integer;
  Ch: Char;
begin
  Result := Trim(AText);
  for Index := 1 to Length(Result) do
    for Ch in ASeparators do
      if Result[Index] = Ch then
        Exit(Copy(Result, 1, Index - 1));
end;

class function TAtlasWelcomeGreeting.FirstName(const ADisplayName, AUserName: string): string;
var
  Name: string;
  Comma: Integer;
begin
  Name := Trim(ADisplayName);
  if Name <> '' then
  begin
    // „Nachname, Vorname“ (Active Directory).
    Comma := Pos(',', Name);
    if Comma > 0 then
      Name := Trim(Copy(Name, Comma + 1, MaxInt));
    Result := FirstWord(Name, [' ']);
    if Result <> '' then
      Exit;
  end;
  Name := Trim(AUserName);
  // Domäne bzw. UPN abschneiden.
  if LastDelimiter('\', Name) > 0 then
    Name := Copy(Name, LastDelimiter('\', Name) + 1, MaxInt);
  if Pos('@', Name) > 0 then
    Name := Copy(Name, 1, Pos('@', Name) - 1);
  Result := Capitalized(FirstWord(Name, ['.', '_', '-', ' ']));
end;

end.
