unit Atlas.IDE.Designer.Views;

// Eigene Knöpfe der Designer-Leiste für die größeren Designer-Funktionen
// (#605 ff.), an einer Stelle für TAtlasIdeDesignerCommands; jede Funktion
// hat einen eigenen Knopf und eine eigene Einstellung, damit sie nicht mit
// dem Menü „Anordnen“ kollidiert:
// - Abstände messen (#605, designer.measureDistances und
//   designer.measureAltKey, TAtlasIdeDesignerMeasure): Schalter.
// - Größe ausprobieren (#606, designer.resizePreview, TAtlasIdeResizePreview):
//   Fenster mit der Probegröße.
// - Skalierung und Texte (#607, designer.scalePreview, TAtlasIdeScalePreview):
//   Fenster mit Skalierung, Bildschirm und langen Texten.
// - Sprechende Namen (#608, designer.nameSuggest, TAtlasIdeNameSuggest):
//   Dialog mit Vorschlägen für Standardnamen.
// - Atlas-Struktur (#609, designer.structure, TAtlasIdeStructure):
//   andockbares Fenster mit Baum, Gruppen und Verknüpfungen.
// - Datenbindung (#610, designer.dataBindings, TAtlasIdeDataBindings):
//   Brotkrumenleiste mit dem Datenkonstrukt der Auswahl unter dem Designer.
// - In Frame auslagern (#611, designer.extractFrame, TAtlasIdeExtractFrame):
//   Dialog mit Vorschau je Datei.
// - Ereignis-Karte (#612, designer.eventMap, TAtlasIdeEventMap): andockbares
//   Fenster mit allen Ereignissen des Formulars.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Designer.Measure,
  Atlas.IDE.Designer.NameSuggest,
  Atlas.IDE.Designer.Structure,
  Atlas.IDE.Designer.DataBindings,
  Atlas.IDE.Designer.ExtractFrame,
  Atlas.IDE.Designer.EventMap,
  Atlas.IDE.Designer.ResizePreview,
  Atlas.IDE.Designer.ScalePreview;

type
  TAtlasIdeDesignerViews = class
  private
    FMeasure: TAtlasIdeDesignerMeasure;
    FResize: TAtlasIdeResizePreview;
    FScale: TAtlasIdeScalePreview;
    FNames: TAtlasIdeNameSuggest;
    FStructure: TAtlasIdeStructure;
    FBindings: TAtlasIdeDataBindings;
    FExtract: TAtlasIdeExtractFrame;
    FEvents: TAtlasIdeEventMap;
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

{ TAtlasIdeDesignerViews }

constructor TAtlasIdeDesignerViews.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FMeasure := TAtlasIdeDesignerMeasure.Create;
  FResize := TAtlasIdeResizePreview.Create(AOnMessage);
  FScale := TAtlasIdeScalePreview.Create(AOnMessage);
  FNames := TAtlasIdeNameSuggest.Create(AOnMessage);
  FStructure := TAtlasIdeStructure.Create(AOnMessage);
  FBindings := TAtlasIdeDataBindings.Create;
  FExtract := TAtlasIdeExtractFrame.Create(AOnMessage);
  FEvents := TAtlasIdeEventMap.Create(AOnMessage);
end;

destructor TAtlasIdeDesignerViews.Destroy;
begin
  FEvents.Free;
  FExtract.Free;
  FBindings.Free;
  FStructure.Free;
  FNames.Free;
  FScale.Free;
  FResize.Free;
  FMeasure.Free;
  inherited Destroy;
end;

function TAtlasIdeDesignerViews.Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
var
  mAll: TArray<TAtlasDesignerButton>;
  mButton: TAtlasDesignerButton;
begin
  Result := nil;
  mAll := [FMeasure.Button(ASettings), FResize.Button(ASettings), FScale.Button(ASettings),
    FNames.Button(ASettings), FStructure.Button(ASettings), FBindings.Button(ASettings),
    FExtract.Button(ASettings), FEvents.Button(ASettings)];
  for mButton in mAll do
  begin
    if mButton.Id <> '' then
    begin
      Result := Result + [mButton];
    end;
  end;
end;

function TAtlasIdeDesignerViews.Run(const AId: string): Boolean;
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
  else if SameText(AId, TAtlasIdeScalePreview.cId) then
  begin
    FScale.Toggle;
  end
  else if SameText(AId, TAtlasIdeNameSuggest.cId) then
  begin
    FNames.Run;
  end
  else if SameText(AId, TAtlasIdeStructure.cId) then
  begin
    FStructure.Toggle;
  end
  else if SameText(AId, TAtlasIdeDataBindings.cId) then
  begin
    FBindings.Toggle;
  end
  else if SameText(AId, TAtlasIdeExtractFrame.cId) then
  begin
    FExtract.Run;
  end
  else if SameText(AId, TAtlasIdeEventMap.cId) then
  begin
    FEvents.Toggle;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAtlasIdeDesignerViews.ApplyTheme;
begin
  FMeasure.ApplyTheme;
  FResize.ApplyTheme;
  FScale.ApplyTheme;
  FStructure.ApplyTheme;
  FBindings.ApplyTheme;
  FEvents.ApplyTheme;
end;

end.
