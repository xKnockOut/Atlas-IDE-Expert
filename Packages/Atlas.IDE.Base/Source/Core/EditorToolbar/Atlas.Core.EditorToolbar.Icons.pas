unit Atlas.Core.EditorToolbar.Icons;

// Atlas-Editorleiste (#1101), Symbole je Befehl ohne VCL und OTA: IconOf
// ordnet bekannten Befehlen der Befehlspalette ein Symbol zu; unbekannte
// zeigen den ersten Buchstaben ihrer Beschriftung (Letter). Die Formen stehen
// in Atlas.Core.EditorToolbar.Glyphs.

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Symbole der Editorleiste (Atlas.Core.EditorToolbar.Glyphs); Letter = erster Buchstabe der
  /// Beschriftung.</summary>
  TAtlasToolbarIcon = (Letter, InterfacePart, ImplementationPart, UsesClause, Initialization_, Return, Back,
    Forward, Toggle, TestUnit, UnitSearch, FindMethod, QuickOpen, CodeActions, Format, Problems, Outline,
    Palette, More, Gear,
    // Designer-Leiste (#1442).
    ComponentSearch, NonVisual, NonVisualHidden, SelectParent, TabOrder, AlignControls,
    // Eigene Knöpfe der Designer-Ansichten (#605 bis #612).
    MeasureDistances, ResizePreview, ScalePreview, NameSuggest, NonVisualTray, DataBindings, ExtractFrame, EventMap,
    // Gleiche auswählen (#738), Anordnen (#730 ff.), Abstandsgriffe (#734), gemeinsame Größengriffe (#737),
    // Schnellleiste (#735).
    SelectSimilar, Arrange, GapHandles, MultiResize, SelectionBar);
{$SCOPEDENUMS OFF}

  TAtlasToolbarIcons = class
  public
    class function IconOf(const AId: string): TAtlasToolbarIcon; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.ToolbarItems;

class function TAtlasToolbarIcons.IconOf(const AId: string): TAtlasToolbarIcon;
const
  cIds: array[0..18] of string = (TAtlasToolbarItems.cGotoInterface, TAtlasToolbarItems.cGotoImplementation,
    TAtlasToolbarItems.cGotoUses, TAtlasToolbarItems.cGotoInitialization, TAtlasToolbarItems.cReturnFromSection,
    'Atlas.NavBack', 'Atlas.NavForward', 'Atlas.ToggleMethod', 'Atlas.SwitchTestUnit', 'Atlas.UnitSearch',
    TAtlasToolbarItems.cFindMethod, 'Atlas.QuickOpen', 'Atlas.CodeActions', 'Atlas.FormatCode',
    'Atlas.ProblemsWindow', 'Atlas.Outline', TAtlasToolbarItems.cCommandPalette, TAtlasToolbarItems.cCustomize,
    'Atlas.SymbolSearch');
  cIcons: array[0..18] of TAtlasToolbarIcon = (TAtlasToolbarIcon.InterfacePart,
    TAtlasToolbarIcon.ImplementationPart, TAtlasToolbarIcon.UsesClause, TAtlasToolbarIcon.Initialization_,
    TAtlasToolbarIcon.Return, TAtlasToolbarIcon.Back, TAtlasToolbarIcon.Forward, TAtlasToolbarIcon.Toggle,
    TAtlasToolbarIcon.TestUnit, TAtlasToolbarIcon.UnitSearch, TAtlasToolbarIcon.FindMethod,
    TAtlasToolbarIcon.QuickOpen, TAtlasToolbarIcon.CodeActions, TAtlasToolbarIcon.Format,
    TAtlasToolbarIcon.Problems, TAtlasToolbarIcon.Outline, TAtlasToolbarIcon.Palette, TAtlasToolbarIcon.Gear,
    TAtlasToolbarIcon.FindMethod);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(cIds) do
  begin
    if SameText(cIds[mIndex], AId) then
    begin
      Exit(cIcons[mIndex]);
    end;
  end;
  Result := TAtlasToolbarIcon.Letter;
end;

end.
