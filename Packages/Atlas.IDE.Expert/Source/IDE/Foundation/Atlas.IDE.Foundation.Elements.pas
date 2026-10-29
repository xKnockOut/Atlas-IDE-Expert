unit Atlas.IDE.Foundation.Elements;

// Gezeichnete Elemente im Editor (#628): Jeder Zeichner von Atlas meldet,
// was er wo gezeichnet hat (Painted), und fragt vorher, ob das Element an
// dieser Stelle ausgeblendet ist (Hidden, FileHidden). Grundlage für
// „Ausblenden direkt am Element“ (Atlas.IDE.Editor.Hide).
// - Treffer: je Datei und Zeile die Elemente mit Rechteck (Koordinaten des
//   Editors), oberster Zeile der Ansicht und Zeilenhöhe. Jedes Zeichnen des
//   Editors beginnt eine neue Runde (OnEditorBeginPaint); beim Zeichnen einer
//   Zeile fallen die Treffer älterer Runden weg, die der laufenden bleiben.
//   So stimmen die Treffer mit dem, was zu sehen ist, auch wenn Zeichner vor
//   oder nach dieser Unit an die Reihe kommen. Nach Scrollen verschiebt At die
//   Rechtecke um die Zahl der Zeilen.
// - Ausgeblendet: Einträge "hidden" der Projektdatei .atlas (#486) über
//   TAtlasHiddenIndex; neu aufgebaut, sobald TAtlasIdeTeamFile einen neuen
//   Stand gelesen hat.
// - Rechtsklick auf ein überlagertes Element (Code Lens, Inlay-Hint,
//   Blockende-Beschriftung): Atlas schluckt das Loslassen der rechten Taste
//   für dieses Editorfenster (das Kontextmenü der IDE bleibt zu) und ruft
//   OnOverlayMenu mit den Elementen und der Mausposition. Jeder Rechtsklick
//   auf ein Element merkt die Elemente für den Befehl „Element ausblenden …“
//   im Atlas-Untermenü (TakeClick, höchstens ClickMs alt).
// Nur im Hauptthread verwenden.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Types,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.AppEvnts,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Hide,
  Atlas.Core.Settings.HiddenPlaces;

type
  /// <summary>Ein gezeichnetes Element.</summary>
  TAtlasElementHit = record
    Target: TAtlasHideTarget;
    /// <summary>Koordinaten des Editors beim Zeichnen.</summary>
    Rect: TRect;
    TopRow: Integer;
    LineHeight: Integer;
    Round: Cardinal;
  end;

  TAtlasOverlayMenuProc = reference to procedure(const ATargets: TArray<TAtlasHideTarget>; const AScreen: TPoint);

  TAtlasIdeElements = class
  public const
    /// <summary>So lange gilt ein Rechtsklick auf ein Element für „Element ausblenden …“.</summary>
    ClickMs = 60000;
    /// <summary>So lange nach dem Drücken wird das Loslassen der rechten Taste geschluckt.</summary>
    RightUpMs = 5000;
    /// <summary>Mehr gemerkte Zeilen: alle vergessen (der Editor zeichnet sie ohnehin neu).</summary>
    MaxLines = 5000;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeElements;
    FOnOverlayMenu: TAtlasOverlayMenuProc;
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FAppEvents: TApplicationEvents;
    FHits: TDictionary<string, TArray<TAtlasElementHit>>;
    FRound: Cardinal;
    FHidden: TAtlasHiddenIndex;
    FHiddenVersion: Integer;
    FClickFile: string;
    FClickTargets: TArray<TAtlasHideTarget>;
    FClickAt: UInt64;
    FPendingWnd: HWND;
    FPendingAt: UInt64;
    FPendingTargets: TArray<TAtlasHideTarget>;
    class function KeyOf(const AFileName: string; ALine: Integer): string; static;
    class function SameFile(const A, B: string): Boolean; static;
    function Index: TAtlasHiddenIndex;
    procedure BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure DropOld(const AKey: string);
    function HitsAt(const AFileName: string; ATopRow, X, Y: Integer): TArray<TAtlasHideTarget>;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Start; static;
    class procedure Stop; static;
    /// <summary>AElement an ALine (0-basiert) von AFileName gezeichnet; ARect in Koordinaten des Editors,
    /// ATopRow die oberste Zeile der Ansicht, ALineHeight die Zeilenhöhe in Pixeln.</summary>
    class procedure Painted(const ATarget: TAtlasHideTarget; const ARect: TRect; ATopRow, ALineHeight: Integer);
      overload; static;
    class procedure Painted(AElement: TAtlasDrawnElement; const AFileName: string; ALine: Integer;
      const AAnchor: string; const ARect: TRect; ATopRow, ALineHeight: Integer); overload; static;
    /// <summary>Element an AAnchor (Rohtext, wird normalisiert) per .atlas ausgeblendet?</summary>
    class function Hidden(AElement: TAtlasDrawnElement; const AFileName, AAnchor: string): Boolean; static;
    /// <summary>Element in der ganzen Datei per .atlas ausgeblendet?</summary>
    class function FileHidden(AElement: TAtlasDrawnElement; const AFileName: string): Boolean; static;
    /// <summary>Zuletzt an ALine (0-basiert) gezeichnete Elemente, je Element einmal.</summary>
    class function OnLine(const AFileName: string; ALine: Integer): TArray<TAtlasHideTarget>; static;
    /// <summary>Elemente unter X, Y (Koordinaten des Editors) bei oberster Zeile ATopRow.</summary>
    class function At(const AFileName: string; ATopRow, X, Y: Integer): TArray<TAtlasHideTarget>; static;
    /// <summary>Elemente des letzten Rechtsklicks in AFileName (höchstens ClickMs alt); vergisst ihn.</summary>
    class function TakeClick(const AFileName: string; out ATargets: TArray<TAtlasHideTarget>): Boolean; static;
    /// <summary>Alle Treffer vergessen und den Editor neu zeichnen lassen (nach dem Ausblenden).</summary>
    class procedure Reset; static;
    class property OnOverlayMenu: TAtlasOverlayMenuProc read FOnOverlayMenu write FOnOverlayMenu;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.TeamFile,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasIdeElements.TEvents }

function TAtlasIdeElements.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevBeginEndPaintEvents, cevPaintLineEvents, cevMouseEvents];
end;

function TAtlasIdeElements.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [Low(TPaintLineStage)];
end;

{ TAtlasIdeElements }

constructor TAtlasIdeElements.Create;
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FHiddenVersion := -1;
  FHits := TDictionary<string, TArray<TAtlasElementHit>>.Create;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorBeginPaint := BeginPaint;
  FEvents.OnEditorPaintLine := PaintLine;
  FEvents.OnEditorMouseDown := EditorMouseDown;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FAppEvents := TApplicationEvents.Create(nil);
  FAppEvents.OnMessage := AppMessage;
end;

destructor TAtlasIdeElements.Destroy;
var
  Services: INTACodeEditorServices;
begin
  if FAppEvents <> nil then
  begin
    FAppEvents.OnMessage := nil;
    FAppEvents.Free;
  end;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorBeginPaint := nil;
  FEvents.OnEditorPaintLine := nil;
  FEvents.OnEditorMouseDown := nil;
  FEventsRef := nil;
  FHidden.Free;
  FHits.Free;
  inherited Destroy;
end;

class procedure TAtlasIdeElements.Start;
begin
  if FInstance = nil then
    FInstance := TAtlasIdeElements.Create;
end;

class procedure TAtlasIdeElements.Stop;
begin
  FreeAndNil(FInstance);
  FOnOverlayMenu := nil;
end;

class function TAtlasIdeElements.KeyOf(const AFileName: string; ALine: Integer): string;
begin
  Result := AnsiLowerCase(AFileName) + '|' + IntToStr(ALine);
end;

class function TAtlasIdeElements.SameFile(const A, B: string): Boolean;
begin
  Result := AnsiSameText(A, B);
end;

function TAtlasIdeElements.Index: TAtlasHiddenIndex;
var
  Team: TAtlasTeamSettings;
begin
  if (FHidden = nil) or (FHiddenVersion <> TAtlasIdeTeamFile.Version) then
  begin
    FreeAndNil(FHidden);
    FHiddenVersion := TAtlasIdeTeamFile.Version;
    Team := TAtlasIdeTeamFile.Current;
    if Team.Valid then
      FHidden := TAtlasHiddenIndex.Create(Team.Hidden, Team.Folder)
    else
      FHidden := TAtlasHiddenIndex.Create(nil, '');
  end;
  Result := FHidden;
end;

procedure TAtlasIdeElements.DropOld(const AKey: string);
var
  Hits, Kept: TArray<TAtlasElementHit>;
  Hit: TAtlasElementHit;
begin
  if not FHits.TryGetValue(AKey, Hits) then
    Exit;
  Kept := nil;
  for Hit in Hits do
    if Hit.Round = FRound then
      Kept := Kept + [Hit];
  if Length(Kept) = 0 then
    FHits.Remove(AKey)
  else if Length(Kept) <> Length(Hits) then
    FHits[AKey] := Kept;
end;

procedure TAtlasIdeElements.BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
begin
  Inc(FRound);
end;

procedure TAtlasIdeElements.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
begin
  if (Context = nil) or (FHits.Count = 0) then
    Exit;
  try
    DropOld(KeyOf(Context.FileName, Context.LogicalLineNum - 1));
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hide, E);
  end;
end;

class procedure TAtlasIdeElements.Painted(const ATarget: TAtlasHideTarget; const ARect: TRect;
  ATopRow, ALineHeight: Integer);
var
  Key: string;
  Hits: TArray<TAtlasElementHit>;
  Hit: TAtlasElementHit;
  Index: Integer;
begin
  if FInstance = nil then
    Exit;
  Key := KeyOf(ATarget.FileName, ATarget.Line);
  FInstance.DropOld(Key);
  if not FInstance.FHits.TryGetValue(Key, Hits) then
  begin
    if FInstance.FHits.Count >= MaxLines then
      FInstance.FHits.Clear;
    Hits := nil;
  end;
  // Dasselbe Element mehrmals in einer Zeile (Läufe, mehrere Befunde): Rechtecke zusammenfassen.
  for Index := 0 to High(Hits) do
    if (Hits[Index].Target.Element = ATarget.Element) and (Hits[Index].Target.RuleId = ATarget.RuleId) then
    begin
      Hits[Index].Rect.Union(ARect);
      FInstance.FHits.AddOrSetValue(Key, Hits);
      Exit;
    end;
  Hit.Target := ATarget;
  Hit.Rect := ARect;
  Hit.TopRow := ATopRow;
  Hit.LineHeight := ALineHeight;
  Hit.Round := FInstance.FRound;
  FInstance.FHits.AddOrSetValue(Key, Hits + [Hit]);
end;

class procedure TAtlasIdeElements.Painted(AElement: TAtlasDrawnElement; const AFileName: string; ALine: Integer;
  const AAnchor: string; const ARect: TRect; ATopRow, ALineHeight: Integer);
begin
  if FInstance = nil then
    Exit;
  Painted(TAtlasHideTarget.Create(AElement, AFileName, ALine, AAnchor), ARect, ATopRow, ALineHeight);
end;

class function TAtlasIdeElements.Hidden(AElement: TAtlasDrawnElement; const AFileName, AAnchor: string): Boolean;
var
  Places: TAtlasHiddenIndex;
begin
  if FInstance = nil then
    Exit(False);
  Places := FInstance.Index;
  Result := not Places.IsEmpty and Places.Hidden(TAtlasDrawnElements.SettingKey(AElement), AFileName,
    TAtlasDrawnElements.Anchor(AAnchor));
end;

class function TAtlasIdeElements.FileHidden(AElement: TAtlasDrawnElement; const AFileName: string): Boolean;
var
  Places: TAtlasHiddenIndex;
begin
  if FInstance = nil then
    Exit(False);
  Places := FInstance.Index;
  Result := not Places.IsEmpty and Places.FileHidden(TAtlasDrawnElements.SettingKey(AElement), AFileName);
end;

class function TAtlasIdeElements.OnLine(const AFileName: string; ALine: Integer): TArray<TAtlasHideTarget>;
var
  Hits: TArray<TAtlasElementHit>;
  Hit: TAtlasElementHit;
begin
  Result := nil;
  if (FInstance = nil) or not FInstance.FHits.TryGetValue(KeyOf(AFileName, ALine), Hits) then
    Exit;
  for Hit in Hits do
    Result := Result + [Hit.Target];
end;

function TAtlasIdeElements.HitsAt(const AFileName: string; ATopRow, X, Y: Integer): TArray<TAtlasHideTarget>;
var
  Pair: TPair<string, TArray<TAtlasElementHit>>;
  Hit: TAtlasElementHit;
  Shifted: TRect;
begin
  Result := nil;
  for Pair in FHits do
    for Hit in Pair.Value do
    begin
      if not SameFile(Hit.Target.FileName, AFileName) then
        Break;
      Shifted := Hit.Rect;
      // Gescrollt, ohne dass die Zeile neu gezeichnet wurde: um die Zeilen verschieben.
      if (Hit.TopRow <> ATopRow) and (Hit.LineHeight > 0) then
        Shifted.Offset(0, (Hit.TopRow - ATopRow) * Hit.LineHeight);
      if PtInRect(Shifted, Point(X, Y)) then
        Result := Result + [Hit.Target];
    end;
end;

class function TAtlasIdeElements.At(const AFileName: string; ATopRow, X, Y: Integer): TArray<TAtlasHideTarget>;
begin
  if FInstance = nil then
    Exit(nil);
  Result := FInstance.HitsAt(AFileName, ATopRow, X, Y);
end;

class function TAtlasIdeElements.TakeClick(const AFileName: string; out ATargets: TArray<TAtlasHideTarget>): Boolean;
begin
  ATargets := nil;
  Result := False;
  if FInstance = nil then
    Exit;
  Result := (Length(FInstance.FClickTargets) > 0) and SameFile(FInstance.FClickFile, AFileName) and
    (TThread.GetTickCount64 - FInstance.FClickAt <= ClickMs);
  if Result then
    ATargets := FInstance.FClickTargets;
  FInstance.FClickTargets := nil;
  FInstance.FClickFile := '';
end;

class procedure TAtlasIdeElements.Reset;
var
  Services: INTACodeEditorServices;
begin
  if FInstance <> nil then
  begin
    FInstance.FHits.Clear;
    // .atlas wurde eben geschrieben: beim nächsten Zeichnen neu lesen.
    FInstance.FHiddenVersion := -1;
  end;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

procedure TAtlasIdeElements.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Targets, Overlays: TArray<TAtlasHideTarget>;
  Target: TAtlasHideTarget;
begin
  try
    FPendingWnd := 0;
    if Button <> mbRight then
    begin
      FClickTargets := nil;
      Exit;
    end;
    View := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      View := Editors.TopView;
    if (View = nil) or (View.Buffer = nil) then
      Exit;
    Targets := HitsAt(View.Buffer.FileName, View.TopRow, X, Y);
    FClickTargets := Targets;
    FClickFile := View.Buffer.FileName;
    FClickAt := TThread.GetTickCount64;
    // Nur auf überlagerten Elementen ersetzt das eigene Menü das der IDE; im Text bleibt es beim Kontextmenü.
    Overlays := nil;
    for Target in Targets do
      if TAtlasDrawnElements.Info(Target.Element).Overlay then
        Overlays := Overlays + [Target];
    if (Length(Overlays) > 0) and Assigned(FOnOverlayMenu) and (Editor <> nil) and Editor.HandleAllocated then
    begin
      FPendingWnd := Editor.Handle;
      FPendingAt := TThread.GetTickCount64;
      FPendingTargets := Overlays;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hide, E);
  end;
end;

procedure TAtlasIdeElements.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  Targets: TArray<TAtlasHideTarget>;
  Where: TPoint;
begin
  if (FPendingWnd = 0) or (Msg.hwnd <> FPendingWnd) then
    Exit;
  try
    if Msg.message = WM_RBUTTONUP then
    begin
      FPendingWnd := 0;
      if TThread.GetTickCount64 - FPendingAt > RightUpMs then
        Exit;
      // Loslassen schlucken: ohne es öffnet die IDE ihr Kontextmenü nicht.
      Handled := True;
      if GetCapture = Msg.hwnd then
        ReleaseCapture;
      Targets := FPendingTargets;
      FPendingTargets := nil;
      Where := Mouse.CursorPos;
      TAtlasMainThread.ForceQueue(TAtlasFeature.Hide,
        procedure
        begin
          if (FInstance <> nil) and Assigned(FOnOverlayMenu) then
            FOnOverlayMenu(Targets, Where);
        end);
    end
    else if Msg.message = WM_LBUTTONDOWN then
      FPendingWnd := 0;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hide, E);
  end;
end;

end.
