unit Atlas.Core.Generate.Choice;

// Auswahl aus einer Liste mit Suchfeld (Assistenten der Objektgalerie, #1821),
// ohne VCL: Matches liefert die Indizes der Einträge, die jedes Wort der Suche
// enthalten (ohne Rücksicht auf Groß- und Kleinschreibung), in der Reihenfolge
// der Liste; eine leere Suche trifft alle. Den Dialog zeichnet
// Atlas.UI.Generate.Choice.

interface

type
  TAtlasChoiceFilter = class
  public
    /// <summary>Indizes der Einträge von AItems, die jedes Wort von ASearch enthalten.</summary>
    class function Matches(const AItems: TArray<string>; const ASearch: string): TArray<Integer>; static;
    /// <summary>Stelle von AIndex in AMatches; 0, wenn AIndex fehlt; -1 ohne Treffer.</summary>
    class function PositionOf(const AMatches: TArray<Integer>; AIndex: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils;

class function TAtlasChoiceFilter.Matches(const AItems: TArray<string>; const ASearch: string): TArray<Integer>;
var
  mWords: TArray<string>;
  mWord: string;
  mIndex: Integer;
  mHit: Boolean;
begin
  Result := nil;
  mWords := LowerCase(Trim(ASearch)).Split([' '], TStringSplitOptions.ExcludeEmpty);
  for mIndex := 0 to High(AItems) do
  begin
    mHit := True;
    for mWord in mWords do
    begin
      if Pos(mWord, LowerCase(AItems[mIndex])) = 0 then
      begin
        mHit := False;
        Break;
      end;
    end;
    if mHit then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

class function TAtlasChoiceFilter.PositionOf(const AMatches: TArray<Integer>; AIndex: Integer): Integer;
var
  mPosition: Integer;
begin
  if Length(AMatches) = 0 then
  begin
    Exit(-1);
  end;
  for mPosition := 0 to High(AMatches) do
  begin
    if AMatches[mPosition] = AIndex then
    begin
      Exit(mPosition);
    end;
  end;
  Result := 0;
end;

end.
