unit Atlas.IDE.Designer.Tools;

// Werkzeuge mit eigenem Knopf in der Designer-Leiste (#734 ff.), an einer
// Stelle für die Befehle der Leiste (TAtlasIdeDesignerCommands): Ein Klick
// auf das Symbol schaltet das Werkzeug ein und aus (gedrückt = an), der Pfeil
// öffnet sein Menü. Der Takt der Leiste lässt die Werkzeuge der Auswahl im
// Designer folgen.
// - Abstandsgriffe (#734, designer.gapHandles, TAtlasIdeGapHandles).
// - Gemeinsame Größengriffe (#737, designer.multiResize, TAtlasIdeMultiResize).
// - Schnellleiste über einer Mehrfachauswahl (#735, designer.selectionBar,
//   TAtlasIdeSelectionBar).
// - Lupe (#743, designer.magnifier, TAtlasIdeMagnifier).
// - Eigenschaften suchen (#524, designer.propertySearch,
//   TAtlasIdePropertySearch): Knopf ohne Menü, öffnet den Dialog.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Designer.HandleTool,
  Atlas.IDE.Designer.PropertyPainter,
  Atlas.IDE.Designer.GapHandles,
  Atlas.IDE.Designer.MultiResize,
  Atlas.IDE.Designer.SelectionBar,
  Atlas.IDE.Designer.Magnifier,
  Atlas.IDE.Designer.PropertySearch;

type
  TAtlasIdeDesignerTools = class
  private
    FGaps: TAtlasIdeGapHandles;
    FResize: TAtlasIdeMultiResize;
    FBar: TAtlasIdeSelectionBar;
    FMagnifier: TAtlasIdeMagnifier;
    /// <summary>Werkzeug mit Griffen zum Knopf AId; nil ohne.</summary>
    function HandleToolOf(const AId: string): TAtlasIdeHandleTool;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht; APainter: Format-Pinsel für die Schnellleiste.</summary>
    constructor Create(const AOnMessage: TProc<string>; APainter: TAtlasIdePropertyPainter);
    destructor Destroy; override;
    /// <summary>Knöpfe nach den Einstellungen.</summary>
    function Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
    /// <summary>Klick auf das Symbol des Knopfs AId; False, wenn er nicht hierher gehört.</summary>
    function Toggle(const AId: string): Boolean;
    /// <summary>Gehört der Knopf AId mit Menü hierher?</summary>
    function HasMenu(const AId: string): Boolean;
    /// <summary>Menü des Knopfs AId an APoint (Bildschirm).</summary>
    procedure Popup(const AId: string; const APoint: TPoint);
    /// <summary>Takt der Leiste, solange sie gezeigt wird.</summary>
    procedure Tick;
    /// <summary>Alles ausblenden (Leiste aus, Designer weg).</summary>
    procedure Hide;
    procedure ApplyTheme;
  end;

implementation

{ TAtlasIdeDesignerTools }

constructor TAtlasIdeDesignerTools.Create(const AOnMessage: TProc<string>; APainter: TAtlasIdePropertyPainter);
begin
  inherited Create;
  FGaps := TAtlasIdeGapHandles.Create(AOnMessage);
  FResize := TAtlasIdeMultiResize.Create(AOnMessage);
  FBar := TAtlasIdeSelectionBar.Create(AOnMessage, APainter);
  FMagnifier := TAtlasIdeMagnifier.Create(AOnMessage);
end;

destructor TAtlasIdeDesignerTools.Destroy;
begin
  FMagnifier.Free;
  FBar.Free;
  FResize.Free;
  FGaps.Free;
  inherited Destroy;
end;

function TAtlasIdeDesignerTools.Buttons(const ASettings: TAtlasPluginSettings): TArray<TAtlasDesignerButton>;
begin
  Result := nil;
  if TAtlasIdeGapHandles.Available(ASettings) then
  begin
    Result := Result + [FGaps.Button];
  end;
  if TAtlasIdeMultiResize.Available(ASettings) then
  begin
    Result := Result + [FResize.Button];
  end;
  if TAtlasIdeSelectionBar.Available(ASettings) then
  begin
    Result := Result + [FBar.Button];
  end;
  if TAtlasIdeMagnifier.Available(ASettings) then
  begin
    Result := Result + [FMagnifier.Button];
  end;
  if TAtlasIdePropertySearch.Available(ASettings) then
  begin
    Result := Result + [TAtlasIdePropertySearch.Button];
  end;
end;

function TAtlasIdeDesignerTools.HandleToolOf(const AId: string): TAtlasIdeHandleTool;
begin
  Result := nil;
  if SameText(AId, TAtlasIdeGapHandles.cId) then
  begin
    Result := FGaps;
  end
  else if SameText(AId, TAtlasIdeMultiResize.cId) then
  begin
    Result := FResize;
  end;
end;

function TAtlasIdeDesignerTools.Toggle(const AId: string): Boolean;
var
  mTool: TAtlasIdeHandleTool;
begin
  if SameText(AId, TAtlasIdeSelectionBar.cId) then
  begin
    FBar.Toggle;
    Exit(True);
  end;
  if SameText(AId, TAtlasIdeMagnifier.cId) then
  begin
    FMagnifier.Toggle;
    Exit(True);
  end;
  mTool := HandleToolOf(AId);
  Result := mTool <> nil;
  if Result then
  begin
    mTool.Toggle;
  end
  else if SameText(AId, TAtlasIdePropertySearch.cId) then
  begin
    TAtlasIdePropertySearch.Run(True);
    Result := True;
  end;
end;

function TAtlasIdeDesignerTools.HasMenu(const AId: string): Boolean;
begin
  Result := (HandleToolOf(AId) <> nil) or SameText(AId, TAtlasIdeSelectionBar.cId) or
    SameText(AId, TAtlasIdeMagnifier.cId);
end;

procedure TAtlasIdeDesignerTools.Popup(const AId: string; const APoint: TPoint);
var
  mTool: TAtlasIdeHandleTool;
begin
  mTool := HandleToolOf(AId);
  if mTool <> nil then
  begin
    mTool.Popup(APoint);
  end
  else if SameText(AId, TAtlasIdeSelectionBar.cId) then
  begin
    FBar.Popup(APoint);
  end
  else if SameText(AId, TAtlasIdeMagnifier.cId) then
  begin
    FMagnifier.Popup(APoint);
  end;
end;

procedure TAtlasIdeDesignerTools.Tick;
begin
  FGaps.Tick;
  FResize.Tick;
  FBar.Tick;
  FMagnifier.Tick;
end;

procedure TAtlasIdeDesignerTools.Hide;
begin
  FGaps.Hide;
  FResize.Hide;
  FBar.Hide;
  FMagnifier.Hide;
end;

procedure TAtlasIdeDesignerTools.ApplyTheme;
begin
  FGaps.ApplyTheme;
  FResize.ApplyTheme;
  FBar.ApplyTheme;
  FMagnifier.ApplyTheme;
end;

end.
