unit Atlas.IDE.Editor.MinimapFolds;

// Faltung für die Minimap (#873): Die Open Tools API meldet gefaltete
// Bereiche nicht. PaintLine (plsEndPaint) merkt sich je gemalter
// Bildschirmzeile die Editorzeile; TAtlasMinimap.Folds erkennt daraus
// gefaltete und wieder aufgeklappte Bereiche. Ändert sich die Zeilenzahl,
// gelten die Bereiche als unbekannt. Nur im Hauptthread.

interface

uses
  System.Types,
  ToolsAPI.Editor,
  Atlas.Core.Editor.Minimap;

type
  TAtlasIdeMinimapFolds = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFolds: TAtlasMinimapFolds;
    FFoldLines: Integer;
    FPainted: TArray<TAtlasMinimapPainted>;
    FPaintedTop: Integer;
    FPaintedFile: string;
    FRowHeight: Integer;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bekannte Bereiche vergessen (andere Datei).</summary>
    procedure Reset;
    /// <summary>Gefaltete Bereiche von AFileName (ALineCount Zeilen) nach den seit dem letzten Aufruf gemalten
    /// Zeilen.</summary>
    function Update(const AFileName: string; ALineCount: Integer): TAtlasMinimapFolds;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

{ TAtlasIdeMinimapFolds.TEvents }

function TAtlasIdeMinimapFolds.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeMinimapFolds.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeMinimapFolds }

constructor TAtlasIdeMinimapFolds.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FPaintedTop := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeMinimapFolds.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

procedure TAtlasIdeMinimapFolds.Reset;
begin
  FFolds := nil;
  FFoldLines := 0;
  FPainted := nil;
end;

function TAtlasIdeMinimapFolds.Update(const AFileName: string; ALineCount: Integer): TAtlasMinimapFolds;
begin
  // Andere Zeilenzahl: Die bekannten Bereiche stimmen nicht mehr.
  if ALineCount <> FFoldLines then
  begin
    FFolds := nil;
    FFoldLines := ALineCount;
  end;
  if (FPainted <> nil) and SameText(FPaintedFile, AFileName) then
  begin
    FFolds := TAtlasMinimap.Folds(FFolds, FPainted, FRowHeight, ALineCount);
  end;
  FPainted := nil;
  Result := FFolds;
end;

procedure TAtlasIdeMinimapFolds.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mView: IOTAEditView;
  mIndex: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) then
  begin
    Exit;
  end;
  try
    mView := Context.EditView;
    if (mView = nil) or (mView.Buffer = nil) then
    begin
      Exit;
    end;
    // Nur Zeilen derselben Bildlaufstellung lassen sich vergleichen.
    if (mView.TopRow <> FPaintedTop) or not SameText(Context.FileName, FPaintedFile) then
    begin
      FPainted := nil;
      FPaintedTop := mView.TopRow;
      FPaintedFile := Context.FileName;
    end;
    FRowHeight := Rect.Bottom - Rect.Top;
    for mIndex := 0 to High(FPainted) do
    begin
      if FPainted[mIndex].Top = Rect.Top then
      begin
        FPainted[mIndex].Line := Context.LogicalLineNum - 1;
        Exit;
      end;
    end;
    // Höchstens eine Bildschirmseite merken.
    if Length(FPainted) < 1000 then
    begin
      FPainted := FPainted + [TAtlasMinimapPainted.Create(Rect.Top, Context.LogicalLineNum - 1)];
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Minimap, E);
  end;
end;

end.
