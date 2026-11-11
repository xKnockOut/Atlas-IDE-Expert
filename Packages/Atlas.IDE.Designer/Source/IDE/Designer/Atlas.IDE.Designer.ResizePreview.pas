unit Atlas.IDE.Designer.ResizePreview;

// Knopf „Größe ausprobieren“ der Designer-Leiste (#606) in der IDE: liest das
// Formular des aktiven Designers (TAtlasDesignerModel) und zeigt es im
// Fenster TAtlasFormPreviewWindow bei einer Probegröße. Die Komponenten im
// Designer werden nicht verschoben, die DFM bleibt unverändert, das Formular
// wird nicht als geändert markiert. Der Knopf ist gedrückt, solange das
// Fenster offen ist; ein zweiter Klick oder Esc schließt es.
// - Minimum aus Constraints.MinWidth/MinHeight des Formulars (auf den Client
//   umgerechnet), Schnellwerte aus designer.resizePreviewSizes, Nadeln und
//   Align-Flächen nach designer.resizePreviewShowAnchors.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.Controls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.FormPreview;

type
  TAtlasIdeResizePreview = class
  public const
    cId = 'resizePreview';
  private
    FOnMessage: TProc<string>;
    FWindow: TAtlasFormPreviewWindow;
    procedure Open;
    procedure CloseWindow;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Knopf nach den Einstellungen; Id leer, wenn ausgeschaltet.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick: Fenster öffnen bzw. schließen.</summary>
    procedure Toggle;
    procedure ApplyTheme;
  end;

implementation

uses
  System.Types,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Designer.Layout,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.ToolStrings,
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

function DataOf(ARoot: TWinControl): TAtlasFormPreviewData;
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

{ TAtlasIdeResizePreview }

constructor TAtlasIdeResizePreview.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

destructor TAtlasIdeResizePreview.Destroy;
begin
  CloseWindow;
  inherited Destroy;
end;

function TAtlasIdeResizePreview.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not ASettings.DesignerResizePreview then
  begin
    CloseWindow;
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.ResizePreview,
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.ResizeHint));
  Result.Pressed := (FWindow <> nil) and FWindow.Visible;
end;

procedure TAtlasIdeResizePreview.Toggle;
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

procedure TAtlasIdeResizePreview.Open;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  CloseWindow;
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or not (mRoot is TWinControl) then
  begin
    FOnMessage(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.ToolNoForm));
    Exit;
  end;
  FWindow := TAtlasFormPreviewWindow.CreatePreview(nil, DataOf(TWinControl(mRoot)), TAtlasIdeStyle.Colors);
  TAtlasIdeDockWindow.ApplyIdeTheme(FWindow);
  FWindow.Show;
end;

procedure TAtlasIdeResizePreview.CloseWindow;
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

procedure TAtlasIdeResizePreview.ApplyTheme;
begin
  if FWindow <> nil then
  begin
    TAtlasIdeDockWindow.ApplyIdeTheme(FWindow);
    FWindow.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

end.
