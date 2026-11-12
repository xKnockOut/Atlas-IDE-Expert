unit Atlas.IDE.Commands.ContextSubmenus;

// Untermenüs im Untermenü „Atlas“ des Editor-Kontextmenüs. Die IDE baut aus der
// registrierten Aktionsliste (INTAEditorLocalMenu.RegisterActionList) nur eine
// Ebene unter „Atlas“; Aktionen einer tieferen Kategorie hängt sie flach an,
// die Namen der Untermenüs standen dann als gewöhnliche Zeilen zwischen rund 50
// Einträgen. Deshalb registriert Atlas nur die erste Ebene und hängt die
// Einträge eines Untermenüs beim Öffnen von „Atlas“ selbst als TMenuItem an den
// Eintrag der Gruppe (Fill). Die Einträge gehören dem Eintrag der Gruppe und
// verschwinden mit ihm, wenn die IDE das Menü neu baut; sie sind mit den
// Aktionen verknüpft (Text, Kürzel, Sichtbarkeit, Aufruf).
// Meldet die IDE das Öffnen nicht, bleibt die Gruppe ohne Einträge; ein Klick
// darauf zeigt sie dann als eigenes Menü an der Maus (Popup).

interface

uses
  System.Classes,
  Vcl.Menus;

type
  TAtlasIdeContextSubmenus = record
  public
    /// <summary>Einträge von AParent durch je einen Eintrag für die Aktionen AActions ersetzen.</summary>
    class procedure Fill(AParent: TMenuItem; const AActions: TArray<TBasicAction>); static;
    /// <summary>AActions als eigenes Menü an der Maus zeigen; APopup wird bei Bedarf angelegt und wiederverwendet.
    /// </summary>
    class procedure Popup(var APopup: TPopupMenu; const AActions: TArray<TBasicAction>); static;
  end;

implementation

uses
  System.Types,
  Vcl.Controls;

class procedure TAtlasIdeContextSubmenus.Fill(AParent: TMenuItem; const AActions: TArray<TBasicAction>);
var
  mAction: TBasicAction;
  mItem: TMenuItem;
begin
  AParent.Clear;
  for mAction in AActions do
  begin
    mItem := TMenuItem.Create(AParent);
    mItem.Action := mAction;
    AParent.Add(mItem);
  end;
end;

class procedure TAtlasIdeContextSubmenus.Popup(var APopup: TPopupMenu; const AActions: TArray<TBasicAction>);
var
  mAt: TPoint;
begin
  if APopup = nil then
  begin
    APopup := TPopupMenu.Create(nil);
  end;
  Fill(APopup.Items, AActions);
  mAt := Mouse.CursorPos;
  APopup.Popup(mAt.X, mAt.Y);
end;

end.
