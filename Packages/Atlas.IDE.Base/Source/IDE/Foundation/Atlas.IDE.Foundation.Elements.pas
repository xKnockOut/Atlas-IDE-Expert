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
    function HitsAt(const AFileName: string; ATopRow, AX, AY: Integer): TArray<TAtlasHideTarget>;
  public
    constructor Create;
    destructor Destroy; override;
    class procedure Start; static;
    class procedure Stop; static;
    /// <summary>AElement an ALine (0-basiert) von AFileName gezeichnet; ARect in Koordinaten des Editors,
    /// ATopRow die oberste Zeile der Ansicht, ALineHeight die Zeilenhöhe in Pixeln.</summary>
    class procedure Painted(const ATarget: TAtlasHideTarget; const ARect: TRect; ATopRow, ALineHeight: Integer);
      static;
    /// <summary>Ziel für Painted: AElement an ALine (0-basiert) von AFileName mit dem Rohtext AAnchor.</summary>
    class function Target(AElement: TAtlasDrawnElement; const AFileName: string; ALine: Integer;
      const AAnchor: string): TAtlasHideTarget; static;
    /// <summary>Element an AAnchor (Rohtext, wird normalisiert) per .atlas ausgeblendet?</summary>
    class function Hidden(AElement: TAtlasDrawnElement; const AFileName, AAnchor: string): Boolean; static;
    /// <summary>Element in der ganzen Datei per .atlas ausgeblendet?</summary>
    class function FileHidden(AElement: TAtlasDrawnElement; const AFileName: string): Boolean; static;
    /// <summary>Zuletzt an ALine (0-basiert) gezeichnete Elemente, je Element einmal.</summary>
    class function OnLine(const AFileName: string; ALine: Integer): TArray<TAtlasHideTarget>; static;
    /// <summary>Elemente unter X, Y (Koordinaten des Editors) bei oberster Zeile ATopRow.</summary>
    class function At(const AFileName: string; ATopRow, AX, AY: Integer): TArray<TAtlasHideTarget>; static;
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
  mServices: INTACodeEditorServices;
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
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  FAppEvents := TApplicationEvents.Create(nil);
  FAppEvents.OnMessage := AppMessage;
end;

destructor TAtlasIdeElements.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  if FAppEvents <> nil then
  begin
    FAppEvents.OnMessage := nil;
    FAppEvents.Free;
  end;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
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
  begin
    FInstance := TAtlasIdeElements.Create;
  end;
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
  mTeam: TAtlasTeamSettings;
begin
  if (FHidden = nil) or (FHiddenVersion <> TAtlasIdeTeamFile.Version) then
  begin
    FreeAndNil(FHidden);
    FHiddenVersion := TAtlasIdeTeamFile.Version;
    mTeam := TAtlasIdeTeamFile.Current;
    if mTeam.Valid then
    begin
      FHidden := TAtlasHiddenIndex.Create(mTeam.Hidden, mTeam.Folder);
    end
    else
    begin
      FHidden := TAtlasHiddenIndex.Create(nil, '');
    end;
  end;
  Result := FHidden;
end;

procedure TAtlasIdeElements.DropOld(const AKey: string);
var
  mHits, mKept: TArray<TAtlasElementHit>;
  mHit: TAtlasElementHit;
begin
  if not FHits.TryGetValue(AKey, mHits) then
  begin
    Exit;
  end;
  mKept := nil;
  for mHit in mHits do
  begin
    if mHit.Round = FRound then
    begin
      mKept := mKept + [mHit];
    end;
  end;
  if Length(mKept) = 0 then
  begin
    FHits.Remove(AKey);
  end
  else if Length(mKept) <> Length(mHits) then
  begin
    FHits[AKey] := mKept;
  end;
end;

procedure TAtlasIdeElements.BeginPaint(const Editor: TWinControl; const ForceFullRepaint: Boolean);
begin
  Inc(FRound);
end;

procedure TAtlasIdeElements.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
begin
  if (Context = nil) or (FHits.Count = 0) then
  begin
    Exit;
  end;
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
  mKey: string;
  mHits: TArray<TAtlasElementHit>;
  mHit: TAtlasElementHit;
  mIndex: Integer;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  mKey := KeyOf(ATarget.FileName, ATarget.Line);
  FInstance.DropOld(mKey);
  if not FInstance.FHits.TryGetValue(mKey, mHits) then
  begin
    if FInstance.FHits.Count >= MaxLines then
    begin
      FInstance.FHits.Clear;
    end;
    mHits := nil;
  end;
  // Dasselbe Element mehrmals in einer Zeile (Läufe, mehrere Befunde): Rechtecke zusammenfassen.
  for mIndex := 0 to High(mHits) do
  begin
    if (mHits[mIndex].Target.Element = ATarget.Element) and (mHits[mIndex].Target.RuleId = ATarget.RuleId) then
    begin
      mHits[mIndex].Rect.Union(ARect);
      FInstance.FHits.AddOrSetValue(mKey, mHits);
      Exit;
    end;
  end;
  mHit.Target := ATarget;
  mHit.Rect := ARect;
  mHit.TopRow := ATopRow;
  mHit.LineHeight := ALineHeight;
  mHit.Round := FInstance.FRound;
  FInstance.FHits.AddOrSetValue(mKey, mHits + [mHit]);
end;

class function TAtlasIdeElements.Target(AElement: TAtlasDrawnElement; const AFileName: string; ALine: Integer;
  const AAnchor: string): TAtlasHideTarget;
begin
  Result := TAtlasHideTarget.Create(AElement, AFileName, ALine, AAnchor);
end;

class function TAtlasIdeElements.Hidden(AElement: TAtlasDrawnElement; const AFileName, AAnchor: string): Boolean;
var
  mPlaces: TAtlasHiddenIndex;
begin
  if FInstance = nil then
  begin
    Exit(False);
  end;
  mPlaces := FInstance.Index;
  Result := not mPlaces.IsEmpty and mPlaces.Hidden(TAtlasDrawnElements.SettingKey(AElement), AFileName,
    TAtlasDrawnElements.Anchor(AAnchor));
end;

class function TAtlasIdeElements.FileHidden(AElement: TAtlasDrawnElement; const AFileName: string): Boolean;
var
  mPlaces: TAtlasHiddenIndex;
begin
  if FInstance = nil then
  begin
    Exit(False);
  end;
  mPlaces := FInstance.Index;
  Result := not mPlaces.IsEmpty and mPlaces.FileHidden(TAtlasDrawnElements.SettingKey(AElement), AFileName);
end;

class function TAtlasIdeElements.OnLine(const AFileName: string; ALine: Integer): TArray<TAtlasHideTarget>;
var
  mHits: TArray<TAtlasElementHit>;
  mHit: TAtlasElementHit;
begin
  Result := nil;
  if (FInstance = nil) or not FInstance.FHits.TryGetValue(KeyOf(AFileName, ALine), mHits) then
  begin
    Exit;
  end;
  for mHit in mHits do
  begin
    Result := Result + [mHit.Target];
  end;
end;

function TAtlasIdeElements.HitsAt(const AFileName: string; ATopRow, AX, AY: Integer): TArray<TAtlasHideTarget>;
var
  mPair: TPair<string, TArray<TAtlasElementHit>>;
  mHit: TAtlasElementHit;
  mShifted: TRect;
begin
  Result := nil;
  for mPair in FHits do
  begin
    for mHit in mPair.Value do
    begin
      if not SameFile(mHit.Target.FileName, AFileName) then
      begin
        Break;
      end;
      mShifted := mHit.Rect;
      // Gescrollt, ohne dass die Zeile neu gezeichnet wurde: um die Zeilen verschieben.
      if (mHit.TopRow <> ATopRow) and (mHit.LineHeight > 0) then
      begin
        mShifted.Offset(0, (mHit.TopRow - ATopRow) * mHit.LineHeight);
      end;
      if PtInRect(mShifted, Point(AX, AY)) then
      begin
        Result := Result + [mHit.Target];
      end;
    end;
  end;
end;

class function TAtlasIdeElements.At(const AFileName: string; ATopRow, AX, AY: Integer): TArray<TAtlasHideTarget>;
begin
  if FInstance = nil then
  begin
    Exit(nil);
  end;
  Result := FInstance.HitsAt(AFileName, ATopRow, AX, AY);
end;

class function TAtlasIdeElements.TakeClick(const AFileName: string; out ATargets: TArray<TAtlasHideTarget>): Boolean;
begin
  ATargets := nil;
  Result := False;
  if FInstance = nil then
  begin
    Exit;
  end;
  Result := (Length(FInstance.FClickTargets) > 0) and SameFile(FInstance.FClickFile, AFileName) and
    (TThread.GetTickCount64 - FInstance.FClickAt <= ClickMs);
  if Result then
  begin
    ATargets := FInstance.FClickTargets;
  end;
  FInstance.FClickTargets := nil;
  FInstance.FClickFile := '';
end;

class procedure TAtlasIdeElements.Reset;
var
  mServices: INTACodeEditorServices;
begin
  if FInstance <> nil then
  begin
    FInstance.FHits.Clear;
    // .atlas wurde eben geschrieben: beim nächsten Zeichnen neu lesen.
    FInstance.FHiddenVersion := -1;
  end;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

procedure TAtlasIdeElements.EditorMouseDown(const Editor: TWinControl; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
  mTargets, mOverlays: TArray<TAtlasHideTarget>;
  mTarget: TAtlasHideTarget;
begin
  try
    FPendingWnd := 0;
    if Button <> mbRight then
    begin
      FClickTargets := nil;
      Exit;
    end;
    mView := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
    begin
      mView := mEditors.TopView;
    end;
    if (mView = nil) or (mView.Buffer = nil) then
    begin
      Exit;
    end;
    mTargets := HitsAt(mView.Buffer.FileName, mView.TopRow, X, Y);
    FClickTargets := mTargets;
    FClickFile := mView.Buffer.FileName;
    FClickAt := TThread.GetTickCount64;
    // Nur auf überlagerten Elementen ersetzt das eigene Menü das der IDE; im Text bleibt es beim Kontextmenü.
    mOverlays := nil;
    for mTarget in mTargets do
    begin
      if TAtlasDrawnElements.Info(mTarget.Element).Overlay then
      begin
        mOverlays := mOverlays + [mTarget];
      end;
    end;
    if (Length(mOverlays) > 0) and Assigned(FOnOverlayMenu) and (Editor <> nil) and Editor.HandleAllocated then
    begin
      FPendingWnd := Editor.Handle;
      FPendingAt := TThread.GetTickCount64;
      FPendingTargets := mOverlays;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hide, E);
  end;
end;

procedure TAtlasIdeElements.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  mTargets: TArray<TAtlasHideTarget>;
  mWhere: TPoint;
begin
  if (FPendingWnd = 0) or (Msg.hwnd <> FPendingWnd) then
  begin
    Exit;
  end;
  try
    if Msg.message = WM_RBUTTONUP then
    begin
      FPendingWnd := 0;
      if TThread.GetTickCount64 - FPendingAt > RightUpMs then
      begin
        Exit;
      end;
      // Loslassen schlucken: ohne es öffnet die IDE ihr Kontextmenü nicht.
      Handled := True;
      if GetCapture = Msg.hwnd then
      begin
        ReleaseCapture;
      end;
      mTargets := FPendingTargets;
      FPendingTargets := nil;
      mWhere := Mouse.CursorPos;
      TAtlasMainThread.ForceQueue(TAtlasFeature.Hide,
        procedure
        begin
          if (FInstance <> nil) and Assigned(FOnOverlayMenu) then
          begin
            FOnOverlayMenu(mTargets, mWhere);
          end;
        end);
    end
    else if Msg.message = WM_LBUTTONDOWN then
    begin
      FPendingWnd := 0;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hide, E);
  end;
end;

end.
