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
    TimeoutMs = 10000;
    /// <summary>Deckkraft der Hervorhebung über dem Text (0–255).</summary>
    MarkAlpha = 48;
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
    procedure KeyDown(const Msg: TMsg; var Handled: Boolean);
    procedure Execute;
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
  Atlas.IDE.Foundation.EditorRefresh;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  Control: TWinControl;
begin
  Control := FindControl(AWnd);
  Result := (Control <> nil) and Control.ClassNameIs('TEditControl');
end;

function IsPascal(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc');
end;

/// <summary>Schreibmarke in Bildschirmkoordinaten; ohne Schreibmarke eine Zeile an der Maus.</summary>
function CaretRect: TRect;
var
  Info: TGUIThreadInfo;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.cbSize := SizeOf(Info);
  if GetGUIThreadInfo(GetCurrentThreadId, Info) and (Info.hwndCaret <> 0) then
  begin
    Result := Info.rcCaret;
    MapWindowPoints(Info.hwndCaret, 0, Result, 2);
  end
  else
    Result := TRect.Create(Mouse.CursorPos, 1, 16);
end;

/// <summary>Gedrückte Taste mit Umschalt, Strg und Alt als TShortCut.</summary>
function PressedShortCut(AKey: Word): TShortCut;
var
  Shift: TShiftState;
begin
  Shift := [];
  if GetKeyState(VK_SHIFT) < 0 then
    Include(Shift, ssShift);
  if GetKeyState(VK_CONTROL) < 0 then
    Include(Shift, ssCtrl);
  if GetKeyState(VK_MENU) < 0 then
    Include(Shift, ssAlt);
  Result := ShortCut(AKey, Shift);
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
  Services: INTACodeEditorServices;
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
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasIdeExpressionType.Destroy;
var
  Services: INTACodeEditorServices;
  Painted: Boolean;
begin
  FreeAndNil(FMessages);
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  Painted := FShown.Active;
  FreeAndNil(FTip);
  FShown := Default(TAtlasExpressionTypeShown);
  FInfo := Default(TAtlasExpressionTypeInfo);
  FLines := nil;
  if Painted then
    Invalidate;
  inherited;
end;

class procedure TAtlasIdeExpressionType.Install(const ASession: TAtlasExpressionTypeSessionFunc;
  const AMessage: TProc<string>);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeExpressionType.Create(ASession, AMessage);
end;

class procedure TAtlasIdeExpressionType.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeExpressionType.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.ExpressionType;
end;

class function TAtlasIdeExpressionType.Active: Boolean;
begin
  Result := (FInstance <> nil) and (FInstance.FTip <> nil) and FInstance.FTip.IsShown;
end;

class procedure TAtlasIdeExpressionType.Run;
begin
  if (FInstance <> nil) and Enabled then
    FInstance.Execute;
end;

class procedure TAtlasIdeExpressionType.Dismiss;
begin
  if FInstance <> nil then
    FInstance.Close;
end;

class procedure TAtlasIdeExpressionType.EditorModified;
begin
  if FInstance <> nil then
    FInstance.Close;
end;

class procedure TAtlasIdeExpressionType.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
end;

class function TAtlasIdeExpressionType.KeyText: string;
begin
  Result := ShortCutToText(TShortCut(TAtlasIdeSettings.Current.ExpressionTypeKey));
end;

procedure TAtlasIdeExpressionType.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

procedure TAtlasIdeExpressionType.Close;
var
  Painted: Boolean;
begin
  Painted := FShown.Active;
  FShown.Active := False;
  if (FTip <> nil) and FTip.IsShown then
    FTip.Dismiss;
  if Painted then
    Invalidate;
end;

procedure TAtlasIdeExpressionType.Execute;
var
  View: IOTAEditView;
  Session: TLspSession;
  Settings: TAtlasPluginSettings;
  FileName, Text, Arguments: string;
  Lines: TArray<string>;
  TabWidth: Integer;
  Selection, Range: TLspRange;
  Expand: Boolean;
  Block: IOTAEditBlock;
  Cursor: TOTAEditPos;
  Answer: TJSONValue;
  Info: TAtlasExpressionTypeInfo;

  function Position(ARow, AColumn: Integer): TLspTextPosition;
  var
    LineText: string;
  begin
    LineText := '';
    if (ARow >= 1) and (ARow <= Length(Lines)) then
      LineText := Lines[ARow - 1];
    Result := TLspTextPosition.Create(ARow - 1, Min(TLspSession.ColumnToIndex(LineText, AColumn, TabWidth),
      Length(LineText)));
  end;

begin
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or not IsPascal(View.Buffer.FileName) then
  begin
    Close;
    Exit;
  end;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if Session = nil then
  begin
    Close;
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  FileName := View.Buffer.FileName;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  Lines := TTextLines.SplitLines(Text);
  TabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  Cursor := View.CursorPos;
  Selection.StartPos := Position(Cursor.Line, Cursor.Col);
  Selection.EndPos := Selection.StartPos;
  Block := View.Block;
  if (Block <> nil) and Block.IsValid and (Block.Size > 0) then
  begin
    Selection.StartPos := Position(Block.StartingRow, Block.StartingColumn);
    Selection.EndPos := Position(Block.EndingRow, Block.EndingColumn);
  end;
  // Steht der Tooltip noch für diesen Stand, geht es eine Stufe hinaus.
  FShown.Active := FShown.Active and Active;
  TAtlasExpressionType.NextRequest(FShown, FileName, Text, Selection, Range, Expand);
  Settings := TAtlasIdeSettings.Current;
  Arguments := TAtlasExpressionType.Arguments(TLspSession.PathToUri(FileName), Range, Expand,
    Settings.ExpressionTypeConversions, Settings.ExpressionTypeConstValue);
  try
    Session.Sync(FileName, Text);
    Answer := Session.RunCommand(TAtlasExpressionType.Command, Arguments, TimeoutMs);
    try
      TAtlasExpressionType.Read(Answer, Info);
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Close;
      Report(TAtlasStrings.Fmt(TAtlasTextId.ExpressionTypeFailed, [E.Message]));
      Exit;
    end;
  end;
  if not Info.Usable then
  begin
    Close;
    Report(TAtlasStrings.Text(TAtlasTextId.ResultsNothing));
    Exit;
  end;
  // Schon der äußerste Ausdruck: Tooltip und Hervorhebung bleiben.
  if TAtlasExpressionType.KeepShown(Expand, Info) then
    Exit;
  FShown.FileName := FileName;
  FShown.Text := Text;
  FShown.Selection := Selection;
  FShown.Range := Info.Range;
  FLines := Lines;
  FTabWidth := TabWidth;
  Show(Info);
end;

procedure TAtlasIdeExpressionType.Show(const AInfo: TAtlasExpressionTypeInfo);
var
  Caret: TRect;
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
              FInstance.Navigate;
          end);
      end;
  end;
  // Farben, Editorschrift und Zoom wie der Editor; unter der Zeile der Schreibmarke.
  Caret := CaretRect;
  TAtlasIdeStyle.Apply(FTip, Caret);
  FTip.ShowFor(TAtlasExpressionType.Rows(AInfo, TAtlasExpressionTypeTip.Texts(KeyText)),
    TPoint.Create(Caret.Left, Caret.Bottom));
  FShown.Active := True;
  Invalidate;
end;

procedure TAtlasIdeExpressionType.Navigate;
var
  Target: TAtlasExpressionTypeInfo;
begin
  Target := FInfo;
  Close;
  if Target.HasLocation then
    TAtlasIdeNavigation.GoToLocation(Target.FileName, Target.Line, Target.Character);
end;

procedure TAtlasIdeExpressionType.KeyDown(const Msg: TMsg; var Handled: Boolean);
var
  Key: Word;
begin
  Key := Word(Msg.wParam);
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
    Exit;
  if (Key = VK_ESCAPE) and (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_MENU) >= 0) then
  begin
    Close;
    Handled := True;
    Exit;
  end;
  // Das eigene Kürzel erweitert (Run); jede andere Taste schließt und geht an den Editor.
  if PressedShortCut(Key) = TShortCut(TAtlasIdeSettings.Current.ExpressionTypeKey) then
    Exit;
  Close;
end;

procedure TAtlasIdeExpressionType.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.ExpressionType) or (FTip = nil) or not FTip.IsShown then
    Exit;
  try
    case Msg.message of
      WM_KEYDOWN, WM_SYSKEYDOWN:
        if IsEditorWindow(Msg.hwnd) then
          KeyDown(Msg, Handled);
      WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_NCLBUTTONDOWN, WM_MOUSEWHEEL:
        if not FTip.HandleAllocated or (Msg.hwnd <> FTip.Handle) then
          Close;
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

procedure TAtlasIdeExpressionType.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Span: TAtlasExpressionTypeSpan;
  Text: string;
  Line: Integer;
  First, Last, Code, Area: TRect;
  Colors: TAtlasColors;
  DC: HDC;
  Saved: Integer;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FShown.Active or
    TAtlasGuard.Disabled(TAtlasFeature.ExpressionType) then
    Exit;
  try
    if not SameText(Context.FileName, FShown.FileName) then
      Exit;
    LineState := Context.LineState;
    if LineState = nil then
      Exit;
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line >= Length(FLines)) then
      Exit;
    Text := FLines[Line];
    if not TAtlasExpressionType.SpanOnLine(FShown.Range, Line, Length(Text), Span) then
      Exit;
    // Nur, wenn die Zeile im Editor dem gefragten Stand entspricht.
    if TrimRight(LineState.Text) <> TrimRight(Text) then
      Exit;
    Colors := TAtlasColors.ForBackground(TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1));
    DC := Context.Canvas.Handle;
    Code := LineState.CodeRect;
    First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Span.Start, FTabWidth),
      Context.EditorLineNum);
    Last := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Span.Stop, FTabWidth),
      Context.EditorLineNum);
    Area := TRect.Create(First.Left, Rect.Top, Max(Last.Left, First.Left + 1), Rect.Bottom);
    Saved := SaveDC(DC);
    try
      if Code.Right > Code.Left then
        IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
      TAtlasIdeStyle.Blend(DC, Area, COLORREF(ColorToRGB(TColor(Colors.Accent))), MarkAlpha);
    finally
      RestoreDC(DC, Saved);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.ExpressionType, E);
  end;
end;

end.
