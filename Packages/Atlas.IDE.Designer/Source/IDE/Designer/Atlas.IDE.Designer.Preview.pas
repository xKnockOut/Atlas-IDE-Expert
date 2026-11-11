unit Atlas.IDE.Designer.Preview;

// Gemeinsame Grundlage der Vorschaufenster in der Designer-Leiste (#606,
// #607): ein Knopf, der gedrückt ist, solange das Fenster offen ist; ein
// zweiter Klick oder Esc schließt es. Gelesen wird das Formular des aktiven
// Designers; die Komponenten werden nicht verschoben, die DFM bleibt
// unverändert, das Formular wird nicht als geändert markiert.
// - FormData: Knoten, Client, Constraints (auf den Client umgerechnet) und
//   die Einstellungen der Probegröße, alles in Pixeln der DFM.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.FormPreview;

type
  TAtlasIdePreviewTool = class
  private
    FOnMessage: TProc<string>;
    FWindow: TAtlasFormPreviewWindow;
    procedure Open;
    procedure CloseWindow;
  protected
    function Id: string; virtual; abstract;
    function Icon: TAtlasToolbarIcon; virtual; abstract;
    function HintText: string; virtual; abstract;
    function Enabled(const ASettings: TAtlasPluginSettings): Boolean; virtual; abstract;
    /// <summary>Fenster für das Formular ARoot (Besitzer nil, wird hier freigegeben).</summary>
    function CreateWindow(ARoot: TWinControl): TAtlasFormPreviewWindow; virtual; abstract;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Formular ARoot als Daten für das Vorschaufenster, in Pixeln der DFM.</summary>
    class function FormData(ARoot: TWinControl): TAtlasFormPreviewData; static;
    /// <summary>Rahmen und Titel (ganze Größe minus Client) in Pixeln der DFM.</summary>
    class function FrameOf(ARoot: TWinControl): TSize; static;
    /// <summary>Knopf nach den Einstellungen; Id leer, wenn ausgeschaltet.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick: Fenster öffnen bzw. schließen.</summary>
    procedure Toggle;
    procedure ApplyTheme;
  end;

implementation

uses
  System.Classes,
  ToolsAPI,
  Atlas.Core.Designer.Layout,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.Model,
  Atlas.IDE.Foundation.DockWindow,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

/// <summary>Grenze der Constraints (ganzes Fenster) als Client in Pixeln der DFM; 0 bleibt 0.</summary>
function ClientLimit(AValue, AFrame: Integer; const AScale: TAtlasDesignScale): Integer;
begin
  Result := 0;
  if AValue > 0 then
  begin
    Result := AScale.ToDesign(AValue - AFrame);
  end;
end;

{ TAtlasIdePreviewTool }

constructor TAtlasIdePreviewTool.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

destructor TAtlasIdePreviewTool.Destroy;
begin
  CloseWindow;
  inherited Destroy;
end;

class function TAtlasIdePreviewTool.FrameOf(ARoot: TWinControl): TSize;
var
  mScale: TAtlasDesignScale;
begin
  mScale := TAtlasDesignScale.ForRoot(ARoot);
  Result := TSize.Create(mScale.ToDesign(ARoot.Width - ARoot.ClientWidth),
    mScale.ToDesign(ARoot.Height - ARoot.ClientHeight));
end;

class function TAtlasIdePreviewTool.FormData(ARoot: TWinControl): TAtlasFormPreviewData;
var
  mControls: TArray<TControl>;
  mScale: TAtlasDesignScale;
  mFrameX, mFrameY: Integer;
begin
  Result := Default(TAtlasFormPreviewData);
  Result.FormName := ARoot.Name;
  Result.Nodes := TAtlasDesignerModel.LayoutNodes(ARoot, mControls);
  Result.Design := TAtlasDesignerModel.ClientOf(ARoot);
  Result.Quick := TAtlasFormLayout.ParseSizes(TAtlasIdeSettings.Current.DesignerResizePreviewSizes);
  Result.ShowAnchors := TAtlasIdeSettings.Current.DesignerResizePreviewShowAnchors;
  mScale := TAtlasDesignScale.ForRoot(ARoot);
  // Constraints gelten für das ganze Fenster: Rahmen und Titel abziehen.
  mFrameX := ARoot.Width - ARoot.ClientWidth;
  mFrameY := ARoot.Height - ARoot.ClientHeight;
  Result.MinClient := TSize.Create(ClientLimit(ARoot.Constraints.MinWidth, mFrameX, mScale),
    ClientLimit(ARoot.Constraints.MinHeight, mFrameY, mScale));
  Result.MaxClient := TSize.Create(ClientLimit(ARoot.Constraints.MaxWidth, mFrameX, mScale),
    ClientLimit(ARoot.Constraints.MaxHeight, mFrameY, mScale));
end;

function TAtlasIdePreviewTool.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not Enabled(ASettings) then
  begin
    CloseWindow;
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(Id, Icon, HintText);
  Result.Pressed := (FWindow <> nil) and FWindow.Visible;
end;

procedure TAtlasIdePreviewTool.Toggle;
begin
  if (FWindow <> nil) and FWindow.Visible then
  begin
    CloseWindow;
  end
  else
  begin
    Open;
  end;
end;

procedure TAtlasIdePreviewTool.Open;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  CloseWindow;
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or not (mRoot is TWinControl) then
  begin
    FOnMessage(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ToolNoForm));
    Exit;
  end;
  FWindow := CreateWindow(TWinControl(mRoot));
  TAtlasIdeDockWindow.ApplyIdeTheme(FWindow);
  FWindow.Show;
end;

procedure TAtlasIdePreviewTool.CloseWindow;
var
  mWindow: TAtlasFormPreviewWindow;
begin
  if FWindow = nil then
  begin
    Exit;
  end;
  mWindow := FWindow;
  FWindow := nil;
  mWindow.OnClosed := nil;
  mWindow.Free;
end;

procedure TAtlasIdePreviewTool.ApplyTheme;
begin
  if FWindow <> nil then
  begin
    TAtlasIdeDockWindow.ApplyIdeTheme(FWindow);
    FWindow.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

end.
