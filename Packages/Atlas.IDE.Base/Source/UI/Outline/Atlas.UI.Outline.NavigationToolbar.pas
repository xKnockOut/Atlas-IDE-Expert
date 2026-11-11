unit Atlas.UI.Outline.NavigationToolbar;

// Navigationsleiste der IDE ausblenden (editor.breadcrumbsHideIdeToolbar):
// Über dem Editor steht die IDE-eigene Leiste mit „Typ suchen“ und „Methode
// suchen“. Die Open Tools API bietet keinen Zugang zu ihren Listen; füllen
// kann Atlas sie nicht. Die Brotkrumenleiste (#590) ersetzt sie (Menü am
// Unit-Glied, „›“ hinter Typen).
// Netz, nicht der Regelweg: Ausgeblendet wird über die Option
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
  cToolbarName = 'TEditorNavigationToolbar';
  cToolbarClassPart = 'NAVIGATIONTOOLBAR';
  /// <summary>Tiefe der Suche im Fensterbaum.</summary>
  cMaxSearchDepth = 8;

type
  /// <summary>Unsichtbarer Halter der IDE-Leiste.</summary>
  TToolbarHolder = class(TCustomPanel);

function IsToolbar(AControl: TControl): Boolean;
begin
  Result := SameText(AControl.Name, cToolbarName) or (Pos(cToolbarClassPart, UpperCase(AControl.ClassName)) > 0);
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
    mIndex: Integer;
    mChild: TControl;
  begin
    Result := nil;
    if ADepth > cMaxSearchDepth then
    begin
      Exit;
    end;
    for mIndex := 0 to AControl.ControlCount - 1 do
    begin
      mChild := AControl.Controls[mIndex];
      if not (mChild is TWinControl) then
      begin
        Continue;
      end;
      if IsToolbar(mChild) then
      begin
        Exit(TWinControl(mChild));
      end;
      Result := Search(TWinControl(mChild), ADepth + 1);
      if Result <> nil then
      begin
        Exit;
      end;
    end;
  end;

begin
  Result := nil;
  if AParent <> nil then
  begin
    Result := Search(AParent, 0);
  end;
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
  mIndex: Integer;
begin
  if (AControl = nil) or (AControl.Parent = nil) or not AControl.Parent.HandleAllocated then
  begin
    Exit;
  end;
  AControl.HandleNeeded;
  for mIndex := 0 to AControl.ControlCount - 1 do
  begin
    if AControl.Controls[mIndex] is TWinControl then
    begin
      OwnHandles(TWinControl(AControl.Controls[mIndex]));
    end;
  end;
end;

procedure TAtlasNavigationToolbar.Apply(AParent: TWinControl; AHide: Boolean);
var
  mToolbar: TWinControl;
  mHolder: TToolbarHolder;
begin
  mToolbar := Find(AParent);
  if mToolbar = nil then
  begin
    Exit;
  end;
  if IsHidden(mToolbar) = AHide then
  begin
    Exit;
  end;
  if not AHide then
  begin
    mHolder := TToolbarHolder(mToolbar.Parent);
    mToolbar.Parent := mHolder.Parent;
    mToolbar.Top := mHolder.Top;
    FPanels.Remove(mHolder);
    mHolder.Free;
    OwnHandles(mToolbar);
    Exit;
  end;
  // Halter an der Stelle der Leiste, damit die Reihenfolge der oben ausgerichteten Steuerelemente bleibt.
  mHolder := TToolbarHolder.Create(nil);
  mHolder.FreeNotification(Self);
  FPanels.Add(mHolder);
  // Sichtbar, aber 0 Pixel hoch: Ein unsichtbarer Halter hätte kein Fenster, und das legte sonst der
  // Parser-Thread der IDE an (siehe oben); mit Fenster rutschte ein unsichtbarer Halter zudem nach oben.
  mHolder.BevelOuter := bvNone;
  mHolder.ShowCaption := False;
  mHolder.Height := 0;
  mHolder.Top := mToolbar.Top;
  mHolder.Align := mToolbar.Align;
  mHolder.Parent := mToolbar.Parent;
  mToolbar.Parent := mHolder;
  OwnHandles(mHolder);
end;

procedure TAtlasNavigationToolbar.RestoreAll;
var
  mHolder: TWinControl;
  mToolbar: TControl;
begin
  while FPanels.Count > 0 do
  begin
    mHolder := FPanels.Last;
    FPanels.Delete(FPanels.Count - 1);
    mHolder.RemoveFreeNotification(Self);
    while mHolder.ControlCount > 0 do
    begin
      mToolbar := mHolder.Controls[0];
      mToolbar.Parent := mHolder.Parent;
      mToolbar.Top := mHolder.Top;
      if mToolbar is TWinControl then
      begin
        OwnHandles(TWinControl(mToolbar));
      end;
    end;
    mHolder.Free;
  end;
end;

procedure TAtlasNavigationToolbar.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (FPanels <> nil) and (AComponent is TWinControl) then
  begin
    FPanels.Remove(TWinControl(AComponent));
  end;
end;

end.
