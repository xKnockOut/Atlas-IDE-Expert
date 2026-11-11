unit Atlas.IDE.Designer.Arrange;

// Knopf „Anordnen“ der Designer-Leiste (#730 ff.) in der IDE: Menü mit den
// Befehlen, die Größe und Lage der markierten Steuerelemente ändern. Jeder
// Befehl hat eine eigene Einstellung; ist keiner an, fehlt der Knopf.
// - Breite nach Text (#730, designer.fitToText, TAtlasIdeFitText).
// - Knopfleiste anordnen (#732, designer.buttonBar, TAtlasIdeButtonBar).
// Gesperrt sind Einträge, für die die Auswahl nicht passt. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Menus,
  Atlas.Core.Settings.Plugin;

type
  TAtlasIdeDesignerArrange = class
  private
    FMenu: TPopupMenu;
    FOnMessage: TProc<string>;
    procedure AddItem(const ACaption: string; ATag: Integer; AEnabled: Boolean);
    procedure ItemClick(Sender: TObject);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Ist mindestens ein Befehl eingeschaltet?</summary>
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Menü für die Auswahl im aktiven Designer an APoint (Bildschirm).</summary>
    procedure Popup(const APoint: TPoint);
  end;

implementation

uses
  System.Classes,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FitText,
  Atlas.IDE.Designer.ButtonBar,
  Atlas.IDE.Foundation.Settings;

const
  cFitToText = 1;
  cButtonBar = 2;

{ TAtlasIdeDesignerArrange }

constructor TAtlasIdeDesignerArrange.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FMenu := TPopupMenu.Create(nil);
end;

destructor TAtlasIdeDesignerArrange.Destroy;
begin
  FMenu.Free;
  inherited Destroy;
end;

class function TAtlasIdeDesignerArrange.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerFitToText or ASettings.DesignerButtonBar;
end;

procedure TAtlasIdeDesignerArrange.AddItem(const ACaption: string; ATag: Integer; AEnabled: Boolean);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := ACaption;
  mItem.Tag := ATag;
  mItem.Enabled := AEnabled;
  mItem.OnClick := ItemClick;
  FMenu.Items.Add(mItem);
end;

procedure TAtlasIdeDesignerArrange.Popup(const APoint: TPoint);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not Available(mSettings) or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  FMenu.Items.Clear;
  if mSettings.DesignerFitToText then
  begin
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerFitToText), cFitToText,
      Length(TAtlasIdeFitText.Candidates(mSelected)) > 0);
  end;
  if mSettings.DesignerButtonBar then
  begin
    AddItem(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerButtonBarCmd), cButtonBar,
      Length(TAtlasIdeButtonBar.Candidates(mSelected)) > 0);
  end;
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeDesignerArrange.ItemClick(Sender: TObject);
var
  mTag: Integer;
  mOnMessage: TProc<string>;
begin
  mTag := TMenuItem(Sender).Tag;
  mOnMessage := FOnMessage;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      case mTag of
        cFitToText:
          TAtlasIdeFitText.Execute(mOnMessage);
        cButtonBar:
          TAtlasIdeButtonBar.Execute(mOnMessage);
      end;
    end);
end;

end.
