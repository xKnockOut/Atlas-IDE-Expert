unit Atlas.Core.Editor.Guides;

// Blocklinien in den Paarfarben (#514): Für jeden gepaarten Block über mehrere
// Zeilen eine senkrechte Linie vom Öffner bis zum Schließer, in der Farbe
// seiner Tiefe. Die Linie steht links vor dem Einzug der Öffnerzeile bzw. vor
// dem Schließer, wenn der weiter links steht (TFoo = class … end).
// Weil die Strukturhervorhebung der IDE dieselben Linien in eigenen Farben
// zeichnet, schaltet Atlas sie ab, solange die eigenen Linien an sind, und
// stellt sie wieder her, wenn sie aus sind. Die IDE liest den Schalter nur
// beim Start.
// Mit Besitzern (#653): Steht der Öffner allein am Zeilenanfang unter seiner
// Anweisung (if … then / begin), beginnt die Linie samt Haken an der Zeile der
// Anweisung und steht vor deren Einzug.

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
    /// <summary>Verschachtelung der Routine des Blocks (#1788).</summary>
    Routine: Integer;
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
    /// <summary>Wie Compute aus schon analysierten Blöcken; ALines sind die Zeilen des Texts (an #10
    /// getrennt).</summary>
    class function FromBlocks(const ALines: TArray<string>; const ABlocks: TArray<TAtlasPairBlock>;
      ATabWidth: Integer; AOwners: Boolean): TArray<TAtlasGuide>; overload; static;
    /// <summary>Wie oben mit AOwners = False.</summary>
    class function FromBlocks(const ALines: TArray<string>; const ABlocks: TArray<TAtlasPairBlock>;
      ATabWidth: Integer): TArray<TAtlasGuide>; overload; static;
    /// <summary>Stiftbreite in Pixeln: AWidth (1–3, bei 100 %) skaliert mit der Zeilenhöhe
    /// gegenüber ABaseCellHeight (Zeilenhöhe bei 100 %).</summary>
    class function PenWidth(AWidth, ACellHeight, ABaseCellHeight: Integer): Integer; static;
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
  mBlocks: TArray<TAtlasPairBlock>;
begin
  TAtlasPairs.Analyze(AText, mBlocks);
  Result := FromBlocks(AText.Split([#10]), mBlocks, ATabWidth);
end;

class function TAtlasGuides.FromBlocks(const ALines: TArray<string>; const ABlocks: TArray<TAtlasPairBlock>;
  ATabWidth: Integer): TArray<TAtlasGuide>;
begin
  Result := FromBlocks(ALines, ABlocks, ATabWidth, False);
end;

class function TAtlasGuides.FromBlocks(const ALines: TArray<string>; const ABlocks: TArray<TAtlasPairBlock>;
  ATabWidth: Integer; AOwners: Boolean): TArray<TAtlasGuide>;
var
  mBlock: TAtlasPairBlock;
  mGuide: TAtlasGuide;
  mDisplay: string;
  mIndent, mFirst: Integer;
begin
  Result := nil;
  for mBlock in ABlocks do
  begin
    if (mBlock.CloseLine <= mBlock.OpenLine) or (mBlock.CloseLine > High(ALines)) then
    begin
      Continue;
    end;
    mFirst := mBlock.OpenLine;
    // Öffner allein am Zeilenanfang unter seiner Anweisung: Linie ab der Anweisung.
    if AOwners and (mBlock.OwnerLine < mBlock.OpenLine) and (mBlock.OwnerLine >= 0) and
      (Trim(Copy(ALines[mBlock.OpenLine], 1, mBlock.OpenCharacter)) = '') then
    begin
      mFirst := mBlock.OwnerLine;
    end;
    mDisplay := TAtlasPairs.DisplayLine(ALines[mFirst], ATabWidth);
    mIndent := 1;
    while (mIndent <= Length(mDisplay)) and (mDisplay[mIndent] = ' ') do
    begin
      Inc(mIndent);
    end;
    mGuide.FirstLine := mFirst;
    mGuide.LastLine := mBlock.CloseLine;
    mGuide.Column := Min(mIndent, Length(TAtlasPairs.DisplayLine(Copy(ALines[mBlock.CloseLine], 1,
      mBlock.CloseCharacter), ATabWidth)) + 1);
    mGuide.Depth := mBlock.Depth;
    mGuide.Routine := mBlock.Routine;
    Result := Result + [mGuide];
  end;
end;

class function TAtlasGuides.PenWidth(AWidth, ACellHeight, ABaseCellHeight: Integer): Integer;
begin
  AWidth := EnsureRange(AWidth, 1, 3);
  if (ACellHeight <= 0) or (ABaseCellHeight <= 0) then
  begin
    Exit(AWidth);
  end;
  Result := Max(1, Round(AWidth * ACellHeight / ABaseCellHeight));
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
