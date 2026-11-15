unit Atlas.Core.Editor.StickyPlan;

// Entscheidungen des mitlaufenden Kopfs (#506) ohne VCL und Open Tools API:
// welche Arten nach den Einstellungen eine eigene Kopfzeile bekommen, welche
// Anweisungsblöcke der Paaranalyse dazu zählen (#1230), welche Kopfzeile am
// Mauspunkt liegt, wann der Kopf nach einem Bildlauf ganz neu zu zeichnen ist,
// welcher Klick was auslöst und wohin eine Blocklinie im Kopf rückt.
// Zeichnen, Zeitgeber und Ereignisse bleiben in Atlas.IDE.Outline.StickyScroll.

{$SCOPEDENUMS ON}

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Editor.Pairs,
  Atlas.Core.Outline.StickyScroll;

type
  /// <summary>Was ein Mausklick auf den Kopf auslöst: nichts; Sprung zum Namen im Kopf; Strg+Klick (Sprung zur
  /// Definition des Bezeichners, wo der Kopf Quelltext zeigt).</summary>
  TAtlasStickyClick = (Ignore, Jump, Definition);

  /// <summary>Was ein Takt nach dem Stand der Gliederung tun muss: nichts; Kopf leeren (ohne Datei oder Server);
  /// neuen Stand übernehmen; nur neu zeichnen (Bildlauf ohne Malen der oberen Zeilen).</summary>
  TAtlasStickyRefresh = (Keep, Clear, Reload, Repaint);

  /// <summary>Wie der Kopf zuletzt gezeichnet steht: gezeichnete Zeilen, gerechnete Köpfe, Zeilenhöhe und linker
  /// Rand des Codebereichs (Pixel).</summary>
  TAtlasStickyGrid = record
    PaintedRows: Integer;
    RowCount: Integer;
    RowHeight: Integer;
    CodeLeft: Integer;
    class function Create(APaintedRows, ARowCount, ARowHeight, ACodeLeft: Integer): TAtlasStickyGrid; static;
  end;

  TAtlasStickyPlan = record
  public const
    /// <summary>So lange nach einem Strg+Klick auf den Kopf gilt Gehe zu Definition der IDE als dessen Folge.</summary>
    cCtrlClickMs = 2000;
    /// <summary>Abstand der Blocklinie links vom Codebereich, wie die Blocklinien des Editors.</summary>
    cGuideMargin = 4;
    /// <summary>Die Blocklinie steht mindestens so viele Pixel vor der Zelle, sonst ein Drittel der Zellbreite.
    /// </summary>
    cGuideMinGap = 2;
    cGuideGapPart = 3;
  public
    /// <summary>Arten mit eigener Kopfzeile nach den Einstellungen.</summary>
    class function Kinds(const ASettings: TAtlasPluginSettings): TAtlasStickyKinds; static;
    /// <summary>Wort aus Buchstaben ab AIndex (0-basiert) in ALine, klein.</summary>
    class function WordAt(const ALine: string; AIndex: Integer): string; static;
    /// <summary>Paar-Token je Zeile (ALineCount Zeilen); Token außerhalb fallen weg.</summary>
    class function PairsPerLine(const ATokens: TArray<TAtlasPairToken>;
      ALineCount: Integer): TArray<TArray<TAtlasPairToken>>; static;
    /// <summary>Blöcke, deren erstes Besitzerwort zu einer der Arten AKinds gehört (#1230).</summary>
    class function BranchesOf(const ABlocks: TArray<TAtlasPairBlock>; const ALines: TArray<string>;
      AKinds: TAtlasStickyKinds): TArray<TAtlasStickyBlock>; static;
    /// <summary>Anweisungsblöcke ab AMinLines Zeilen (vom Kopf bis zum end bzw. until).</summary>
    class function LongBranches(const ABranches: TArray<TAtlasStickyBlock>;
      AMinLines: Integer): TArray<TAtlasStickyBlock>; static;
    /// <summary>True, wenn AColumns die Spalte AColumn enthält.</summary>
    class function HasColumn(const AColumns: TArray<Integer>; AColumn: Integer): Boolean; static;
    /// <summary>Kopfzeile unter dem Mauspunkt AX, AY im Kopf AGrid; False außerhalb des Kopfs.</summary>
    class function RowAt(const AGrid: TAtlasStickyGrid; AX, AY: Integer; out ARow: Integer): Boolean; static;
    /// <summary>Bildschirmzeile (0-basiert) eines Zeilenrechtecks ab ATop mit Höhe AHeight (Mitte der Zeile).</summary>
    class function ScreenRow(ATop, AHeight: Integer): Integer; static;
    /// <summary>True, wenn der Editor beim Bildlauf nur einen Teil gemalt hat und alte Köpfe verschoben stehen:
    /// zuletzt ab APaintedTop gezeichnet (-1 = noch nie), jetzt ab ATop.</summary>
    class function Scrolled(APaintedTop, ATop, APaintedRows, ARowCount: Integer): Boolean; static;
    /// <summary>Schritt des Takts: ohne Datei oder Server (ANoSource) leeren, beim Warten (AWaiting) nichts tun,
    /// neuer Stand (AChanged) übernehmen; sonst nur neu zeichnen, wenn die oberste Zeile ungezeichnet wanderte und
    /// es etwas zu zeigen gibt.</summary>
    class function Refresh(ANoSource, AWaiting, AChanged, ATopMoved, AHasContent: Boolean): TAtlasStickyRefresh;
      static;
    /// <summary>Klick mit linker Taste (ALeft) und den Umschalttasten AShift, ACtrl, AAlt auf eine Kopfzeile.</summary>
    class function Click(ALeft, AShift, ACtrl, AAlt: Boolean): TAtlasStickyClick; static;
    /// <summary>True, wenn ein Strg+Klick auf den Kopf von ACtrlFile (zum Zeitpunkt ACtrlTick in ms) jetzt (ANow)
    /// noch für AFileName gilt.</summary>
    class function CtrlClickFresh(const ACtrlFile, AFileName: string; ACtrlTick, ANow: UInt64): Boolean; static;
    /// <summary>Spalte der Blocklinie in Pixeln vor der Zelle (ACellLeft, ACellWidth) bei Stiftbreite APenWidth;
    /// nicht links aus dem Codebereich ACodeLeft..ACodeRight (leer, wenn ACodeRight &lt;= ACodeLeft).</summary>
    class function GuideX(ACellLeft, ACellWidth, APenWidth, ACodeLeft, ACodeRight: Integer): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math;

{ TAtlasStickyGrid }

class function TAtlasStickyGrid.Create(APaintedRows, ARowCount, ARowHeight, ACodeLeft: Integer): TAtlasStickyGrid;
begin
  Result.PaintedRows := APaintedRows;
  Result.RowCount := ARowCount;
  Result.RowHeight := ARowHeight;
  Result.CodeLeft := ACodeLeft;
end;

{ TAtlasStickyPlan }

class function TAtlasStickyPlan.Kinds(const ASettings: TAtlasPluginSettings): TAtlasStickyKinds;
begin
  Result := [];
  if ASettings.StickyScrollTypes then
  begin
    Include(Result, TAtlasStickyKind.Types);
  end;
  if ASettings.StickyScrollRoutines then
  begin
    Include(Result, TAtlasStickyKind.Routines);
  end;
  if ASettings.StickyScrollBlocks then
  begin
    Include(Result, TAtlasStickyKind.Branches);
  end;
  if ASettings.StickyScrollLoops then
  begin
    Include(Result, TAtlasStickyKind.Loops);
  end;
  if ASettings.StickyScrollTry then
  begin
    Include(Result, TAtlasStickyKind.TryBlocks);
  end;
  if ASettings.StickyScrollCase then
  begin
    Include(Result, TAtlasStickyKind.CaseBlocks);
  end;
  if ASettings.StickyScrollWith then
  begin
    Include(Result, TAtlasStickyKind.WithBlocks);
  end;
end;

class function TAtlasStickyPlan.WordAt(const ALine: string; AIndex: Integer): string;
var
  mStop: Integer;
begin
  mStop := AIndex + 1;
  while (mStop <= Length(ALine)) and CharInSet(ALine[mStop], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(mStop);
  end;
  Result := LowerCase(Copy(ALine, AIndex + 1, mStop - AIndex - 1));
end;

class function TAtlasStickyPlan.PairsPerLine(const ATokens: TArray<TAtlasPairToken>;
  ALineCount: Integer): TArray<TArray<TAtlasPairToken>>;
var
  mToken: TAtlasPairToken;
  mCount: Integer;
begin
  Result := nil;
  SetLength(Result, Max(0, ALineCount));
  for mToken in ATokens do
  begin
    if (mToken.Line >= 0) and (mToken.Line <= High(Result)) then
    begin
      mCount := Length(Result[mToken.Line]);
      SetLength(Result[mToken.Line], mCount + 1);
      Result[mToken.Line][mCount] := mToken;
    end;
  end;
end;

class function TAtlasStickyPlan.BranchesOf(const ABlocks: TArray<TAtlasPairBlock>; const ALines: TArray<string>;
  AKinds: TAtlasStickyKinds): TArray<TAtlasStickyBlock>;
var
  mBlock: TAtlasPairBlock;
  mKind: TAtlasStickyKind;
  mCount: Integer;
begin
  Result := nil;
  for mBlock in ABlocks do
  begin
    if (mBlock.OwnerLine < 0) or (mBlock.OwnerLine > High(ALines)) then
    begin
      Continue;
    end;
    if TAtlasStickyScroll.OwnerKind(WordAt(ALines[mBlock.OwnerLine], mBlock.OwnerCharacter), mKind) and
      (mKind in AKinds) then
    begin
      mCount := Length(Result);
      SetLength(Result, mCount + 1);
      Result[mCount] := TAtlasStickyBlock.Create(mBlock.OwnerLine, mBlock.OwnerCharacter, mBlock.CloseLine);
    end;
  end;
end;

class function TAtlasStickyPlan.LongBranches(const ABranches: TArray<TAtlasStickyBlock>;
  AMinLines: Integer): TArray<TAtlasStickyBlock>;
var
  mBlock: TAtlasStickyBlock;
  mCount: Integer;
begin
  Result := nil;
  for mBlock in ABranches do
  begin
    if mBlock.EndLine - mBlock.Line + 1 >= AMinLines then
    begin
      mCount := Length(Result);
      SetLength(Result, mCount + 1);
      Result[mCount] := mBlock;
    end;
  end;
end;

class function TAtlasStickyPlan.HasColumn(const AColumns: TArray<Integer>; AColumn: Integer): Boolean;
var
  mColumn: Integer;
begin
  Result := False;
  for mColumn in AColumns do
  begin
    if mColumn = AColumn then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasStickyPlan.RowAt(const AGrid: TAtlasStickyGrid; AX, AY: Integer; out ARow: Integer): Boolean;
begin
  ARow := -1;
  Result := (AGrid.PaintedRows > 0) and (AGrid.RowHeight > 0) and (AY >= 0) and (AX >= AGrid.CodeLeft);
  if Result then
  begin
    ARow := AY div AGrid.RowHeight;
    Result := (ARow < AGrid.PaintedRows) and (ARow < AGrid.RowCount);
  end;
end;

class function TAtlasStickyPlan.ScreenRow(ATop, AHeight: Integer): Integer;
begin
  Result := -1;
  if AHeight > 0 then
  begin
    Result := (ATop + AHeight div 2) div AHeight;
  end;
end;

class function TAtlasStickyPlan.Scrolled(APaintedTop, ATop, APaintedRows, ARowCount: Integer): Boolean;
begin
  Result := (APaintedTop >= 0) and (ATop <> APaintedTop) and ((APaintedRows > 0) or (ARowCount > 0));
end;

class function TAtlasStickyPlan.Refresh(ANoSource, AWaiting, AChanged, ATopMoved,
  AHasContent: Boolean): TAtlasStickyRefresh;
begin
  if AWaiting then
  begin
    Exit(TAtlasStickyRefresh.Keep);
  end;
  if ANoSource then
  begin
    Exit(TAtlasStickyRefresh.Clear);
  end;
  if AChanged then
  begin
    Exit(TAtlasStickyRefresh.Reload);
  end;
  if ATopMoved and AHasContent then
  begin
    Exit(TAtlasStickyRefresh.Repaint);
  end;
  Result := TAtlasStickyRefresh.Keep;
end;

class function TAtlasStickyPlan.Click(ALeft, AShift, ACtrl, AAlt: Boolean): TAtlasStickyClick;
begin
  if not ALeft or AShift or AAlt then
  begin
    Exit(TAtlasStickyClick.Ignore);
  end;
  if ACtrl then
  begin
    Exit(TAtlasStickyClick.Definition);
  end;
  Result := TAtlasStickyClick.Jump;
end;

class function TAtlasStickyPlan.CtrlClickFresh(const ACtrlFile, AFileName: string; ACtrlTick, ANow: UInt64): Boolean;
begin
  Result := (ACtrlFile <> '') and SameText(ACtrlFile, AFileName) and (ANow >= ACtrlTick) and
    (ANow - ACtrlTick < cCtrlClickMs);
end;

class function TAtlasStickyPlan.GuideX(ACellLeft, ACellWidth, APenWidth, ACodeLeft, ACodeRight: Integer): Integer;
var
  mLeftmost: Integer;
begin
  Result := ACellLeft - Max(cGuideMinGap, ACellWidth div cGuideGapPart) - (APenWidth - 1) div 2;
  mLeftmost := ACodeLeft - cGuideMargin + APenWidth div 2;
  if (ACodeRight > ACodeLeft) and (Result < mLeftmost) then
  begin
    Result := mLeftmost;
  end;
end;

end.
