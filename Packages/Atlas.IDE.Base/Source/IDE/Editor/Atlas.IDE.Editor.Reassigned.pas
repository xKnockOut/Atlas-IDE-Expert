unit Atlas.IDE.Editor.Reassigned;

// Neu zugewiesene Variablen unterstreichen (#712) im Editor. Welche Namen
// zählen, rechnet der Server (atlas.server.reassigned,
// Atlas.Common.Semantics.Reassigned); Antwort lesen und Linien rechnen
// Atlas.Core.Editor.Reassigned. Hier bleiben Zeitgeber, Anfrage und Zeichnen.
// - Ein Zeitgeber (250 ms) liest die Ansicht vorn. Ruht der Text 700 ms, fragt
//   Atlas den laufenden Server im Hintergrund nach den Stellen im sichtbaren
//   Teil mit einer Bildschirmhöhe Rand (Arten aus
//   highlight.reassigned.targets); nur die jüngste Antwort zählt und je Datei,
//   Textstand, Arten und Bereich nur einmal. Verlässt die Ansicht den Bereich,
//   fragt Atlas neu. Scheitert die Anfrage, wartet Atlas 5 s; der Server bricht
//   die Rechnung beim Zeitlimit ab.
// - PaintLine (plsEndPaint) zieht unter jede Stelle eines neu zugewiesenen
//   Namens eine dünne Linie (highlight.reassigned.style: gepunktet,
//   durchgezogen, Welle) in der Akzentfarbe des Themas oder der eigenen Farbe
//   (highlight.reassigned.color); nur, solange die Zeile noch den Text vom
//   Abruf hat. Die Linie sitzt eine Einheit über der Wellenlinie der Probleme.
// - Den Hover („Neu zugewiesen: 3 Zuweisungen“) liefert der Server mit der
//   Hover-Antwort; Atlas.IDE.Hover.Editor blendet ihn mit der Einstellung aus.
// - highlight.reassigned aus oder Atlas aus: nichts. Je Datei oder überall
//   ausblenden über das Element Reassigned (#628) an der Linie.
// Gesichert über TAtlasFeature.Reassigned (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Style.Color,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Reassigned,
  Atlas.Core.Editor.Reassigned,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasReassignedSessionFunc = reference to function: TLspSession;

  TAtlasIdeReassigned = class
  public const
    cCommand = 'atlas.server.reassigned';
  private const
    cTickMs = 250;
    cQuietMs = 700;
    cTimeoutMs = 2000;
    cRetryMs = 5000;
    /// <summary>Anteil der Akzentfarbe am Hintergrund bei der Themenfarbe.</summary>
    cThemeStrength = 0.7;
    /// <summary>Zeilenhöhe in Pixeln je Einheit der Linie; die Linie wächst mit der Bildschirmskalierung.</summary>
    cRowPixelsPerUnit = 16;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeReassigned;
  private
    FSession: TAtlasReassignedSessionFunc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FWorkers: TAtlasWorkerSlot;
    FRequest: Integer;
    // Stand des Editors: Datei, Pufferstand und Zeitpunkt der letzten Änderung.
    FFileName: string;
    FVersion: Cardinal;
    FChangedAt: UInt64;
    FRetryAt: TAtlasDeadline;
    FAskedKey: string;
    FAskedRange: TAtlasReassignedRange;
    // Stand der Antwort: Datei, Pufferstand, Zeilen und Stellen.
    FShownFile: string;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FSet: TAtlasReassignedSet;
    FStyle: TAtlasReassignedStyle;
    FColor: string;
    procedure TimerTick(Sender: TObject);
    procedure Update;
    procedure Forget;
    procedure ApplyStyle(const AStyleText, AColorText: string);
    function Settled(const ASnapshot: TAtlasEditorSnapshot): Boolean;
    procedure Clear;
    procedure Ask(const AText: string; ATargets: TAtlasReassignedTargets; const ARange: TAtlasReassignedRange);
    procedure Accept(ARequest: Integer; const AFileName, AText: string;
      const ASet: TAtlasReassignedSet; AFailed: Boolean);
    function LineColor(ABack: TAtlasColor): TAtlasColor;
    procedure PaintUses(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
      const AUses: TArray<TAtlasReassignedUse>; ABack: TAtlasColor);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class function IsSource(const AFileName: string): Boolean; static;
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasReassignedSessionFunc);
    destructor Destroy; override;
    class procedure Install(const ASession: TAtlasReassignedSessionFunc); static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Editor.PaintedLine;

{ TAtlasIdeReassigned.TEvents }

function TAtlasIdeReassigned.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeReassigned.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeReassigned }

constructor TAtlasIdeReassigned.Create(const ASession: TAtlasReassignedSessionFunc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FIndex := -1;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeReassigned.Destroy;
var
  mServices: INTACodeEditorServices;
  mPainted: Boolean;
begin
  FreeAndNil(FTimer);
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  if FEvents <> nil then
  begin
    FEvents.OnEditorPaintLine := nil;
  end;
  FEventsRef := nil;
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: bis zu ihrem Ende abwarten (sie haben eine eigene
  // Zeitgrenze), nicht nur bis cStopMs.
  if FWorkers <> nil then
  begin
    FWorkers.Stop(TAtlasWorkerSlot.cWaitForever);
  end;
  FreeAndNil(FWorkers);
  mPainted := FSet.HasUses;
  Clear;
  if mPainted then
  begin
    Invalidate;
  end;
  inherited;
end;

class procedure TAtlasIdeReassigned.Install(const ASession: TAtlasReassignedSessionFunc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeReassigned.Create(ASession);
  end;
end;

class procedure TAtlasIdeReassigned.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeReassigned.Installed: Boolean;
begin
  Result := FInstance <> nil;
end;

class procedure TAtlasIdeReassigned.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

class function TAtlasIdeReassigned.IsSource(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := ExtractFileExt(AFileName);
  Result := SameText(mExtension, '.pas') or SameText(mExtension, '.dpr') or SameText(mExtension, '.dpk');
end;

procedure TAtlasIdeReassigned.Clear;
begin
  FSet := Default(TAtlasReassignedSet);
  FShownFile := '';
  FLines := nil;
  FAskedKey := '';
  FAskedRange := TAtlasReassignedRange.Whole;
end;

procedure TAtlasIdeReassigned.TimerTick(Sender: TObject);
begin
  try
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Reassigned, E);
  end;
end;

/// <summary>Linien und gemerkten Stand verwerfen.</summary>
procedure TAtlasIdeReassigned.Forget;
var
  mHad: Boolean;
begin
  mHad := FSet.HasUses;
  Clear;
  if mHad then
  begin
    Invalidate;
  end;
end;

/// <summary>Neue Linienart oder Farbe: neu zeichnen.</summary>
procedure TAtlasIdeReassigned.ApplyStyle(const AStyleText, AColorText: string);
var
  mStyle: TAtlasReassignedStyle;
begin
  mStyle := TAtlasReassignedNames.StyleOf(AStyleText);
  if (mStyle = FStyle) and (AColorText = FColor) then
  begin
    Exit;
  end;
  FStyle := mStyle;
  FColor := AColorText;
  if FSet.HasUses then
  begin
    Invalidate;
  end;
end;

/// <summary>Steht der Text aus ASnapshot seit der Tipp-Pause still und ist keine Wartezeit offen?</summary>
function TAtlasIdeReassigned.Settled(const ASnapshot: TAtlasEditorSnapshot): Boolean;
var
  mMoment: UInt64;
begin
  mMoment := TAtlasTicks.Now;
  Result := (ASnapshot.Version = FVersion) and SameText(ASnapshot.FileName, FFileName);
  if not Result then
  begin
    // Die Linien bleiben stehen (PaintLine prüft je Zeile den Text); gefragt wird nach der Tipp-Pause.
    FFileName := ASnapshot.FileName;
    FVersion := ASnapshot.Version;
    FChangedAt := mMoment;
    Exit;
  end;
  Result := (mMoment - FChangedAt >= cQuietMs) and FRetryAt.Reached;
end;

procedure TAtlasIdeReassigned.Update;
var
  mView: IOTAEditView;
  mSnapshot: TAtlasEditorSnapshot;
  mTargetsText, mStyleText, mColorText, mKey: string;
  mTargets: TAtlasReassignedTargets;
  mFirst, mLast: Integer;
begin
  mView := nil;
  if TAtlasIdeSettings.ReassignedOn(mTargetsText, mStyleText, mColorText) and
    not TAtlasGuard.Disabled(TAtlasFeature.Reassigned) then
  begin
    mView := TAtlasEditorBuffer.ActiveView;
  end;
  if mView = nil then
  begin
    // Aus oder kein Editor vorn: nichts zeigen, beim Wiederkommen neu fragen.
    Forget;
    Exit;
  end;
  // Kein Quelltext vorn: Die Linien der Quelldatei bleiben.
  if (mView.Buffer = nil) or not IsSource(mView.Buffer.FileName) then
  begin
    Exit;
  end;
  ApplyStyle(mStyleText, mColorText);
  mSnapshot := TAtlasEditorSnapshots.Get(mView);
  if not Settled(mSnapshot) then
  begin
    Exit;
  end;
  mTargets := TAtlasReassignedNames.ParseTargets(mTargetsText);
  mKey := Format('%s|%d|%s', [FFileName, FVersion, TAtlasReassignedNames.TargetsText(mTargets)]);
  mFirst := mView.TopRow - 1;
  mLast := Max(mFirst, mView.BottomRow - 1);
  // Nur der sichtbare Teil mit Rand: Die ganze Datei lief in großen Units ins Zeitlimit.
  if (mKey <> FAskedKey) or not FAskedRange.Contains(mFirst, mLast) then
  begin
    FAskedKey := mKey;
    FAskedRange := TAtlasReassignedRange.Around(mFirst, mLast);
    FTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
    Ask(mSnapshot.Text, mTargets, FAskedRange);
  end;
end;

/// <summary>Faden, der ASession fragt und die Antwort im Hauptthread an die laufende Hervorhebung gibt.</summary>
function Asker(ASession: TLspSession; const AArguments: string; ARequest: Integer;
  const AFileName, AText: string): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mAnswer: TJSONValue;
      mFound: TAtlasReassignedSet;
      mFailed: Boolean;
    begin
      mFound := Default(TAtlasReassignedSet);
      mFailed := False;
      try
        mAnswer := ASession.RunCommand(TAtlasIdeReassigned.cCommand, AArguments, TAtlasIdeReassigned.cTimeoutMs);
        try
          mFound := TAtlasReassignedSet.FromJson(mAnswer);
        finally
          mAnswer.Free;
        end;
      except
        // Server beschäftigt, weg oder zu alt (Befehl unbekannt): später noch einmal, der Editor bleibt frei.
        mFailed := True;
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.Reassigned,
        procedure
        begin
          if TAtlasIdeReassigned.FInstance <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.Reassigned,
              procedure
              begin
                if TAtlasIdeReassigned.FInstance <> nil then
                begin
                  TAtlasIdeReassigned.FInstance.Accept(ARequest, AFileName, AText, mFound, mFailed);
                end;
              end);
          end;
        end);
    end);
end;

procedure TAtlasIdeReassigned.Ask(const AText: string; ATargets: TAtlasReassignedTargets;
  const ARange: TAtlasReassignedRange);
var
  mSession: TLspSession;
  mWorker: TThread;
begin
  if not Assigned(FSession) then
  begin
    Exit;
  end;
  mSession := FSession();
  if mSession = nil then
  begin
    // Server läuft (noch) nicht: beim nächsten Takt nach der Wartezeit noch einmal.
    FAskedKey := '';
    FRetryAt := TAtlasDeadline.After(cRetryMs);
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FFileName, AText);
  FWorkers.Prune;
  Inc(FRequest);
  mWorker := Asker(mSession, TAtlasReassigned.Arguments(TLspSession.PathToUri(FFileName), ATargets, ARange),
    FRequest, FFileName, AText);
  FWorkers.Start(mWorker);
end;

procedure TAtlasIdeReassigned.Accept(ARequest: Integer; const AFileName, AText: string;
  const ASet: TAtlasReassignedSet; AFailed: Boolean);
var
  mHad: Boolean;
begin
  if ARequest <> FRequest then
  begin
    Exit;
  end;
  if AFailed then
  begin
    FAskedKey := '';
    FRetryAt := TAtlasDeadline.After(cRetryMs);
    Exit;
  end;
  if not ASet.Valid then
  begin
    Exit;
  end;
  mHad := FSet.HasUses;
  FSet := ASet;
  FShownFile := AFileName;
  FLines := TTextLines.SplitLines(AText);
  if mHad or FSet.HasUses then
  begin
    Invalidate;
  end;
end;

function TAtlasIdeReassigned.LineColor(ABack: TAtlasColor): TAtlasColor;
begin
  if not TAtlasReassignedNames.TryColor(FColor, Result) then
  begin
    Result := TAtlasColorMath.Mix(TAtlasColors.ForBackground(ABack).Accent, ABack, cThemeStrength);
  end;
end;

procedure TAtlasIdeReassigned.PaintUses(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AText: string; const AUses: TArray<TAtlasReassignedUse>; ABack: TAtlasColor);
var
  mUse: TAtlasReassignedUse;
  mPart: TAtlasUnderlineSegment;
  mFirst, mLast, mCode, mMark: TRect;
  mCanvas: TCanvas;
  mDC: HDC;
  mSaved, mStep, mBaseline: Integer;
begin
  mCanvas := AContext.Canvas;
  mDC := mCanvas.Handle;
  mCode := AContext.LineState.CodeRect;
  // Eine Einheit je 16 Pixel Zeilenhöhe: wächst mit der Bildschirmskalierung.
  mStep := Max(1, ARect.Height div cRowPixelsPerUnit);
  // Über der Wellenlinie der Probleme (Rect.Bottom - 2), damit beide lesbar bleiben.
  mBaseline := ARect.Bottom - 2 - 2 * mStep;
  mSaved := SaveDC(mDC);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    mCanvas.Pen.Color := TColor(LineColor(ABack));
    mCanvas.Pen.Width := mStep;
    mCanvas.Pen.Style := psSolid;
    for mUse in AUses do
    begin
      mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mUse.Character, FTabWidth),
        AContext.EditorLineNum);
      mLast := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mUse.EndCharacter, FTabWidth),
        AContext.EditorLineNum);
      for mPart in TAtlasReassigned.Segments(FStyle, mFirst.Left, Max(mLast.Left, mFirst.Left + 1), mBaseline, mStep) do
      begin
        mCanvas.MoveTo(mPart.X1, mPart.Y1);
        mCanvas.LineTo(mPart.X2, mPart.Y2);
      end;
      mMark := TRect.Create(mFirst.Left, mBaseline - 2 * mStep, Max(mLast.Left, mFirst.Left + 1), ARect.Bottom);
      TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.Reassigned, AContext.FileName,
        AContext.LogicalLineNum - 1, AText), mMark, AContext.EditView.TopRow, ARect.Height);
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TAtlasIdeReassigned.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mFound: TArray<TAtlasReassignedUse>;
  mLine: Integer;
begin
  if not FSet.HasUses or TAtlasGuard.Disabled(TAtlasFeature.Reassigned) then
  begin
    Exit;
  end;
  try
    // Nur, wenn die Zeile im Editor dem gefragten Stand entspricht (sonst kommt nach der Tipp-Pause eine neue
    // Antwort).
    if not TAtlasPaintedLine.Resolve(Stage, BeforeEvent, Context, FShownFile, FLines, mLine) or
      TAtlasIdeElements.FileHidden(TAtlasDrawnElement.Reassigned, Context.FileName) then
    begin
      Exit;
    end;
    mFound := FSet.UsesAt(mLine);
    if Length(mFound) > 0 then
    begin
      PaintUses(Rect, Context, FLines[mLine], mFound, TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2,
        Rect.Top + 1));
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Reassigned, E);
  end;
end;

end.
