unit Atlas.IDE.Editor.ExitPoints;

// Austrittspunkte hervorheben (#698) im Editor. Welche Stellen zählen, rechnet
// der Server (atlas.server.exitPoints, Atlas.Common.Semantics.ExitPoints);
// Antwort lesen, Auslöser und Sprünge rechnet Atlas.Core.Editor.ExitPoints.
// Hier bleiben Zeitgeber, Anfrage, Zeichnen und F3.
// - Ein Zeitgeber (100 ms) liest den Cursor der Ansicht vorn. Steht er auf
//   einem Auslöser (TAtlasExitPoints.Triggers) und ruht zwei Takte, fragt Atlas
//   den laufenden Server im Hintergrund; nur die jüngste Antwort zählt, und
//   nur, solange der Text derselbe ist (TAtlasEditorSnapshots).
// - Steht der Cursor auf einer markierten Stelle oder dem Routinennamen, bleibt
//   die Hervorhebung (F3 springt so auch auf das end); woanders verschwindet
//   sie, ebenso bei jeder Änderung am Text und mit einer Markierung (dann
//   gehört F3 der Markierungssuche).
// - PaintLine (plsEndPaint) überzieht jede Stelle halb durchsichtig: Austritte
//   in der Warnfarbe, Austritte ohne Ergebnis und die Quellen einer Exception
//   in der Fehlerfarbe, Zuweisungen an Result in der Farbe für Hinzugefügtes,
//   Schleifen in der Akzentfarbe. Hinter dem Routinenkopf steht die Marke
//   („3 Austritte“, editor.exitPoints.badge); den Platz teilt sie mit den
//   anderen Zeichnern (TAtlasLineTail).
// - F3/Umschalt+F3 (Atlas.IDE.Commands.Bindings) springt reihum, solange die
//   Hervorhebung steht und der Cursor auf einer ihrer Stellen liegt.
// - editor.exitPoints aus oder Atlas aus: nichts. Je Datei oder überall
//   ausblenden über das Element ExitPoints (#628) an der Marke.
// Gesichert über TAtlasFeature.ExitPoints (#493). Nur im Hauptthread.

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
  Atlas.Core.Editor.ExitPoints,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasExitPointsSessionFunc = reference to function: TLspSession;

  TAtlasIdeExitPoints = class
  public const
    cCommand = 'atlas.server.exitPoints';
  private const
    cTickMs = 100;
    /// <summary>So viele Takte ohne Bewegung, bevor Atlas den Server fragt.</summary>
    cIdleTicks = 2;
    cTimeoutMs = 1500;
    /// <summary>Deckkraft der Stellen über dem Text (0–255).</summary>
    cPointAlpha = 70;
    /// <summary>Anteil der Farbe am Hintergrund der Marke.</summary>
    cMarkStrength = 0.16;
    /// <summary>Innenabstand der Marke links und rechts in Pixeln.</summary>
    cMarkPadding = 4;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeExitPoints;
  private
    FSession: TAtlasExitPointsSessionFunc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FTimer: TTimer;
    FWorkers: TAtlasWorkerSlot;
    FFont: TFont;
    FFontKey: string;
    FRequest: Integer;
    FIdleKey: string;
    FIdleCount: Integer;
    FAskedKey: string;
    // Stand der Hervorhebung: Datei, Pufferstand, Zeilen und Antwort.
    FFileName: string;
    FVersion: Cardinal;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FSet: TAtlasExitPointSet;
    FBadge: Boolean;
    procedure TimerTick(Sender: TObject);
    procedure Update;
    procedure Forget;
    procedure Load(const AView: IOTAEditView; const ASnapshot: TAtlasEditorSnapshot);
    function Due(ALine, ACharacter: Integer; AExceptions, ALoops: Boolean): Boolean;
    procedure Clear;
    procedure Ask(const AText: string; ALine, ACharacter: Integer; AExceptions, ALoops: Boolean);
    procedure Accept(ARequest: Integer; const AFileName: string; AVersion: Cardinal; const ASet: TAtlasExitPointSet);
    procedure EnsureFont(const AEditorFont: TFont);
    function Jump(ABackward: Boolean): Boolean;
    procedure PaintPoints(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
      const APoints: TArray<TAtlasExitPoint>; ABack: TAtlasColor);
    procedure PaintBadge(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
      ABack: TAtlasColor);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasExitPointsSessionFunc);
    destructor Destroy; override;
    class procedure Install(const ASession: TAtlasExitPointsSessionFunc); static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
    /// <summary>F3 (ABackward: Umschalt+F3): zur nächsten Stelle springen, solange die Hervorhebung steht und der
    /// Cursor auf einer ihrer Stellen liegt; sonst False (die Taste geht weiter).</summary>
    class function TryJump(ABackward: Boolean): Boolean; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Editor.Elements,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Editor.PaintedLine;

function RoleColor(const AColors: TAtlasColors; ARole: TAtlasExitPointRole): TAtlasColor;
begin
  case ARole of
    TAtlasExitPointRole.Assign:
      Result := AColors.Add;
    TAtlasExitPointRole.Missing, TAtlasExitPointRole.Source:
      Result := AColors.Error;
    TAtlasExitPointRole.Loop:
      Result := AColors.Accent;
  else
    Result := AColors.Warn;
  end;
end;

{ TAtlasIdeExitPoints.TEvents }

function TAtlasIdeExitPoints.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeExitPoints.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeExitPoints }

constructor TAtlasIdeExitPoints.Create(const ASession: TAtlasExitPointsSessionFunc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FIndex := -1;
  FWorkers := TAtlasWorkerSlot.Create(HInstance);
  FFont := TFont.Create;
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

destructor TAtlasIdeExitPoints.Destroy;
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
  mPainted := FSet.Found;
  Clear;
  FreeAndNil(FFont);
  if mPainted then
  begin
    Invalidate;
  end;
  inherited;
end;

class procedure TAtlasIdeExitPoints.Install(const ASession: TAtlasExitPointsSessionFunc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeExitPoints.Create(ASession);
  end;
end;

class procedure TAtlasIdeExitPoints.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeExitPoints.Installed: Boolean;
begin
  Result := FInstance <> nil;
end;

class procedure TAtlasIdeExitPoints.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

function IsSource(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := ExtractFileExt(AFileName);
  Result := SameText(mExtension, '.pas') or SameText(mExtension, '.dpr') or SameText(mExtension, '.dpk') or
    SameText(mExtension, '.inc');
end;

procedure ReadCaret(const AView: IOTAEditView; out ALine, ACharacter: Integer);
var
  mCursor: TOTAEditPos;
  mLineText: string;
begin
  mCursor := AView.CursorPos;
  ALine := Max(0, mCursor.Line - 1);
  mLineText := TAtlasEditorBuffer.LineText(AView, ALine + 1);
  ACharacter := Min(TLspSession.ColumnToIndex(mLineText, mCursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer)),
    Length(mLineText));
end;

function HasBlock(const AView: IOTAEditView): Boolean;
var
  mBlock: IOTAEditBlock;
begin
  mBlock := AView.Block;
  Result := (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0);
end;

procedure TAtlasIdeExitPoints.Clear;
begin
  FSet := Default(TAtlasExitPointSet);
  FFileName := '';
  FVersion := 0;
  FLines := nil;
  FAskedKey := '';
end;

procedure TAtlasIdeExitPoints.TimerTick(Sender: TObject);
begin
  try
    Update;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ExitPoints, E);
  end;
end;

/// <summary>Hervorhebung und gemerkten Stand verwerfen.</summary>
procedure TAtlasIdeExitPoints.Forget;
var
  mHad: Boolean;
begin
  mHad := FSet.Found;
  Clear;
  if mHad then
  begin
    Invalidate;
  end;
end;

/// <summary>Neuer Text in ASnapshot: Die alte Antwort gilt nicht mehr.</summary>
procedure TAtlasIdeExitPoints.Load(const AView: IOTAEditView; const ASnapshot: TAtlasEditorSnapshot);
begin
  if (ASnapshot.Version = FVersion) and SameText(ASnapshot.FileName, FFileName) then
  begin
    Exit;
  end;
  Forget;
  FFileName := ASnapshot.FileName;
  FVersion := ASnapshot.Version;
  FLines := TTextLines.SplitLines(ASnapshot.Text);
  FTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
end;

/// <summary>Steht die Schreibmarke lange genug auf einem Wort, nach dem noch nicht gefragt wurde?</summary>
function TAtlasIdeExitPoints.Due(ALine, ACharacter: Integer; AExceptions, ALoops: Boolean): Boolean;
var
  mLineText, mKey: string;
  mStart, mStop: Integer;
begin
  Result := False;
  mLineText := '';
  if ALine < Length(FLines) then
  begin
    mLineText := FLines[ALine];
  end;
  if not TAtlasExitPoints.Triggers(mLineText, ACharacter) or
    not TAtlasExitPoints.WordAt(mLineText, ACharacter, mStart, mStop) then
  begin
    FIdleKey := '';
    FAskedKey := '';
    Exit;
  end;
  // Je Wort eine Anfrage: Cursorbewegungen innerhalb des Worts ändern den Schlüssel nicht.
  mKey := Format('%s|%d|%d|%d|%d|%d', [FFileName, FVersion, ALine, mStart, Ord(AExceptions), Ord(ALoops)]);
  if mKey <> FIdleKey then
  begin
    FIdleKey := mKey;
    FIdleCount := 0;
    Exit;
  end;
  Inc(FIdleCount);
  Result := (FIdleCount >= cIdleTicks) and (mKey <> FAskedKey);
  if Result then
  begin
    FAskedKey := mKey;
  end;
end;

procedure TAtlasIdeExitPoints.Update;
var
  mView: IOTAEditView;
  mSnapshot: TAtlasEditorSnapshot;
  mExceptions, mLoops, mBadge: Boolean;
  mLine, mCharacter: Integer;
begin
  mView := nil;
  mBadge := False;
  if TAtlasIdeSettings.ExitPointsOn(mExceptions, mLoops, mBadge) and
    not TAtlasGuard.Disabled(TAtlasFeature.ExitPoints) then
  begin
    mView := TAtlasEditorBuffer.ActiveView;
  end;
  if (mView = nil) or (mView.Buffer = nil) or not IsSource(mView.Buffer.FileName) or HasBlock(mView) then
  begin
    Forget;
    Exit;
  end;
  if mBadge <> FBadge then
  begin
    FBadge := mBadge;
    if FSet.Found then
    begin
      Invalidate;
    end;
  end;
  mSnapshot := TAtlasEditorSnapshots.Get(mView);
  Load(mView, mSnapshot);
  ReadCaret(mView, mLine, mCharacter);
  if FSet.Holds(mLine, mCharacter) then
  begin
    Exit;
  end;
  if FSet.Found then
  begin
    FSet := Default(TAtlasExitPointSet);
    Invalidate;
  end;
  if Due(mLine, mCharacter, mExceptions, mLoops) then
  begin
    Ask(mSnapshot.Text, mLine, mCharacter, mExceptions, mLoops);
  end;
end;

/// <summary>Argumente der Anfrage: Datei, Position und Optionen.</summary>
function ExitPointArguments(const AFileName: string; ALine, ACharacter: Integer; AExceptions,
  ALoops: Boolean): string;
var
  mValues: TJSONArray;
  mPosition, mOptions: TJSONObject;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(AFileName));
    mPosition := TJSONObject.Create;
    mPosition.AddPair('line', TJSONNumber.Create(ALine));
    mPosition.AddPair('character', TJSONNumber.Create(ACharacter));
    mValues.AddElement(mPosition);
    mOptions := TJSONObject.Create;
    mOptions.AddPair('exceptions', TJSONBool.Create(AExceptions));
    mOptions.AddPair('loops', TJSONBool.Create(ALoops));
    mValues.AddElement(mOptions);
    Result := mValues.ToJSON;
  finally
    mValues.Free;
  end;
end;

/// <summary>Faden, der ASession fragt und die Antwort im Hauptthread an die laufende Hervorhebung gibt.</summary>
function Asker(ASession: TLspSession; const AArguments: string; ARequest: Integer; const AFileName: string;
  AVersion: Cardinal): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mAnswer: TJSONValue;
      mFound: TAtlasExitPointSet;
    begin
      mFound := Default(TAtlasExitPointSet);
      try
        mAnswer := ASession.RunCommand(TAtlasIdeExitPoints.cCommand, AArguments, TAtlasIdeExitPoints.cTimeoutMs);
        try
          mFound := TAtlasExitPointSet.FromJson(mAnswer);
        finally
          mAnswer.Free;
        end;
      except
        // Server beschäftigt, weg oder zu alt (Befehl unbekannt): keine Hervorhebung, der Editor bleibt frei.
        mFound := Default(TAtlasExitPointSet);
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.ExitPoints,
        procedure
        begin
          if TAtlasIdeExitPoints.FInstance <> nil then
          begin
            TAtlasGuard.Run(TAtlasFeature.ExitPoints,
              procedure
              begin
                if TAtlasIdeExitPoints.FInstance <> nil then
                begin
                  TAtlasIdeExitPoints.FInstance.Accept(ARequest, AFileName, AVersion, mFound);
                end;
              end);
          end;
        end);
    end);
end;

procedure TAtlasIdeExitPoints.Ask(const AText: string; ALine, ACharacter: Integer; AExceptions, ALoops: Boolean);
var
  mSession: TLspSession;
  mWorker: TThread;
begin
  mSession := nil;
  if Assigned(FSession) then
  begin
    mSession := FSession();
  end;
  if mSession = nil then
  begin
    Exit;
  end;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  mSession.Sync(FFileName, AText);
  FWorkers.Prune;
  Inc(FRequest);
  mWorker := Asker(mSession, ExitPointArguments(FFileName, ALine, ACharacter, AExceptions, ALoops), FRequest,
    FFileName, FVersion);
  FWorkers.Start(mWorker);
end;

procedure TAtlasIdeExitPoints.Accept(ARequest: Integer; const AFileName: string; AVersion: Cardinal;
  const ASet: TAtlasExitPointSet);
begin
  // Nur die jüngste Antwort und nur für den Text, nach dem gefragt wurde.
  if (ARequest <> FRequest) or not SameText(AFileName, FFileName) or (AVersion <> FVersion) then
  begin
    Exit;
  end;
  FSet := ASet;
  if FSet.Found then
  begin
    Invalidate;
  end;
end;

class function TAtlasIdeExitPoints.TryJump(ABackward: Boolean): Boolean;
begin
  Result := (FInstance <> nil) and not TAtlasGuard.Disabled(TAtlasFeature.ExitPoints) and FInstance.Jump(ABackward);
end;

function TAtlasIdeExitPoints.Jump(ABackward: Boolean): Boolean;
var
  mView: IOTAEditView;
  mSnapshot: TAtlasEditorSnapshot;
  mLine, mCharacter: Integer;
  mPoint: TAtlasExitPoint;
  mPosition: TOTAEditPos;
  mLineText: string;
begin
  Result := False;
  if not FSet.Found then
  begin
    Exit;
  end;
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView = nil) or (mView.Buffer = nil) or HasBlock(mView) then
  begin
    Exit;
  end;
  mSnapshot := TAtlasEditorSnapshots.Get(mView);
  if not SameText(mSnapshot.FileName, FFileName) or (mSnapshot.Version <> FVersion) then
  begin
    Exit;
  end;
  ReadCaret(mView, mLine, mCharacter);
  if not FSet.Holds(mLine, mCharacter) or not FSet.Next(mLine, mCharacter, ABackward, mPoint) then
  begin
    Exit;
  end;
  mLineText := '';
  if mPoint.Line < Length(FLines) then
  begin
    mLineText := FLines[mPoint.Line];
  end;
  mPosition.Line := mPoint.Line + 1;
  mPosition.Col := TLspSession.IndexToColumn(mLineText, mPoint.Character, FTabWidth);
  mView.CursorPos := mPosition;
  mView.MoveViewToCursor;
  mView.Paint;
  Result := True;
end;

procedure TAtlasIdeExitPoints.EnsureFont(const AEditorFont: TFont);
var
  mKey: string;
begin
  mKey := AEditorFont.Name + '|' + IntToStr(AEditorFont.Size) + '|' + IntToStr(AEditorFont.PixelsPerInch);
  if mKey = FFontKey then
  begin
    Exit;
  end;
  FFont.Assign(AEditorFont);
  FFont.Style := [];
  FFontKey := mKey;
end;

procedure TAtlasIdeExitPoints.PaintPoints(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AText: string; const APoints: TArray<TAtlasExitPoint>; ABack: TAtlasColor);
var
  mPoint: TAtlasExitPoint;
  mColors: TAtlasColors;
  mFirst, mLast, mCode: TRect;
  mDC: HDC;
  mSaved: Integer;
begin
  mColors := TAtlasColors.ForBackground(ABack);
  mDC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mSaved := SaveDC(mDC);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mPoint in APoints do
    begin
      mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mPoint.Character, FTabWidth),
        AContext.EditorLineNum);
      mLast := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mPoint.EndCharacter, FTabWidth),
        AContext.EditorLineNum);
      TAtlasIdeStyle.Blend(mDC, TRect.Create(mFirst.Left, ARect.Top, Max(mLast.Left, mFirst.Left + 1), ARect.Bottom),
        COLORREF(ColorToRGB(TColor(RoleColor(mColors, mPoint.Role)))), cPointAlpha);
    end;
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TAtlasIdeExitPoints.PaintBadge(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const AText: string; ABack: TAtlasColor);
var
  mCaption, mKey: string;
  mCell, mMark: TRect;
  mColors: TAtlasColors;
  mTone: TAtlasColor;
  mDC: HDC;
  mSaved, X, mTop: Integer;
  mSize: TSize;
  mBrush: HBRUSH;
begin
  mCaption := TAtlasExitPoints.BadgeText(FSet, TAtlasStrings.Text(TAtlasTextId.ExitPointsOne),
    TAtlasStrings.Text(TAtlasTextId.ExitPointsCount), TAtlasStrings.Text(TAtlasTextId.ExitPointsResultMissing));
  mCell := AContext.EditorState.GetCharacterPosPx(
    TLspSession.IndexToColumn(AText, Length(TrimRight(AText)), FTabWidth) + 2, AContext.EditorLineNum);
  mKey := TAtlasLineTail.KeyOf(AContext.FileName, AContext.LogicalLineNum, AContext.EditorLineNum, ARect.Top);
  X := TAtlasLineTail.Start(Self, mKey, mCell.Left);
  mColors := TAtlasColors.ForBackground(ABack);
  mTone := mColors.Warn;
  if FSet.ResultMissing then
  begin
    mTone := mColors.Error;
  end;
  EnsureFont(AContext.Canvas.Font);
  mDC := AContext.Canvas.Handle;
  mSaved := SaveDC(mDC);
  mBrush := CreateSolidBrush(COLORREF(ColorToRGB(TColor(TAtlasColorMath.Mix(mTone, ABack, cMarkStrength)))));
  try
    SelectObject(mDC, FFont.Handle);
    GetTextExtentPoint32W(mDC, PChar(mCaption), Length(mCaption), mSize);
    mTop := ARect.Top + Max(0, (ARect.Bottom - ARect.Top - mSize.cy) div 2);
    mMark := TRect.Create(X, ARect.Top + 1, X + mSize.cx + 2 * cMarkPadding, ARect.Bottom - 1);
    FillRect(mDC, mMark, mBrush);
    SetTextColor(mDC, COLORREF(ColorToRGB(TColor(mTone))));
    SetBkMode(mDC, TRANSPARENT);
    TextOutW(mDC, X + cMarkPadding, mTop, PChar(mCaption), Length(mCaption));
  finally
    DeleteObject(mBrush);
    RestoreDC(mDC, mSaved);
  end;
  TAtlasLineTail.Finish(Self, mKey, mMark.Right);
  TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.ExitPoints, AContext.FileName,
    FSet.RoutineLine, AText), mMark, AContext.EditView.TopRow, ARect.Height);
end;

procedure TAtlasIdeExitPoints.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mPoints: TArray<TAtlasExitPoint>;
  mLine: Integer;
  mBadge: Boolean;
  mBack: TAtlasColor;
begin
  if not FSet.Found or TAtlasGuard.Disabled(TAtlasFeature.ExitPoints) then
  begin
    Exit;
  end;
  try
    if not TAtlasPaintedLine.Resolve(Stage, BeforeEvent, Context, FFileName, FLines, mLine) or
      TAtlasIdeElements.FileHidden(TAtlasDrawnElement.ExitPoints, Context.FileName) then
    begin
      Exit;
    end;
    mPoints := FSet.PointsAt(mLine);
    mBadge := FBadge and FSet.HasBadge and (mLine = FSet.RoutineLine);
    if (Length(mPoints) = 0) and not mBadge then
    begin
      Exit;
    end;
    mBack := TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1);
    if Length(mPoints) > 0 then
    begin
      PaintPoints(Rect, Context, FLines[mLine], mPoints, mBack);
    end;
    if mBadge then
    begin
      PaintBadge(Rect, Context, FLines[mLine], mBack);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ExitPoints, E);
  end;
end;

end.
