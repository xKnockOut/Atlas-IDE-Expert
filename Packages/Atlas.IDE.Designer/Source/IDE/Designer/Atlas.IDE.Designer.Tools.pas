unit Atlas.IDE.Designer.Tools;

// Eigene Knöpfe der Designer-Leiste für die größeren Designer-Funktionen
// (#605 ff.), an einer Stelle für TAtlasIdeDesignerCommands; jede Funktion
// hat einen eigenen Knopf und eine eigene Einstellung, damit sie nicht mit
// dem Menü „Anordnen“ kollidiert:
// - Abstände messen (#605, designer.measureDistances und
//   designer.measureAltKey, TAtlasIdeDesignerMeasure): Schalter.
// - Größe ausprobieren (#606, designer.resizePreview, TAtlasIdeResizePreview):
//   Fenster mit der Probegröße.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Designer.Measure,
  Atlas.IDE.Designer.ResizePreview;

type
  TAtlasIdeDesignerTools = class
  private
    FMeasure: TAtlasIdeDesignerMeasure;
    FResize: TAtlasIdeResizePreview;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Knöpfe nach den Einstellungen.</summary>
    function Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
    /// <summary>Klick auf den Knopf AId ohne Menü; False, wenn er nicht hierher gehört.</summary>
    function Run(const AId: string): Boolean;
    procedure ApplyTheme;
  end;

implementation

{ TAtlasIdeDesignerTools }

constructor TAtlasIdeDesignerTools.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FMeasure := TAtlasIdeDesignerMeasure.Create;
  FResize := TAtlasIdeResizePreview.Create(AOnMessage);
end;

destructor TAtlasIdeDesignerTools.Destroy;
begin
  FResize.Free;
  FMeasure.Free;
  inherited Destroy;
end;

function TAtlasIdeDesignerTools.Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
var
  mAll: TArray<TAtlasDesignerButton>;
  mButton: TAtlasDesignerButton;
begin
  Result := nil;
  mAll := [FMeasure.Button(ASettings), FResize.Button(ASettings)];
  for mButton in mAll do
  begin
    if mButton.Id <> '' then
    begin
      Result := Result + [mButton];
    end;
  end;
end;

function TAtlasIdeDesignerTools.Run(const AId: string): Boolean;
begin
  Result := True;
  if SameText(AId, TAtlasIdeDesignerMeasure.cId) then
  begin
    FMeasure.Toggle;
  end
  else if SameText(AId, TAtlasIdeResizePreview.cId) then
  begin
    FResize.Toggle;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAtlasIdeDesignerTools.ApplyTheme;
begin
  FMeasure.ApplyTheme;
  FResize.ApplyTheme;
end;

end.
