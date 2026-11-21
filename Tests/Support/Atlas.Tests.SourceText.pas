unit Atlas.Tests.SourceText;

// Testhilfe: Quelltexte für Tests zusammensetzen, Positionen von Markierungen bestimmen und prüfen, ob ein Text
// fehlerfrei parst. Viele Testunits hatten dafür eigene, wortgleiche Routinen.

interface

uses
  Atlas.Text.Lines;

type
  TTestSource = record
  public
    /// <summary>Zeilen mit #10 nach jeder Zeile, auch nach der letzten.</summary>
    class function Lines(const ALines: array of string): string; static;
    /// <summary>Position (Zeile und Zeichen ab 0) des ersten Vorkommens von AMarker; Ausnahme, wenn es fehlt.
    /// </summary>
    class function PositionOf(const AText, AMarker: string): TTextPosition; overload; static;
    /// <summary>Position des AOccurrence-ten Vorkommens (ab 1) von AMarker; Ausnahme, wenn es fehlt.</summary>
    class function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition; overload; static;
    /// <summary>Position direkt hinter dem ersten Vorkommen von AMarker (Schreibmarke); Ausnahme, wenn es fehlt.
    /// </summary>
    class function PositionAfter(const AText, AMarker: string): TTextPosition; static;
    /// <summary>Position des Zeichens AIndex (ab 1) in AText.</summary>
    class function PositionAt(const AText: string; AIndex: Integer): TTextPosition; static;
    /// <summary>AMarked ohne das erste "|"; APosition ist die Stelle, an der es stand.</summary>
    class function Unmark(const AMarked: string; out APosition: TTextPosition): string; static;
    /// <summary>Erste Zeile (ab 0) von AText, die AMarker enthält; prüft, dass es sie gibt.</summary>
    class function LineOf(const AText, AMarker: string): Integer; static;
    /// <summary>Anzahl der Syntaxfehler von AText.</summary>
    class function SyntaxErrors(const AText: string): Integer; static;
    /// <summary>AText parst ohne Syntaxfehler.</summary>
    class function Parses(const AText: string): Boolean; static;
    /// <summary>Prüft, dass AText ohne Syntaxfehler parst; die Meldung nennt den Text.</summary>
    class procedure AssertParses(const AText: string); static;
  end;

implementation

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache;

{ TTestSource }

class function TTestSource.Lines(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + mLine + #10;
  end;
end;

class function TTestSource.PositionOf(const AText, AMarker: string): TTextPosition;
begin
  Result := PositionOf(AText, AMarker, 1);
end;

class function TTestSource.PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  mIndex, mFound: Integer;
begin
  mFound := 0;
  mIndex := 0;
  repeat
    mIndex := Pos(AMarker, AText, mIndex + 1);
    if mIndex = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(mFound);
  until mFound >= AOccurrence;
  Result := PositionAt(AText, mIndex);
end;

class function TTestSource.PositionAfter(const AText, AMarker: string): TTextPosition;
var
  mIndex: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  Result := PositionAt(AText, mIndex + Length(AMarker));
end;

class function TTestSource.PositionAt(const AText: string; AIndex: Integer): TTextPosition;
var
  mIndex, mLine, mLineStart: Integer;
begin
  mLine := 0;
  mLineStart := 1;
  for mIndex := 1 to AIndex - 1 do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
      mLineStart := mIndex + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, AIndex - mLineStart);
end;

class function TTestSource.Unmark(const AMarked: string; out APosition: TTextPosition): string;
var
  mMarker: Integer;
begin
  mMarker := Pos('|', AMarked);
  APosition := PositionAt(AMarked, mMarker);
  Result := Copy(AMarked, 1, mMarker - 1) + Copy(AMarked, mMarker + 1, MaxInt);
end;

class function TTestSource.LineOf(const AText, AMarker: string): Integer;
var
  mLines: TArray<string>;
begin
  mLines := AText.Split([#10]);
  Result := 0;
  while (Result <= High(mLines)) and (Pos(AMarker, mLines[Result]) = 0) do
  begin
    Inc(Result);
  end;
  Assert.IsTrue(Result <= High(mLines), AMarker + ' nicht gefunden');
end;

class function TTestSource.SyntaxErrors(const AText: string): Integer;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := Length(mTree.Diagnostics);
  finally
    mTree.Free;
  end;
end;

class function TTestSource.Parses(const AText: string): Boolean;
begin
  Result := SyntaxErrors(AText) = 0;
end;

class procedure TTestSource.AssertParses(const AText: string);
begin
  Assert.AreEqual(0, SyntaxErrors(AText), AText);
end;

end.
