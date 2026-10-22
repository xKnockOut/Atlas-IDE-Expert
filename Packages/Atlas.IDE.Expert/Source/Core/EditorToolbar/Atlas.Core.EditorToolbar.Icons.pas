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
    Palette, More, Gear);
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
  Ids: array[0..18] of string = (TAtlasToolbarItems.GotoInterface, TAtlasToolbarItems.GotoImplementation,
    TAtlasToolbarItems.GotoUses, TAtlasToolbarItems.GotoInitialization, TAtlasToolbarItems.ReturnFromSection,
    'Atlas.NavBack', 'Atlas.NavForward', 'Atlas.ToggleMethod', 'Atlas.SwitchTestUnit', 'Atlas.UnitSearch',
    TAtlasToolbarItems.FindMethod, 'Atlas.QuickOpen', 'Atlas.CodeActions', 'Atlas.FormatCode',
    'Atlas.ProblemsWindow', 'Atlas.Outline', TAtlasToolbarItems.CommandPalette, TAtlasToolbarItems.Customize,
    'Atlas.SymbolSearch');
  Icons: array[0..18] of TAtlasToolbarIcon = (TAtlasToolbarIcon.InterfacePart,
    TAtlasToolbarIcon.ImplementationPart, TAtlasToolbarIcon.UsesClause, TAtlasToolbarIcon.Initialization_,
    TAtlasToolbarIcon.Return, TAtlasToolbarIcon.Back, TAtlasToolbarIcon.Forward, TAtlasToolbarIcon.Toggle,
    TAtlasToolbarIcon.TestUnit, TAtlasToolbarIcon.UnitSearch, TAtlasToolbarIcon.FindMethod,
    TAtlasToolbarIcon.QuickOpen, TAtlasToolbarIcon.CodeActions, TAtlasToolbarIcon.Format,
    TAtlasToolbarIcon.Problems, TAtlasToolbarIcon.Outline, TAtlasToolbarIcon.Palette, TAtlasToolbarIcon.Gear,
    TAtlasToolbarIcon.FindMethod);
var
  Index: Integer;
begin
  for Index := 0 to High(Ids) do
    if SameText(Ids[Index], AId) then
      Exit(Icons[Index]);
  Result := TAtlasToolbarIcon.Letter;
end;

end.
