unit Atlas.IDE.Editor.ExpressionType;

// Typ des markierten Ausdrucks (#689) im Editor. Den Typ rechnet der Server
// (atlas.server.expressionType), Antwort, Zeilen und das Erweitern regelt
// Atlas.Core.Editor.ExpressionType, den Tooltip zeichnet
// Atlas.UI.Editor.ExpressionType; hier bleiben Anfrage, Tasten, Hervorhebung
// und der Sprung.
// - Strg+Umschalt+T (keys.expressionType) schickt den Puffer und die
//   Markierung (ohne Markierung die Schreibmarke) an den Server und zeigt den
//   Tooltip unter der Schreibmarke. Der beschriebene Ausdruck ist im Editor
//   dezent hinterlegt (PaintLine, plsEndPaint).
// - Erneutes Drücken bei unveränderter Markierung erweitert auf den
//   umschließenden Ausdruck; ohne größeren Ausdruck bleibt der Tooltip.
// - Klick auf den Typ springt zu seiner Deklaration (TAtlasIdeNavigation).
// - Esc, jede andere Taste, ein Klick daneben, eine Änderung oder ein Wechsel
//   der Ansicht schließt den Tooltip.
// - hints.expressionType aus oder Atlas aus: kein Kürzel, kein Menüeintrag;
//   hints.expressionType.conversions bzw. .constValue gehen als Schalter an
//   den Server.
// Gesichert über TAtlasFeature.ExpressionType (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Graphics,
  Vcl.AppEvnts,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.ExpressionType,
  Atlas.UI.Editor.ExpressionType;

type
  TAtlasExpressionTypeSessionFunc = reference to function: TLspSession;

  TAtlasIdeExpressionType = class
  private const
    /// <summary>Die Namensauflösung kann Units nachladen: etwas länger als eine einfache Anfrage.</summary>
    cTimeoutMs = 10000;
    /// <summary>Deckkraft der Hervorhebung über dem Text (0–255).</summary>
    cMarkAlpha = 48;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeExpressionType;
  private
    FSession: TAtlasExpressionTypeSessionFunc;
    FMessage: TProc<string>;
    FMessages: TApplicationEvents;
    FTip: TAtlasExpressionTypeTip;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    // Gezeigter Ausdruck: Stand, Antwort, Zeilen für die Hervorhebung.
    FShown: TAtlasExpressionTypeShown;
    FInfo: TAtlasExpressionTypeInfo;
    FLines: TArray<string>;
    FTabWidth: Integer;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const AMsg: TMsg; var AHandled: Boolean);
    procedure Execute;
    function Ready(out AView: IOTAEditView; out ASession: TLspSession): Boolean;
    function Ask(ASession: TLspSession; const AFileName, AText, AArguments: string;
      out AInfo: TAtlasExpressionTypeInfo): Boolean;
    procedure Show(const AInfo: TAtlasExpressionTypeInfo);
    procedure Navigate;
    procedure Close;
    procedure Report(const AText: string);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class function KeyText: string; static;
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasExpressionTypeSessionFunc; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>ASession liefert die laufende Sitzung (nil ohne), AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Install(const ASession: TAtlasExpressionTypeSessionFunc; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>hints.expressionType an und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Steht der Tooltip?</summary>
    class function Active: Boolean; static;
    /// <summary>Typ des markierten Ausdrucks zeigen bzw. erweitern (Befehl Atlas.ExpressionType).</summary>
    class procedure Run; static;
    /// <summary>Tooltip schließen (Ansicht gewechselt).</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: Jede Änderung schließt den Tooltip.</summary>
    class procedure EditorModified; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Vcl.Controls,
  Vcl.Menus,
  Atlas.Text.Lines,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Client,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Editor.PaintedLine;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  mControl: TWinControl;
begin
  mControl := FindControl(AWnd);
  Result := (mControl <> nil) and mControl.ClassNameIs('TEditControl');
end;

function IsPascal(const AFileName: string): Boolean;
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AFileName));
  Result := (mExt = '.pas') or (mExt = '.dpr') or (mExt = '.dpk') or (mExt = '.inc');
end;

/// <summary>Schreibmarke in Bildschirmkoordinaten; ohne Schreibmarke eine Zeile an der Maus.</summary>
function CaretRect: TRect;
var
  mInfo: TGUIThreadInfo;
begin
  FillChar(mInfo, SizeOf(mInfo), 0);
  mInfo.cbSize := SizeOf(mInfo);
  if GetGUIThreadInfo(GetCurrentThreadId, mInfo) and (mInfo.hwndCaret <> 0) then
  begin
    Result := mInfo.rcCaret;
    MapWindowPoints(mInfo.hwndCaret, 0, Result, 2);
  end
  else
  begin
    Result := TRect.Create(Mouse.CursorPos, 1, 16);
  end;
end;

/// <summary>Gedrückte Taste mit Umschalt, Strg und Alt als TShortCut.</summary>
function PressedShortCut(AKey: Word): TShortCut;
var
  mShift: TShiftState;
begin
  mShift := [];
  if GetKeyState(VK_SHIFT) < 0 then
  begin
    Include(mShift, ssShift);
  end;
  if GetKeyState(VK_CONTROL) < 0 then
  begin
    Include(mShift, ssCtrl);
  end;
  if GetKeyState(VK_MENU) < 0 then
  begin
    Include(mShift, ssAlt);
  end;
  Result := ShortCut(AKey, mShift);
end;

{ TAtlasIdeExpressionType.TEvents }

function TAtlasIdeExpressionType.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeExpressionType.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeExpressionType }

constructor TAtlasIdeExpressionType.Create(const ASession: TAtlasExpressionTypeSessionFunc;
  const AMessage: TProc<string>);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FIndex := -1;
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeExpressionType.Destroy;
var
  mServices: INTACodeEditorServices;
  mPainted: Boolean;
begin
  FreeAndNil(FMessages);
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  mPainted := FShown.Active;
  FreeAndNil(FTip);
  FShown := Default(TAtlasExpressionTypeShown);
  FInfo := Default(TAtlasExpressionTypeInfo);
  FLines := nil;
  if mPainted then
  begin
    Invalidate;
  end;
  inherited;
end;

class procedure TAtlasIdeExpressionType.Install(const ASession: TAtlasExpressionTypeSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeExpressionType.Create(ASession, AMessage);
  end;
end;

class procedure TAtlasIdeExpressionType.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeExpressionType.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.ExpressionType;
end;

class function TAtlasIdeExpressionType.Active: Boolean;
begin
  Result := (FInstance <> nil) and (FInstance.FTip <> nil) and FInstance.FTip.IsShown;
end;

class procedure TAtlasIdeExpressionType.Run;
begin
  if (FInstance <> nil) and Enabled then
  begin
    FInstance.Execute;
  end;
end;

class procedure TAtlasIdeExpressionType.Dismiss;
begin
  if FInstance <> nil then
  begin
    FInstance.Close;
  end;
end;

class procedure TAtlasIdeExpressionType.EditorModified;
begin
  if FInstance <> nil then
  begin
    FInstance.Close;
  end;
end;

class procedure TAtlasIdeExpressionType.Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

class function TAtlasIdeExpressionType.KeyText: string;
begin
  Result := ShortCutToText(TShortCut(TAtlasIdeSettings.Current.ExpressionTypeKey));
end;

procedure TAtlasIdeExpressionType.Report(const AText: string);
begin
  if Assigned(FMessage) then
  begin
    FMessage(AText);
  end;
end;

procedure TAtlasIdeExpressionType.Close;
var
  mPainted: Boolean;
begin
  mPainted := FShown.Active;
  FShown.Active := False;
  if (FTip <> nil) and FTip.IsShown then
  begin
    FTip.Dismiss;
  end;
  if mPainted then
  begin
    Invalidate;
  end;
end;

function PositionIn(const ALines: TArray<string>; ARow, AColumn, ATabWidth: Integer): TLspTextPosition;
var
  mLineText: string;
begin
  mLineText := '';
  if (ARow >= 1) and (ARow <= Length(ALines)) then
  begin
    mLineText := ALines[ARow - 1];
  end;
  Result := TLspTextPosition.Create(ARow - 1, Min(TLspSession.ColumnToIndex(mLineText, AColumn, ATabWidth),
    Length(mLineText)));
end;

/// <summary>Markierung in AView, ohne sie die Schreibmarke, als Bereich in ALines.</summary>
function SelectionOf(const AView: IOTAEditView; const ALines: TArray<string>; ATabWidth: Integer): TLspRange;
var
  mBlock: IOTAEditBlock;
  mCursor: TOTAEditPos;
begin
  mCursor := AView.CursorPos;
  Result.StartPos := PositionIn(ALines, mCursor.Line, mCursor.Col, ATabWidth);
  Result.EndPos := Result.StartPos;
  mBlock := AView.Block;
  if (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0) then
  begin
    Result.StartPos := PositionIn(ALines, mBlock.StartingRow, mBlock.StartingColumn, ATabWidth);
    Result.EndPos := PositionIn(ALines, mBlock.EndingRow, mBlock.EndingColumn, ATabWidth);
  end;
end;

/// <summary>Argumente der Anfrage nach den Einstellungen.</summary>
function ArgumentsFor(const AFileName: string; const ARange: TLspRange; AExpand: Boolean): string;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasExpressionType.Arguments(TLspSession.PathToUri(AFileName), ARange, AExpand,
    mSettings.ExpressionTypeConversions, mSettings.ExpressionTypeConstValue);
end;

function TAtlasIdeExpressionType.Ready(out AView: IOTAEditView; out ASession: TLspSession): Boolean;
begin
  ASession := nil;
  AView := TAtlasEditorBuffer.ActiveView;
  Result := (AView <> nil) and (AView.Buffer <> nil) and IsPascal(AView.Buffer.FileName);
  if Result and Assigned(FSession) then
  begin
    ASession := FSession();
  end;
  if Result and (ASession = nil) then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Result := False;
  end;
end;

function TAtlasIdeExpressionType.Ask(ASession: TLspSession; const AFileName, AText, AArguments: string;
  out AInfo: TAtlasExpressionTypeInfo): Boolean;
var
  mAnswer: TJSONValue;
begin
  Result := False;
  try
    ASession.Sync(AFileName, AText);
    mAnswer := ASession.RunCommand(TAtlasExpressionType.Command, AArguments, cTimeoutMs);
    try
      TAtlasExpressionType.Read(mAnswer, AInfo);
    finally
      mAnswer.Free;
    end;
    Result := AInfo.Usable;
    if not Result then
    begin
      Report(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    end;
  except
    on E: ELspClientError do
    begin
      Report(TAtlasStrings.Fmt(TAtlasTextId.ExpressionTypeFailed, [E.Message]));
    end;
  end;
end;

procedure TAtlasIdeExpressionType.Execute;
var
  mView: IOTAEditView;
  mSession: TLspSession;
  mFileName, mText: string;
  mLines: TArray<string>;
  mTabWidth: Integer;
  mSelection, mRange: TLspRange;
  mExpand: Boolean;
  mInfo: TAtlasExpressionTypeInfo;
begin
  if not Ready(mView, mSession) then
  begin
    Close;
    Exit;
  end;
  mFileName := mView.Buffer.FileName;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mLines := TTextLines.SplitLines(mText);
  mTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  mSelection := SelectionOf(mView, mLines, mTabWidth);
  // Steht der Tooltip noch für diesen Stand, geht es eine Stufe hinaus.
  FShown.Active := FShown.Active and Active;
  TAtlasExpressionType.NextRequest(FShown, mFileName, mText, mSelection, mRange, mExpand);
  if not Ask(mSession, mFileName, mText, ArgumentsFor(mFileName, mRange, mExpand), mInfo) then
  begin
    Close;
    Exit;
  end;
  // Schon der äußerste Ausdruck: Tooltip und Hervorhebung bleiben.
  if TAtlasExpressionType.KeepShown(mExpand, mInfo) then
  begin
    Exit;
  end;
  FShown.FileName := mFileName;
  FShown.Text := mText;
  FShown.Selection := mSelection;
  FShown.Range := mInfo.Range;
  FLines := mLines;
  FTabWidth := mTabWidth;
  Show(mInfo);
end;

procedure TAtlasIdeExpressionType.Show(const AInfo: TAtlasExpressionTypeInfo);
var
  mCaret: TRect;
begin
  FInfo := AInfo;
  if FTip = nil then
  begin
    FTip := TAtlasExpressionTypeTip.Create(nil);
    FTip.OnNavigate :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.ExpressionType,
          procedure
          begin
            if FInstance <> nil then
            begin
              FInstance.Navigate;
            end;
          end);
      end;
  end;
  // Farben, Editorschrift und Zoom wie der Editor; unter der Zeile der Schreibmarke.
  mCaret := CaretRect;
  TAtlasIdeStyle.Apply(FTip, mCaret);
  FTip.ShowFor(TAtlasExpressionType.Rows(AInfo, TAtlasExpressionTypeTip.Texts(KeyText)),
    TPoint.Create(mCaret.Left, mCaret.Bottom));
  FShown.Active := True;
  Invalidate;
end;

procedure TAtlasIdeExpressionType.Navigate;
var
  mTarget: TAtlasExpressionTypeInfo;
begin
  mTarget := FInfo;
  Close;
  if mTarget.HasLocation then
  begin
    TAtlasIdeNavigation.GoToLocation(mTarget.FileName, mTarget.Line, mTarget.Character);
  end;
end;

procedure TAtlasIdeExpressionType.KeyDown(const AMsg: TMsg; var AHandled: Boolean);
var
  mKey: Word;
begin
  mKey := Word(AMsg.wParam);
  if (mKey = VK_SHIFT) or (mKey = VK_CONTROL) or (mKey = VK_MENU) then
  begin
    Exit;
  end;
  if (mKey = VK_ESCAPE) and (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_MENU) >= 0) then
  begin
    Close;
    AHandled := True;
    Exit;
  end;
  // Das eigene Kürzel erweitert (Run); jede andere Taste schließt und geht an den Editor.
  if PressedShortCut(mKey) = TShortCut(TAtlasIdeSettings.Current.ExpressionTypeKey) then
  begin
    Exit;
  end;
  Close;
end;

procedure TAtlasIdeExpressionType.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.ExpressionType) or (FTip = nil) or not FTip.IsShown then
  begin
    Exit;
  end;
  try
    case Msg.message of
      WM_KEYDOWN, WM_SYSKEYDOWN:
        if IsEditorWindow(Msg.hwnd) then
        begin
          KeyDown(Msg, Handled);
        end;
      WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_NCLBUTTONDOWN, WM_MOUSEWHEEL:
        if not FTip.HandleAllocated or (Msg.hwnd <> FTip.Handle) then
        begin
          Close;
        end;
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.ExpressionType, E);
    end;
  end;
end;

/// <summary>Hinterlegt ASpan in der Zeile AText von AContext.</summary>
procedure PaintSpan(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
  const ASpan: TAtlasExpressionTypeSpan; ATabWidth: Integer);
var
  mFirst, mLast, mCode, mArea: TRect;
  mColors: TAtlasColors;
  mDC: HDC;
  mSaved: Integer;
begin
  mColors := TAtlasColors.ForBackground(TAtlasIdeStyle.SampleBack(AContext.Canvas, ARect.Right - 2, ARect.Top + 1));
  mDC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, ASpan.Start, ATabWidth),
    AContext.EditorLineNum);
  mLast := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, ASpan.Stop, ATabWidth),
    AContext.EditorLineNum);
  mArea := TRect.Create(mFirst.Left, ARect.Top, Max(mLast.Left, mFirst.Left + 1), ARect.Bottom);
  mSaved := SaveDC(mDC);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    TAtlasIdeStyle.Blend(mDC, mArea, COLORREF(ColorToRGB(TColor(mColors.Accent))), TAtlasIdeExpressionType.cMarkAlpha);
  finally
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TAtlasIdeExpressionType.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mSpan: TAtlasExpressionTypeSpan;
  mLine: Integer;
begin
  if not FShown.Active or TAtlasGuard.Disabled(TAtlasFeature.ExpressionType) then
  begin
    Exit;
  end;
  try
    // Nur, wenn die Zeile im Editor dem gefragten Stand entspricht.
    if TAtlasPaintedLine.Resolve(Stage, BeforeEvent, Context, FShown.FileName, FLines, mLine) and
      TAtlasExpressionType.SpanOnLine(FShown.Range, mLine, Length(FLines[mLine]), mSpan) then
    begin
      PaintSpan(Rect, Context, FLines[mLine], mSpan, FTabWidth);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ExpressionType, E);
  end;
end;

end.
