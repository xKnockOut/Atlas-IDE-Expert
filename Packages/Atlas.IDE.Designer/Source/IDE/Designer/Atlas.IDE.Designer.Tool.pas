unit Atlas.IDE.Designer.Tool;

// Gemeinsame Basis der Designer-Werkzeuge in der IDE: Meldungen in die
// Meldungsansicht (Say), Umrisse über dem Designer (Outlines, erst beim
// ersten Gebrauch angelegt), Farben nach dem IDE-Thema (ApplyTheme) und die
// Tasten des Werkzeugs (OwnKeys, beim Freigeben abgemeldet). Damit steht das
// nicht wortgleich in jedem Werkzeug. Werkzeuge mit weiteren Fenstern
// ergänzen ApplyTheme über ThemeWindow. Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Menus,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.UI.Designer.Overlay,
  Atlas.UI.Designer.Outlines;

type
  TAtlasIdeDesignerTool = class
  private
    FOnMessage: TProc<string>;
    FOutlines: TAtlasDesignerOutlines;
    FKeyClient: TAtlasKeyClient;
  protected
    /// <summary>Tasten des Werkzeugs: Die Basis übernimmt AKeys, meldet ihn beim Freigeben ab und gibt ihn frei.
    /// </summary>
    procedure OwnKeys(AKeys: TAtlasKeyClient);
    /// <summary>Tasten aus OwnKeys beim Tastatur-Hook an- (AWanted) bzw. abmelden.</summary>
    procedure HookKeys(AWanted: Boolean);
    /// <summary>Zeile in der Meldungsansicht.</summary>
    procedure Say(const AText: string); virtual;
    /// <summary>Umrisse über dem Designer; beim ersten Aufruf angelegt.</summary>
    function Outlines: TAtlasDesignerOutlines;
    /// <summary>Sind die Umrisse schon angelegt?</summary>
    function HasOutlines: Boolean;
    /// <summary>Umrisse AOutlines (Lage im Client von ARoot) über dem Client von ARoot zeigen.</summary>
    procedure ShowOutlinesIn(ARoot: TWinControl; const AOutlines: TArray<TAtlasOutline>);
    /// <summary>Farben des IDE-Themas an das weitere Fenster AWindow des Werkzeugs (nil: noch nicht angelegt).
    /// </summary>
    class procedure ThemeWindow(AWindow: TAtlasDesignerOverlay); static;
    /// <summary>Eintrag ACaption mit ATag und Haken AChecked am Ende von AMenu; Klick an AOnClick.</summary>
    class function AddMenuItem(AMenu: TPopupMenu; const ACaption: string; ATag: Integer; AChecked: Boolean;
      AOnClick: TNotifyEvent): TMenuItem; static;
    /// <summary>Fenster, dem die Fenster der Werkzeuge gehören (Hauptfenster der IDE).</summary>
    class function OwnerWindow: HWND; static;
    property OnMessage: TProc<string> read FOnMessage;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht (darf nil sein).</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Farben nach dem IDE-Thema.</summary>
    procedure ApplyTheme; virtual;
    /// <summary>Umrisse ausblenden, falls angelegt.</summary>
    procedure HideOutlines; virtual;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.IDE.Foundation.EditorStyle;

{ TAtlasIdeDesignerTool }

constructor TAtlasIdeDesignerTool.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

destructor TAtlasIdeDesignerTool.Destroy;
begin
  if FKeyClient <> nil then
  begin
    TAtlasKeyHook.Remove(FKeyClient);
    FKeyClient.Free;
  end;
  FOutlines.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDesignerTool.OwnKeys(AKeys: TAtlasKeyClient);
begin
  FKeyClient := AKeys;
end;

procedure TAtlasIdeDesignerTool.HookKeys(AWanted: Boolean);
begin
  if AWanted then
  begin
    TAtlasKeyHook.Add(FKeyClient);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeyClient);
  end;
end;

procedure TAtlasIdeDesignerTool.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

function TAtlasIdeDesignerTool.Outlines: TAtlasDesignerOutlines;
begin
  if FOutlines = nil then
  begin
    FOutlines := TAtlasDesignerOutlines.CreateOutlines(nil, OwnerWindow, TAtlasIdeStyle.Colors);
  end;
  Result := FOutlines;
end;

function TAtlasIdeDesignerTool.HasOutlines: Boolean;
begin
  Result := FOutlines <> nil;
end;

procedure TAtlasIdeDesignerTool.HideOutlines;
begin
  if FOutlines <> nil then
  begin
    FOutlines.HideOutlines;
  end;
end;

procedure TAtlasIdeDesignerTool.ShowOutlinesIn(ARoot: TWinControl; const AOutlines: TArray<TAtlasOutline>);
var
  mArea: TRect;
begin
  mArea := ARoot.ClientRect;
  mArea.Offset(ARoot.ClientOrigin);
  Outlines.ShowOutlines(mArea, AOutlines);
end;

class procedure TAtlasIdeDesignerTool.ThemeWindow(AWindow: TAtlasDesignerOverlay);
begin
  if AWindow <> nil then
  begin
    AWindow.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

class function TAtlasIdeDesignerTool.AddMenuItem(AMenu: TPopupMenu; const ACaption: string; ATag: Integer;
  AChecked: Boolean; AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.Checked := AChecked;
  Result.OnClick := AOnClick;
  AMenu.Items.Add(Result);
end;

class function TAtlasIdeDesignerTool.OwnerWindow: HWND;
begin
  Result := Application.MainFormHandle;
end;

procedure TAtlasIdeDesignerTool.ApplyTheme;
begin
  ThemeWindow(FOutlines);
end;

end.
