unit Argus.Core.Editor.Guides;

// Blocklinien in den Paarfarben (#514): Für jeden gepaarten Block über mehrere
// Zeilen eine senkrechte Linie vom Öffner bis zum Schließer, in der Farbe
// seiner Tiefe. Die Linie steht links vor dem Einzug der Öffnerzeile bzw. vor
// dem Schließer, wenn der weiter links steht (TFoo = class … end).
// Weil die Strukturhervorhebung der IDE dieselben Linien in eigenen Farben
// zeichnet, schaltet Argus sie ab, solange die eigenen Linien an sind, und
// stellt sie wieder her, wenn sie aus sind. Die IDE liest den Schalter nur
// beim Start.

interface

uses
  Argus.Core.Editor.Pairs;

type
  TArgusGuide = record
    /// <summary>0-basierte Zeilen von Öffner und Schließer.</summary>
    FirstLine: Integer;
    LastLine: Integer;
    /// <summary>1-basierte Editorspalte, vor der die Linie steht (Tabs aufgelöst).</summary>
    Column: Integer;
    Depth: Integer;
  end;

  /// <summary>Strukturhervorhebung der IDE und ob Argus sie abgeschaltet hat.</summary>
  TArgusIdeStructure = record
    Enabled: Boolean;
    DisabledByArgus: Boolean;
  end;

  TArgusGuides = class
  public
    /// <summary>Linien aller gepaarten Blöcke über mehrere Zeilen.</summary>
    class function Compute(const AText: string; ATabWidth: Integer): TArray<TArgusGuide>; static;
    /// <summary>Wie Compute aus schon analysierten Blöcken; ALines sind die Zeilen des Texts (an #10 getrennt).</summary>
    class function FromBlocks(const ALines: TArray<string>; const ABlocks: TArray<TArgusPairBlock>;
      ATabWidth: Integer): TArray<TArgusGuide>; static;
    /// <summary>Neuer Zustand der IDE-Strukturhervorhebung: aus bei eigenen Linien,
    /// sonst wieder an, wenn Argus sie abgeschaltet hatte.</summary>
    class function Switch(const AState: TArgusIdeStructure; AOwnGuides: Boolean): TArgusIdeStructure; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TArgusGuides }

class function TArgusGuides.Compute(const AText: string; ATabWidth: Integer): TArray<TArgusGuide>;
var
  Blocks: TArray<TArgusPairBlock>;
begin
  TArgusPairs.Analyze(AText, Blocks);
  Result := FromBlocks(AText.Split([#10]), Blocks, ATabWidth);
end;

class function TArgusGuides.FromBlocks(const ALines: TArray<string>; const ABlocks: TArray<TArgusPairBlock>;
  ATabWidth: Integer): TArray<TArgusGuide>;
var
  Block: TArgusPairBlock;
  Guide: TArgusGuide;
  Display: string;
  Indent: Integer;
begin
  Result := nil;
  for Block in ABlocks do
  begin
    if (Block.CloseLine <= Block.OpenLine) or (Block.CloseLine > High(ALines)) then
      Continue;
    Display := TArgusPairs.DisplayLine(ALines[Block.OpenLine], ATabWidth);
    Indent := 1;
    while (Indent <= Length(Display)) and (Display[Indent] = ' ') do
      Inc(Indent);
    Guide.FirstLine := Block.OpenLine;
    Guide.LastLine := Block.CloseLine;
    Guide.Column := Min(Indent, Length(TArgusPairs.DisplayLine(Copy(ALines[Block.CloseLine], 1,
      Block.CloseCharacter), ATabWidth)) + 1);
    Guide.Depth := Block.Depth;
    Result := Result + [Guide];
  end;
end;

class function TArgusGuides.Switch(const AState: TArgusIdeStructure; AOwnGuides: Boolean): TArgusIdeStructure;
begin
  Result := AState;
  if AOwnGuides then
  begin
    if AState.Enabled then
    begin
      Result.Enabled := False;
      Result.DisabledByArgus := True;
    end;
  end
  else if AState.DisabledByArgus then
  begin
    // Nur zurückdrehen, was Argus selbst abgeschaltet hat.
    Result.Enabled := True;
    Result.DisabledByArgus := False;
  end;
end;

end.
