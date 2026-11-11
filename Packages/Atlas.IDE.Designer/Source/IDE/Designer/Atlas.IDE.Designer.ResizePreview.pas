unit Atlas.IDE.Designer.ResizePreview;

// Knopf „Größe ausprobieren“ der Designer-Leiste (#606) in der IDE: zeigt das
// Formular des aktiven Designers im Fenster TAtlasFormPreviewWindow bei einer
// Probegröße (Grundlage TAtlasIdePreviewTool).
// - Minimum aus Constraints.MinWidth/MinHeight des Formulars (auf den Client
//   umgerechnet), Schnellwerte aus designer.resizePreviewSizes, Nadeln und
//   Align-Flächen nach designer.resizePreviewShowAnchors.
// Nur im Hauptthread.

interface

uses
  Vcl.Controls,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.FormPreview,
  Atlas.IDE.Designer.Preview;

type
  TAtlasIdeResizePreview = class(TAtlasIdePreviewTool)
  public const
    cId = 'resizePreview';
  protected
    function Id: string; override;
    function Icon: TAtlasToolbarIcon; override;
    function HintText: string; override;
    function Enabled(const ASettings: TAtlasPluginSettings): Boolean; override;
    function CreateWindow(ARoot: TWinControl): TAtlasFormPreviewWindow; override;
  end;

implementation

uses
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Foundation.EditorStyle;

{ TAtlasIdeResizePreview }

function TAtlasIdeResizePreview.Id: string;
begin
  Result := cId;
end;

function TAtlasIdeResizePreview.Icon: TAtlasToolbarIcon;
begin
  Result := TAtlasToolbarIcon.ResizePreview;
end;

function TAtlasIdeResizePreview.HintText: string;
begin
  Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ResizeHint);
end;

function TAtlasIdeResizePreview.Enabled(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerResizePreview;
end;

function TAtlasIdeResizePreview.CreateWindow(ARoot: TWinControl): TAtlasFormPreviewWindow;
begin
  Result := TAtlasFormPreviewWindow.CreatePreview(nil, FormData(ARoot), TAtlasIdeStyle.Colors);
end;

end.
