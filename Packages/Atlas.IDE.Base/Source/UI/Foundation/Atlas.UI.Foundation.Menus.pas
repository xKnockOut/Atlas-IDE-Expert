unit Atlas.UI.Foundation.Menus;

// Einträge in Kontext- und Aufklappmenüs der Atlas-Fenster anlegen: Beschriftung, Tag und Klick in einem Aufruf.
// Der Eintrag gehört dem Menü bzw. dem angegebenen Besitzer und wird mit ihm freigegeben.

interface

uses
  System.Classes,
  Vcl.Menus;

type
  TAtlasMenus = class
  public
    /// <summary>Neuer Eintrag am Ende von AMenu.</summary>
    class function Add(AMenu: TPopupMenu; const ACaption: string; ATag: Integer;
      AClick: TNotifyEvent): TMenuItem; overload; static;
    /// <summary>Neuer Eintrag am Ende von AMenu mit Tag 0.</summary>
    class function Add(AMenu: TPopupMenu; const ACaption: string; AClick: TNotifyEvent): TMenuItem; overload;
      static;
    /// <summary>Neuer Eintrag am Ende von AParent (auch Untermenü), Besitzer AOwner.</summary>
    class function Add(AOwner: TComponent; AParent: TMenuItem; const ACaption: string; ATag: Integer;
      AClick: TNotifyEvent): TMenuItem; overload; static;
  end;

implementation

{ TAtlasMenus }

class function TAtlasMenus.Add(AMenu: TPopupMenu; const ACaption: string; ATag: Integer;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := Add(AMenu, AMenu.Items, ACaption, ATag, AClick);
end;

class function TAtlasMenus.Add(AMenu: TPopupMenu; const ACaption: string; AClick: TNotifyEvent): TMenuItem;
begin
  Result := Add(AMenu, AMenu.Items, ACaption, 0, AClick);
end;

class function TAtlasMenus.Add(AOwner: TComponent; AParent: TMenuItem; const ACaption: string; ATag: Integer;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AOwner);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AClick;
  AParent.Add(Result);
end;

end.
