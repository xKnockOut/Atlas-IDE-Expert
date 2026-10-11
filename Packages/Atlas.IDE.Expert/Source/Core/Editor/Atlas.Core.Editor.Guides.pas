unit Atlas.Core.Editor.Guides;

// Blocklinien in den Paarfarben (#514): Für jeden gepaarten Block über mehrere
// Zeilen eine senkrechte Linie vom Öffner bis zum Schließer, in der Farbe
// seiner Tiefe. Die Linie steht links vor dem Einzug der Öffnerzeile bzw. vor
// dem Schließer, wenn der weiter links steht (TFoo = class … end).
// Weil die Strukturhervorhebung der IDE dieselben Linien in eigenen Farben
// zeichnet, schaltet Atlas sie ab, solange die eigenen Linien an sind, und
// stellt sie wieder her, wenn sie aus sind. Die IDE liest den Schalter nur
// beim Start.

interface

uses
  Atlas.Core.Editor.Pairs;

type
  TAtlasGuide = record
    /// <summary>0-basierte Zeilen von Öffner und Schließer.</summary>
    FirstLine: Integer;
    LastLine: Integer;
    /// <summary>1-basierte Editorspalte, vor der die Linie steht (Tabs aufgelöst).</summary>
    Column: Integer;
    Depth: Integer;
  end;

  /// <summary>Strukturhervorhebung der IDE und ob Atlas sie abgeschaltet hat.</summary>
  TAtlasIdeStructure = record
    Enabled: Boolean;
    DisabledByAtlas: Boolean;
  end;

  TAtlasGuides = class
  public
    /// <summary>Linien aller gepaarten Blöcke über mehrere Zeilen.</summary>
    class function Compute(const AText: string; ATabWidth: Integer): TArray<TAtlasGuide>; static;
    /// <summary>Wie Compute aus schon analysierten Blöcken; ALines sind die Zeilen des Texts (an #10 getrennt).</summary>
    class function FromBlocks(const ALines: TArray<string>; const ABlocks: TArray<TAtlasPairBlock>;
      ATabWidth: Integer): TArray<TAtlasGuide>; static;
    /// <summary>Neuer Zustand der IDE-Strukturhervorhebung: aus bei eigenen Linien,
    /// sonst wieder an, wenn Atlas sie abgeschaltet hatte.</summary>
    class function Switch(const AState: TAtlasIdeStructure; AOwnGuides: Boolean): TAtlasIdeStructure; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasGuides }

class function TAtlasGuides.Compute(const AText: string; ATabWidth: Integer): TArray<TAtlasGuide>;
var
  Blocks: TArray<TAtlasPairBlock>;
begin
  TAtlasPairs.Analyze(AText, Blocks);
  Result := FromBlocks(AText.Split([#10]), Blocks, ATabWidth);
end;

class function TAtlasGuides.FromBlocks(const ALines: TArray<string>; const ABlocks: TArray<TAtlasPairBlock>;
  ATabWidth: Integer): TArray<TAtlasGuide>;
var
  Block: TAtlasPairBlock;
  Guide: TAtlasGuide;
  Display: string;
  Indent: Integer;
begin
  Result := nil;
  for Block in ABlocks do
  begin
    if (Block.CloseLine <= Block.OpenLine) or (Block.CloseLine > High(ALines)) then
      Continue;
    Display := TAtlasPairs.DisplayLine(ALines[Block.OpenLine], ATabWidth);
    Indent := 1;
    while (Indent <= Length(Display)) and (Display[Indent] = ' ') do
      Inc(Indent);
    Guide.FirstLine := Block.OpenLine;
    Guide.LastLine := Block.CloseLine;
    Guide.Column := Min(Indent, Length(TAtlasPairs.DisplayLine(Copy(ALines[Block.CloseLine], 1,
      Block.CloseCharacter), ATabWidth)) + 1);
    Guide.Depth := Block.Depth;
    Result := Result + [Guide];
  end;
end;

class function TAtlasGuides.Switch(const AState: TAtlasIdeStructure; AOwnGuides: Boolean): TAtlasIdeStructure;
begin
  Result := AState;
  if AOwnGuides then
  begin
    if AState.Enabled then
    begin
      Result.Enabled := False;
      Result.DisabledByAtlas := True;
    end;
  end
  else if AState.DisabledByAtlas then
  begin
    // Nur zurückdrehen, was Atlas selbst abgeschaltet hat.
    Result.Enabled := True;
    Result.DisabledByAtlas := False;
  end;
end;

end.
