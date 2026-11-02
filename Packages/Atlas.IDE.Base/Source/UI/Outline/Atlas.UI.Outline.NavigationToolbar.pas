unit Atlas.UI.Outline.NavigationToolbar;

// Navigationsleiste der IDE ausblenden (editor.breadcrumbsHideIdeToolbar):
// Über dem Editor steht die IDE-eigene Leiste mit „Typ suchen“ und „Methode
// suchen“. Die Open Tools API bietet keinen Zugang zu ihren Listen; füllen
// kann Atlas sie nicht. Die Brotkrumenleiste (#590) ersetzt sie (Menü am
// Unit-Glied, „›“ hinter Typen).
// Netz, nicht der Regelweg (Bericht M3): Ausgeblendet wird über die Option
// „Navigationssymbolleiste anzeigen“ der IDE (TAtlasIdeNavigationOption).
// Umhängen greift in das Editorfenster der IDE ein und läuft nur, wenn die
// IDE diese Option nicht hat oder ablehnt.
// - Gefunden wird das Steuerelement am Namen TEditorNavigationToolbar bzw.
//   am Klassennamen (…NavigationToolbar…).
// - Die IDE setzt Visible der Leiste bei jedem neuen Reiter wieder auf True.
//   Deshalb kommt die Leiste in ein eigenes, 0 Pixel hohes Panel an ihrer
//   Stelle; dieses Panel kennt die IDE nicht.
// - Restore bzw. Apply mit AHide = False hängt die Leiste an ihren alten
//   Platz zurück und gibt das Panel frei (Einstellung aus, Entladen).
// - Nach jedem Umhängen legt Atlas die Fenster von Halter und Leiste sofort
//   neu an. Sonst entstehen sie erst beim nächsten Zugriff, und den macht der
//   Parser-Thread der IDE (er aktualisiert die Leiste): Die Fenster gehörten
//   dann ihm, und jedes Popup unter dem IDE-Hauptfenster wartete auf diesen
//   Thread, solange er selbst wartet. Die IDE hing beim Klick in den Editor
//   oder aufs Statusfeld ohne Meldung.
// Nur VCL, keine Open Tools API; nur im Hauptthread.

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls;

type
  TAtlasNavigationToolbar = class(TComponent)
  private
    FPanels: TList<TWinControl>;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Navigationsleiste der IDE unter AParent (Fenster des Editors); nil = keine.</summary>
    class function Find(AParent: TWinControl): TWinControl; static;
    /// <summary>Ist AToolbar gerade von Atlas ausgeblendet?</summary>
    class function IsHidden(AToolbar: TControl): Boolean; static;
    /// <summary>Leiste unter AParent aus- bzw. wieder einblenden.</summary>
    procedure Apply(AParent: TWinControl; AHide: Boolean);
    /// <summary>Alle ausgeblendeten Leisten zurückhängen.</summary>
    procedure RestoreAll;
    /// <summary>Anzahl der Leisten, die Atlas gerade ausblendet.</summary>
    function HiddenCount: Integer;
  end;

implementation

uses
  System.SysUtils,
  Vcl.ExtCtrls;

const
  ToolbarName = 'TEditorNavigationToolbar';
  ToolbarClassPart = 'NAVIGATIONTOOLBAR';
  /// <summary>Tiefe der Suche im Fensterbaum.</summary>
  MaxSearchDepth = 8;

type
  /// <summary>Unsichtbarer Halter der IDE-Leiste.</summary>
  TToolbarHolder = class(TCustomPanel);

function IsToolbar(AControl: TControl): Boolean;
begin
  Result := SameText(AControl.Name, ToolbarName) or (Pos(ToolbarClassPart, UpperCase(AControl.ClassName)) > 0);
end;

{ TAtlasNavigationToolbar }

constructor TAtlasNavigationToolbar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPanels := TList<TWinControl>.Create;
end;

destructor TAtlasNavigationToolbar.Destroy;
begin
  RestoreAll;
  FPanels.Free;
  inherited Destroy;
end;

class function TAtlasNavigationToolbar.Find(AParent: TWinControl): TWinControl;

  function Search(AControl: TWinControl; ADepth: Integer): TWinControl;
  var
    Index: Integer;
    Child: TControl;
  begin
    Result := nil;
    if ADepth > MaxSearchDepth then
      Exit;
    for Index := 0 to AControl.ControlCount - 1 do
    begin
      Child := AControl.Controls[Index];
      if not (Child is TWinControl) then
        Continue;
      if IsToolbar(Child) then
        Exit(TWinControl(Child));
      Result := Search(TWinControl(Child), ADepth + 1);
      if Result <> nil then
        Exit;
    end;
  end;

begin
  Result := nil;
  if AParent <> nil then
    Result := Search(AParent, 0);
end;

class function TAtlasNavigationToolbar.IsHidden(AToolbar: TControl): Boolean;
begin
  Result := (AToolbar <> nil) and (AToolbar.Parent is TToolbarHolder);
end;

function TAtlasNavigationToolbar.HiddenCount: Integer;
begin
  Result := FPanels.Count;
end;

/// <summary>Fenster von AControl und allen Kindern jetzt im aufrufenden (Haupt-)Thread anlegen.</summary>
procedure OwnHandles(AControl: TWinControl);
var
  Index: Integer;
begin
  if (AControl = nil) or (AControl.Parent = nil) or not AControl.Parent.HandleAllocated then
    Exit;
  AControl.HandleNeeded;
  for Index := 0 to AControl.ControlCount - 1 do
    if AControl.Controls[Index] is TWinControl then
      OwnHandles(TWinControl(AControl.Controls[Index]));
end;

procedure TAtlasNavigationToolbar.Apply(AParent: TWinControl; AHide: Boolean);
var
  Toolbar: TWinControl;
  Holder: TToolbarHolder;
begin
  Toolbar := Find(AParent);
  if Toolbar = nil then
    Exit;
  if IsHidden(Toolbar) = AHide then
    Exit;
  if not AHide then
  begin
    Holder := TToolbarHolder(Toolbar.Parent);
    Toolbar.Parent := Holder.Parent;
    Toolbar.Top := Holder.Top;
    FPanels.Remove(Holder);
    Holder.Free;
    OwnHandles(Toolbar);
    Exit;
  end;
  // Halter an der Stelle der Leiste, damit die Reihenfolge der oben ausgerichteten Steuerelemente bleibt.
  Holder := TToolbarHolder.Create(nil);
  Holder.FreeNotification(Self);
  FPanels.Add(Holder);
  // Sichtbar, aber 0 Pixel hoch: Ein unsichtbarer Halter hätte kein Fenster, und das legte sonst der
  // Parser-Thread der IDE an (siehe oben); mit Fenster rutschte ein unsichtbarer Halter zudem nach oben.
  Holder.BevelOuter := bvNone;
  Holder.ShowCaption := False;
  Holder.Height := 0;
  Holder.Top := Toolbar.Top;
  Holder.Align := Toolbar.Align;
  Holder.Parent := Toolbar.Parent;
  Toolbar.Parent := Holder;
  OwnHandles(Holder);
end;

procedure TAtlasNavigationToolbar.RestoreAll;
var
  Holder: TWinControl;
  Toolbar: TControl;
begin
  while FPanels.Count > 0 do
  begin
    Holder := FPanels.Last;
    FPanels.Delete(FPanels.Count - 1);
    Holder.RemoveFreeNotification(Self);
    while Holder.ControlCount > 0 do
    begin
      Toolbar := Holder.Controls[0];
      Toolbar.Parent := Holder.Parent;
      Toolbar.Top := Holder.Top;
      if Toolbar is TWinControl then
        OwnHandles(TWinControl(Toolbar));
    end;
    Holder.Free;
  end;
end;

procedure TAtlasNavigationToolbar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FPanels <> nil) and (AComponent is TWinControl) then
    FPanels.Remove(TWinControl(AComponent));
end;

end.
