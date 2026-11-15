unit Atlas.Core.EditorToolbar.Plan;

// Atlas-Editorleiste (#1101), Entscheidungen ohne VCL und OTA (#1967):
// - Takt: ohne Leiste und ohne Rücksprungpunkte nur aufräumen; ohne aktiven
//   Editor bzw. mit der IDE im Hintergrund nur jeder SlowTicks-te Takt.
// - Platz der Leiste: in der Brotkrumenzeile (inBreadcrumbs, nur mit
//   Brotkrumen), über (aboveBreadcrumbs) oder unter den Brotkrumen; Breite in
//   der Brotkrumenzeile höchstens die halbe Zeile, mindestens MinWidth.
// - Knöpfe: Abschnittsbefehle und ihr Ziel, Hervorhebung im eigenen Abschnitt
//   (finalization zählt zu initialization), Tooltip ohne Ziel, Zustand aus den
//   Hooks (Befundpunkt an „Probleme“, Zurück, Vor), Text ohne „Atlas: “.
// - Sprünge: Ziel ins obere Drittel, Rücksprung auf das erste Zeichen der Zeile,
//   Zeilenverschiebung der Rücksprungpunkte ab der früheren Cursorzeile.

interface

uses
  System.SysUtils,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.EditorToolbar.Sections;

type
  TAtlasToolbarTick = (Clear, Wait, Run);
  TAtlasToolbarPlacement = (InBreadcrumbs, Below, Above);
  TAtlasToolbarHook = (None, Findings, Back, Forward);
  /// <summary>Tooltip eines gesperrten Abschnittsbefehls: Datei ohne interface/implementation bzw. ohne
  /// Abschnitt.</summary>
  TAtlasToolbarSectionHint = (NoParts, NoSection);

  TAtlasToolbarPlan = record
  public const
    cSlowTicks = 13;
    cPositionAbove = 'aboveBreadcrumbs';
    cPositionInline = 'inBreadcrumbs';
    cAtlasPrefix = 'Atlas: ';
    cProblemsId = 'Atlas.ProblemsWindow';
    cBackId = 'Atlas.NavBack';
    cForwardId = 'Atlas.NavForward';
    /// <summary>Mindestbreite in der Brotkrumenzeile bei 96 dpi.</summary>
    cInlineMinWidth = 120;
    cDesignPpi = 96;
    cTopPart = 3;
  public
    /// <summary>Was ein Takt tut; AIdle zählt die Takte ohne aktiven Editor (Run setzt ihn auf 0).</summary>
    class function Tick(AOn: Boolean; APointCount: Integer; AEditorActive: Boolean;
      var AIdle: Integer): TAtlasToolbarTick; static;
    class function PlacementOf(const APosition: string; AHasCrumbs: Boolean): TAtlasToolbarPlacement; static;
    /// <summary>Breite in der Brotkrumenzeile: so breit wie nötig, höchstens die halbe Zeile.</summary>
    class function InlineWidth(APreferred, AMinWidth, ACrumbsWidth: Integer): Integer; static;
    /// <summary>Neue Oberkante, wenn die Leiste auf der falschen Seite der Brotkrumen steht (alTop ordnet nach
    /// Top); False, wenn sie richtig steht.</summary>
    class function ReorderTop(APlacement: TAtlasToolbarPlacement; ABarTop, ACrumbsTop, ACrumbsHeight: Integer;
      out ATop: Integer): Boolean; static;
    class function PlainCaption(const ACaption: string): string; static;
    /// <summary>Sprungziel eines Abschnittsbefehls; False für andere Kennungen.</summary>
    class function SectionTargetOf(const AId: string; out ATarget: TAtlasSectionTarget): Boolean; static;
    class function SectionPressed(ATarget: TAtlasSectionTarget; ASection: TAtlasCodeSection): Boolean; static;
    class function SectionHint(ATarget: TAtlasSectionTarget): TAtlasToolbarSectionHint; static;
    class function HookOf(const AId: string): TAtlasToolbarHook; static;
    /// <summary>Oberste Zeile (1-basiert) für das Sprungziel AMarkLine (0-basiert) bei ARows sichtbaren Zeilen.
    /// </summary>
    class function TopRow(AMarkLine, ARows: Integer): Integer; static;
    /// <summary>Ziel des Rücksprungs in der Zeile AText: Spalte des ersten Zeichens, das kein Leerraum ist.</summary>
    class function ReturnColumn(const AText: string): Integer; static;
    /// <summary>Zeile, ab der eingefügte bzw. gelöschte Zeilen die Rücksprungpunkte verschieben.</summary>
    class function ShiftAnchor(ALine: Integer; ASameFile: Boolean; ALastLine: Integer): Integer; static;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Settings.ToolbarItems;

class function TAtlasToolbarPlan.Tick(AOn: Boolean; APointCount: Integer; AEditorActive: Boolean;
  var AIdle: Integer): TAtlasToolbarTick;
begin
  if not AOn and (APointCount = 0) then
  begin
    Exit(TAtlasToolbarTick.Clear);
  end;
  if not AEditorActive then
  begin
    Inc(AIdle);
    if AIdle < cSlowTicks then
    begin
      Exit(TAtlasToolbarTick.Wait);
    end;
  end;
  AIdle := 0;
  Result := TAtlasToolbarTick.Run;
end;

class function TAtlasToolbarPlan.PlacementOf(const APosition: string; AHasCrumbs: Boolean): TAtlasToolbarPlacement;
begin
  if SameText(APosition, cPositionInline) and AHasCrumbs then
  begin
    Result := TAtlasToolbarPlacement.InBreadcrumbs;
  end
  else if SameText(APosition, cPositionAbove) then
  begin
    Result := TAtlasToolbarPlacement.Above;
  end
  else
  begin
    Result := TAtlasToolbarPlacement.Below;
  end;
end;

class function TAtlasToolbarPlan.InlineWidth(APreferred, AMinWidth, ACrumbsWidth: Integer): Integer;
begin
  Result := Min(APreferred, Max(AMinWidth, ACrumbsWidth div 2));
end;

class function TAtlasToolbarPlan.ReorderTop(APlacement: TAtlasToolbarPlacement; ABarTop, ACrumbsTop,
  ACrumbsHeight: Integer; out ATop: Integer): Boolean;
begin
  ATop := ABarTop;
  if APlacement = TAtlasToolbarPlacement.Above then
  begin
    Result := ABarTop > ACrumbsTop;
    if Result then
    begin
      ATop := ACrumbsTop - 1;
    end;
    Exit;
  end;
  Result := ABarTop < ACrumbsTop;
  if Result then
  begin
    ATop := ACrumbsTop + ACrumbsHeight;
  end;
end;

class function TAtlasToolbarPlan.PlainCaption(const ACaption: string): string;
begin
  Result := ACaption;
  if Result.StartsWith(cAtlasPrefix) then
  begin
    Result := Copy(Result, Length(cAtlasPrefix) + 1, MaxInt);
  end;
end;

class function TAtlasToolbarPlan.SectionTargetOf(const AId: string; out ATarget: TAtlasSectionTarget): Boolean;
const
  cIds: array[TAtlasSectionTarget] of string = (TAtlasToolbarItems.cGotoInterface,
    TAtlasToolbarItems.cGotoImplementation, TAtlasToolbarItems.cGotoUses, TAtlasToolbarItems.cGotoInitialization);
var
  mTarget: TAtlasSectionTarget;
begin
  for mTarget := Low(TAtlasSectionTarget) to High(TAtlasSectionTarget) do
  begin
    if SameText(AId, cIds[mTarget]) then
    begin
      ATarget := mTarget;
      Exit(True);
    end;
  end;
  ATarget := TAtlasSectionTarget.InterfacePart;
  Result := False;
end;

class function TAtlasToolbarPlan.SectionPressed(ATarget: TAtlasSectionTarget; ASection: TAtlasCodeSection): Boolean;
begin
  case ATarget of
    TAtlasSectionTarget.InterfacePart:
      Result := ASection = TAtlasCodeSection.InterfacePart;
    TAtlasSectionTarget.ImplementationPart:
      Result := ASection = TAtlasCodeSection.ImplementationPart;
    TAtlasSectionTarget.UsesClause:
      Result := ASection = TAtlasCodeSection.UsesClause;
  else
    Result := (ASection = TAtlasCodeSection.Initialization_) or (ASection = TAtlasCodeSection.Finalization_);
  end;
end;

class function TAtlasToolbarPlan.SectionHint(ATarget: TAtlasSectionTarget): TAtlasToolbarSectionHint;
begin
  if ATarget in [TAtlasSectionTarget.InterfacePart, TAtlasSectionTarget.ImplementationPart] then
  begin
    Result := TAtlasToolbarSectionHint.NoParts;
  end
  else
  begin
    Result := TAtlasToolbarSectionHint.NoSection;
  end;
end;

class function TAtlasToolbarPlan.HookOf(const AId: string): TAtlasToolbarHook;
const
  cIds: array[TAtlasToolbarHook] of string = ('', cProblemsId, cBackId, cForwardId);
var
  mHook: TAtlasToolbarHook;
begin
  for mHook := Succ(TAtlasToolbarHook.None) to High(TAtlasToolbarHook) do
  begin
    if SameText(AId, cIds[mHook]) then
    begin
      Exit(mHook);
    end;
  end;
  Result := TAtlasToolbarHook.None;
end;

class function TAtlasToolbarPlan.TopRow(AMarkLine, ARows: Integer): Integer;
begin
  Result := Max(1, AMarkLine + 1 - Max(1, ARows) div cTopPart);
end;

class function TAtlasToolbarPlan.ReturnColumn(const AText: string): Integer;
begin
  Result := Length(AText) - Length(TrimLeft(AText));
end;

class function TAtlasToolbarPlan.ShiftAnchor(ALine: Integer; ASameFile: Boolean; ALastLine: Integer): Integer;
begin
  Result := ALine;
  if ASameFile and (ALastLine >= 0) then
  begin
    Result := Min(Result, ALastLine);
  end;
end;

end.
