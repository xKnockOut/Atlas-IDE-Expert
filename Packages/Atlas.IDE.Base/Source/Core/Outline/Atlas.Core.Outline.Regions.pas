unit Atlas.Core.Outline.Regions;

// Regionen am Caret für die Brotkrumenleiste (#1764), Kern ohne VCL und OTA:
// - Eine Region reicht von {$REGION 'Name'} bis zum Ende des passenden
//   {$ENDREGION}; ohne Ende bis zum Ende des Texts. Direktiven aus
//   TAtlasDirectiveScanner (Kommentare und Strings zählen nicht).
// - At liefert alle Regionen der Unit in Quelltextreihenfolge mit Tiefe und
//   die innerste Region um die Stelle. Ohne Text bleibt der Name leer; die
//   Anzeige ergänzt „Region (Z. n)“.

interface

uses
  Atlas.Core.Outline.Directives;

type
  TAtlasRegionMark = record
    /// <summary>Name ohne Anführungszeichen; leer bei {$REGION} ohne Text.</summary>
    Name: string;
    /// <summary>Anfang von {$REGION}, 0-basiert.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Hinter {$ENDREGION} bzw. Ende des Texts, 0-basiert.</summary>
    EndLine: Integer;
    EndCharacter: Integer;
    /// <summary>0 = äußerste.</summary>
    Depth: Integer;
  end;

  TAtlasRegionPlace = record
    /// <summary>Alle Regionen in Quelltextreihenfolge.</summary>
    Regions: TArray<TAtlasRegionMark>;
    /// <summary>Innerste Region um die Stelle; -1 außerhalb.</summary>
    Current: Integer;
  end;

  TAtlasRegionFinder = class
  public
    /// <summary>Regionen des Texts und die innerste um ALine/ACharacter (0-basiert).</summary>
    class function At(const ALines: TArray<string>; ALine, ACharacter: Integer): TAtlasRegionPlace; overload;
      static;
    /// <summary>Wie oben aus schon gelesenen Direktiven eines Texts mit ALineCount Zeilen (je Stand einmal
    /// gelesen, nicht je Caret-Stelle).</summary>
    class function At(const ADirectives: TAtlasDirectives; ALineCount, ALine, ACharacter: Integer): TAtlasRegionPlace;
      overload; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Outline.TypeText;

/// <summary>Name aus dem Argument von {$REGION}: ohne Anführungszeichen.</summary>
function RegionName(const AArgument: string): string;
begin
  Result := AArgument;
  if (Length(Result) >= 2) and (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2).Replace('''''', '''');
  end;
end;

/// <summary>Regionen aus den Direktiven; ohne {$ENDREGION} bis AEndLine.</summary>
function RegionsOf(const ADirectives: TAtlasDirectives; AEndLine: Integer): TArray<TAtlasRegionMark>;
var
  mDirective: TAtlasDirective;
  mOpen: TArray<Integer>;
  mRegion: TAtlasRegionMark;
begin
  Result := nil;
  mOpen := nil;
  for mDirective in ADirectives do
  begin
    if mDirective.Name = 'REGION' then
    begin
      mRegion.Name := RegionName(mDirective.Argument);
      mRegion.Line := mDirective.Line;
      mRegion.Character := mDirective.Character;
      mRegion.EndLine := AEndLine;
      mRegion.EndCharacter := 0;
      mRegion.Depth := Length(mOpen);
      Result := Result + [mRegion];
      mOpen := mOpen + [High(Result)];
    end
    else if (mDirective.Name = 'ENDREGION') and (Length(mOpen) > 0) then
    begin
      Result[mOpen[High(mOpen)]].EndLine := mDirective.EndLine;
      Result[mOpen[High(mOpen)]].EndCharacter := mDirective.EndCharacter;
      SetLength(mOpen, Length(mOpen) - 1);
    end;
  end;
end;

class function TAtlasRegionFinder.At(const ALines: TArray<string>; ALine, ACharacter: Integer): TAtlasRegionPlace;
begin
  Result := At(TAtlasDirectiveScanner.Scan(ALines), Length(ALines), ALine, ACharacter);
end;

class function TAtlasRegionFinder.At(const ADirectives: TAtlasDirectives; ALineCount, ALine,
  ACharacter: Integer): TAtlasRegionPlace;
var
  mIndex: Integer;
  mRegion: TAtlasRegionMark;
begin
  Result.Regions := RegionsOf(ADirectives, ALineCount);
  Result.Current := -1;
  for mIndex := 0 to High(Result.Regions) do
  begin
    mRegion := Result.Regions[mIndex];
    // Innere stehen hinter ihren äußeren: Die letzte passende ist die innerste.
    if not TAtlasTypeText.Before(ALine, ACharacter, mRegion.Line, mRegion.Character) and
      TAtlasTypeText.Before(ALine, ACharacter, mRegion.EndLine, mRegion.EndCharacter) then
    begin
      Result.Current := mIndex;
    end;
  end;
end;

end.
