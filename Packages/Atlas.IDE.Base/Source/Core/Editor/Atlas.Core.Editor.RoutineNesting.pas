unit Atlas.Core.Editor.RoutineNesting;

// Lokale Routinen in Paarfarben und Blocklinien abheben (#1788). Die Tiefe eines Blocks zählt nur offene
// Blöcke; zwischen den Routinen ist keiner offen, also hätten lokale und äußere Routine dieselbe Farbe. Die
// Analyse (Atlas.Core.Editor.Pairs) liefert deshalb je Token und Block die Verschachtelung der Routine; hier
// wird daraus die Farbe:
// - outer:  wie bisher, nur die Tiefe zählt.
// - deeper: jede umschließende Routine zählt als weitere Stufe.
// - color:  lokale Routinen und alles darin in einer eigenen Farbe der Palette, Blocklinien gestrichelt.
// Das Band hinterlegt die Zeilen einer lokalen Routine (Kopf bis end) schwach in ihrer Farbe.

interface

uses
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.Pairs;

type
  /// <summary>Wie lokale Routinen gefärbt werden (highlight.nestedRoutines, #1788).</summary>
  TAtlasNestedRoutineStyle = (Outer, Deeper, OwnColor);

  /// <summary>Zeilen einer lokalen Routine vom Kopf bis zum end, 0-basiert (#1788).</summary>
  TAtlasRoutineBand = record
    FirstLine: Integer;
    LastLine: Integer;
    Depth: Integer;
    Routine: Integer;
  end;

  /// <summary>Färbung lokaler Routinen nach den Einstellungen (#1788).</summary>
  TAtlasRoutineNesting = record
  public const
    /// <summary>Namen in den Einstellungen, in der Reihenfolge von TAtlasNestedRoutineStyle.</summary>
    cStyleNames: array[TAtlasNestedRoutineStyle] of string = ('outer', 'deeper', 'color');
    /// <summary>Vorgabe von highlight.nestedRoutines.</summary>
    cDefaultStyle = TAtlasNestedRoutineStyle.Deeper;
  public
    Style: TAtlasNestedRoutineStyle;
    Band: Boolean;
    class function Create(const AStyleName: string; ABand: Boolean): TAtlasRoutineNesting; static;
    /// <summary>Aus highlight.nestedRoutines und highlight.nestedRoutineBand.</summary>
    class function FromSettings(const ASettings: TAtlasPluginSettings): TAtlasRoutineNesting; static;
    /// <summary>AColors (hell oder dunkel) mit den eigenen Paarfarben und der eigenen Farbe lokaler Routinen aus
    /// ASettings; eine Stelle für Editor und mitlaufenden Kopf.</summary>
    class function PairPalette(const AColors: TAtlasColors; const ASettings: TAtlasPluginSettings): TAtlasColors;
      static;
    /// <summary>Art zum Namen AName (Groß-/Kleinschreibung egal); unbekannt = DefaultStyle.</summary>
    class function StyleOf(const AName: string): TAtlasNestedRoutineStyle; static;
    /// <summary>Gültiger Name zu AName; unbekannt = Name der Vorgabe.</summary>
    class function NormalizeName(const AName: string): string; static;
    /// <summary>Tiefe für die Paarfarbe: mit Deeper um die Verschachtelung ARoutine erhöht.</summary>
    function Depth(ADepth, ARoutine: Integer): Integer;
    /// <summary>True, wenn ein Token bzw. Block der Verschachtelung ARoutine die eigene Farbe bekommt.</summary>
    function OwnColor(ARoutine: Integer): Boolean;
    /// <summary>Farbe eines Paars der Tiefe ADepth in der Verschachtelung ARoutine aus APalette.</summary>
    function Color(const APalette: TAtlasColors; ADepth, ARoutine: Integer): TAtlasColor;
    /// <summary>Bänder der lokalen Routinen aus ABlocks (nur Rümpfe mit ARoutine > 0); leer ohne Band.</summary>
    function Bands(const ABlocks: TArray<TAtlasPairBlock>): TArray<TAtlasRoutineBand>;
    /// <summary>Je Zeile (ALineCount Zeilen) das innerste Band aus ABands als Index, sonst -1.</summary>
    class function BandOfLines(const ABands: TArray<TAtlasRoutineBand>; ALineCount: Integer): TArray<Integer>;
      static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasRoutineNesting }

class function TAtlasRoutineNesting.Create(const AStyleName: string; ABand: Boolean): TAtlasRoutineNesting;
begin
  Result.Style := StyleOf(AStyleName);
  Result.Band := ABand;
end;

class function TAtlasRoutineNesting.FromSettings(const ASettings: TAtlasPluginSettings): TAtlasRoutineNesting;
begin
  Result := Create(ASettings.NestedRoutines, ASettings.NestedRoutineBand);
end;

class function TAtlasRoutineNesting.PairPalette(const AColors: TAtlasColors;
  const ASettings: TAtlasPluginSettings): TAtlasColors;
begin
  if AColors.IsDark then
  begin
    Result := AColors.WithPairs(ASettings.PairColorsDark).WithNestedRoutine(ASettings.NestedRoutineColorDark);
  end
  else
  begin
    Result := AColors.WithPairs(ASettings.PairColorsLight).WithNestedRoutine(ASettings.NestedRoutineColorLight);
  end;
end;

class function TAtlasRoutineNesting.StyleOf(const AName: string): TAtlasNestedRoutineStyle;
var
  mStyle: TAtlasNestedRoutineStyle;
begin
  for mStyle := Low(TAtlasNestedRoutineStyle) to High(TAtlasNestedRoutineStyle) do
  begin
    if SameText(Trim(AName), cStyleNames[mStyle]) then
    begin
      Exit(mStyle);
    end;
  end;
  Result := cDefaultStyle;
end;

class function TAtlasRoutineNesting.NormalizeName(const AName: string): string;
begin
  Result := cStyleNames[StyleOf(AName)];
end;

function TAtlasRoutineNesting.Depth(ADepth, ARoutine: Integer): Integer;
begin
  Result := ADepth;
  if Style = TAtlasNestedRoutineStyle.Deeper then
  begin
    Result := ADepth + Max(0, ARoutine);
  end;
end;

function TAtlasRoutineNesting.OwnColor(ARoutine: Integer): Boolean;
begin
  Result := (Style = TAtlasNestedRoutineStyle.OwnColor) and (ARoutine > 0);
end;

function TAtlasRoutineNesting.Color(const APalette: TAtlasColors; ADepth, ARoutine: Integer): TAtlasColor;
begin
  if OwnColor(ARoutine) then
  begin
    Exit(APalette.NestedRoutine);
  end;
  Result := APalette.Pairs[Depth(ADepth, ARoutine) mod Length(APalette.Pairs)];
end;

function TAtlasRoutineNesting.Bands(const ABlocks: TArray<TAtlasPairBlock>): TArray<TAtlasRoutineBand>;
var
  mBlock: TAtlasPairBlock;
  mBand: TAtlasRoutineBand;
begin
  Result := nil;
  if not Band then
  begin
    Exit;
  end;
  for mBlock in ABlocks do
  begin
    if mBlock.IsRoutine and (mBlock.Routine > 0) and (mBlock.CloseLine >= mBlock.OwnerLine) then
    begin
      mBand.FirstLine := Min(mBlock.OwnerLine, mBlock.OpenLine);
      mBand.LastLine := mBlock.CloseLine;
      mBand.Depth := mBlock.Depth;
      mBand.Routine := mBlock.Routine;
      Result := Result + [mBand];
    end;
  end;
end;

class function TAtlasRoutineNesting.BandOfLines(const ABands: TArray<TAtlasRoutineBand>;
  ALineCount: Integer): TArray<Integer>;
var
  mIndex, mLine: Integer;
begin
  Result := nil;
  SetLength(Result, Max(0, ALineCount));
  for mLine := 0 to High(Result) do
  begin
    Result[mLine] := -1;
  end;
  for mIndex := 0 to High(ABands) do
  begin
    for mLine := Max(0, ABands[mIndex].FirstLine) to Min(High(Result), ABands[mIndex].LastLine) do
    begin
      // Innerste gewinnt: die tiefere Verschachtelung.
      if (Result[mLine] < 0) or (ABands[Result[mLine]].Routine < ABands[mIndex].Routine) then
      begin
        Result[mLine] := mIndex;
      end;
    end;
  end;
end;

end.
