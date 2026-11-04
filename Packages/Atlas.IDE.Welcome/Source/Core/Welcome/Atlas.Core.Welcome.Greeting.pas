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
  begin
    Result := TAtlasDayTime.Morning;
  end
  else if (AHour >= 11) and (AHour <= 17) then
  begin
    Result := TAtlasDayTime.Day;
  end
  else if (AHour >= 18) and (AHour <= 23) then
  begin
    Result := TAtlasDayTime.Evening;
  end
  else
  begin
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
  Index: Integer;
  Ch: Char;
begin
  Result := Trim(AText);
  for Index := 1 to Length(Result) do
  begin
    for Ch in ASeparators do
    begin
      if Result[Index] = Ch then
      begin
        Exit(Copy(Result, 1, Index - 1));
      end;
    end;
  end;
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
    begin
      Name := Trim(Copy(Name, Comma + 1, MaxInt));
    end;
    Result := FirstWord(Name, [' ']);
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  Name := Trim(AUserName);
  // Domäne bzw. UPN abschneiden.
  if LastDelimiter('\', Name) > 0 then
  begin
    Name := Copy(Name, LastDelimiter('\', Name) + 1, MaxInt);
  end;
  if Pos('@', Name) > 0 then
  begin
    Name := Copy(Name, 1, Pos('@', Name) - 1);
  end;
  Result := Capitalized(FirstWord(Name, ['.', '_', '-', ' ']));
end;

end.
