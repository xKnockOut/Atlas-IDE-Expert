unit Atlas.Vcl.Controls.Menus;

// Einträge in Kontext- und Aufklappmenüs der Atlas-Fenster anlegen: Beschriftung, Tag und Klick in einem Aufruf.
// Der Eintrag gehört dem Menü bzw. dem angegebenen Besitzer und wird mit ihm freigegeben.
// Jeder Eintrag ist ein TAtlasCommandMenuItem: Sein Klick läuft als Befehl des Benutzers
// (TAtlasCommandScope), ein Fehler darin steht also sofort in der Meldungsansicht statt nur im Protokoll.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.Menus;

type
  /// <summary>Menüeintrag, dessen Klick als Befehl des Benutzers läuft (TAtlasCommandScope, Name aus der
  /// Beschriftung): Der erste Fehler darin und ein Aufruf unter einer abgeschalteten Funktion erscheinen sofort in
  /// der Meldungsansicht. Die Handler sichern sich weiter selbst über TAtlasGuard.Run.</summary>
  TAtlasCommandMenuItem = class(TMenuItem)
  public
    procedure Click; override;
  end;

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
    /// <summary>AMenu unter der linken unteren Ecke von AControl aufklappen.</summary>
    class procedure PopupBelow(AMenu: TPopupMenu; AControl: TControl); static;
  end;

implementation

uses
  System.Types,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Vcl.Controls.Helpers;

{ TAtlasCommandMenuItem }

procedure TAtlasCommandMenuItem.Click;
begin
  TAtlasCommandScope.Enter(Caption);
  try
    inherited Click;
  finally
    TAtlasCommandScope.Leave;
  end;
end;

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
  Result := TAtlasCommandMenuItem.Create(AOwner);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AClick;
  AParent.Add(Result);
end;

class procedure TAtlasMenus.PopupBelow(AMenu: TPopupMenu; AControl: TControl);
var
  mPoint: TPoint;
begin
  mPoint := TAtlasControls.BelowLeft(AControl);
  AMenu.Popup(mPoint.X, mPoint.Y);
end;

end.
