unit Atlas.IDE.Editor.Unwrap;

// Umschließung entfernen (#657) im Editor. Die Konstrukte und ihre Edits
// rechnet der Server (atlas.server.unwrap), die Antwort liest
// Atlas.Core.Editor.Unwrap, die Liste zeichnet Atlas.UI.Editor.Unwrap; hier
// bleiben Anfrage, Tasten, Vorschau und das Übernehmen.
// - Strg+Umschalt+Entf (keys.unwrap.key) schickt den Puffer und die Stelle
//   der Schreibmarke an den Server und zeigt die Liste an der Schreibmarke.
//   Bei nur einem Konstrukt entfällt die Liste, die Vorschau steht gleich da.
// - Vorschau: PaintLine (plsEndPaint) hinterlegt, was bleibt, grün und das,
//   was entfällt, rot und durchgestrichen, für den gewählten Eintrag. ↑/↓
//   und die Maus wechseln den Eintrag.
// - Enter (oder Klick) übernimmt: ein Rückgängig-Schritt (#397), nur auf den
//   Stand, für den die Antwort gilt. Esc, jede andere Taste, ein Klick daneben,
//   eine Änderung oder ein Wechsel der Ansicht schließt ohne Änderung.
// - keys.unwrap aus oder Atlas aus: kein Kürzel, kein Menüeintrag.
// Gesichert über TAtlasFeature.Unwrap (#493). Nur im Hauptthread.

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
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.Unwrap,
  Atlas.UI.Editor.Unwrap;

type
  TAtlasUnwrapSessionFunc = reference to function: TLspSession;

  TAtlasIdeUnwrap = class
  private const
    /// <summary>„with auflösen“ fragt die Namensauflösung: etwas länger als eine einfache Anfrage.</summary>
    TimeoutMs = 10000;
    /// <summary>Deckkraft der Vorschau über dem Text (0–255).</summary>
    KeepAlpha = 56;
    RemoveAlpha = 64;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private class var
    FInstance: TAtlasIdeUnwrap;
  private
    FSession: TAtlasUnwrapSessionFunc;
    FMessage: TProc<string>;
    FMessages: TApplicationEvents;
    FWindow: TAtlasUnwrapWindow;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FWriting: Boolean;
    // Offene Liste: Datei, Text beim Fragen, Einträge und der gewählte (Vorschau).
    FFileName: string;
    FText: string;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FEntries: TArray<TAtlasUnwrapEntry>;
    FPreview: Integer;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const Msg: TMsg; var Handled: Boolean);
    procedure Execute;
    procedure Preview(AIndex: Integer);
    procedure Accept(AIndex: Integer);
    procedure Close;
    procedure Report(const AText: string);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
  public
    constructor Create(const ASession: TAtlasUnwrapSessionFunc; const AMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>ASession liefert die laufende Sitzung (nil ohne), AMessage schreibt eine Zeile in die
    /// Meldungsansicht.</summary>
    class procedure Install(const ASession: TAtlasUnwrapSessionFunc; const AMessage: TProc<string>); static;
    class procedure Uninstall; static;
    /// <summary>keys.unwrap an und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Ist die Liste offen?</summary>
    class function Active: Boolean; static;
    /// <summary>Konstrukte an der Schreibmarke holen und die Liste zeigen (Befehl Atlas.Unwrap).</summary>
    class procedure Run; static;
    /// <summary>Liste schließen ohne Änderung (Ansicht gewechselt).</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: Jede fremde Änderung schließt die Liste.</summary>
    class procedure EditorModified; static;
  end;

implementation

uses
  System.Math,
  System.JSON,
  Vcl.Controls,
  Atlas.Text.Lines,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.UI.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit;

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

/// <summary>Bildschirmstelle unter der Zeile mit der Schreibmarke.</summary>
function CaretPoint: TPoint;
var
  Focus: HWND;
begin
  Result := Mouse.CursorPos;
  Focus := GetFocus;
  if (Focus <> 0) and GetCaretPos(Result) then
  begin
    Inc(Result.Y, 16);
    Winapi.Windows.ClientToScreen(Focus, Result);
  end;
end;

{ TAtlasIdeUnwrap.TEvents }

function TAtlasIdeUnwrap.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeUnwrap.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeUnwrap }

constructor TAtlasIdeUnwrap.Create(const ASession: TAtlasUnwrapSessionFunc; const AMessage: TProc<string>);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FIndex := -1;
  FPreview := -1;
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasIdeUnwrap.Destroy;
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
  Painted := FPreview >= 0;
  FreeAndNil(FWindow);
  FEntries := nil;
  FLines := nil;
  if Painted then
    Invalidate;
  inherited;
end;

class procedure TAtlasIdeUnwrap.Install(const ASession: TAtlasUnwrapSessionFunc; const AMessage: TProc<string>);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeUnwrap.Create(ASession, AMessage);
end;

class procedure TAtlasIdeUnwrap.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeUnwrap.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.Unwrap;
end;

class function TAtlasIdeUnwrap.Active: Boolean;
begin
  Result := (FInstance <> nil) and (FInstance.FWindow <> nil) and FInstance.FWindow.IsShown;
end;

class procedure TAtlasIdeUnwrap.Run;
begin
  if (FInstance <> nil) and Enabled then
    FInstance.Execute;
end;

class procedure TAtlasIdeUnwrap.Dismiss;
begin
  if FInstance <> nil then
    FInstance.Close;
end;

class procedure TAtlasIdeUnwrap.EditorModified;
begin
  if (FInstance <> nil) and not FInstance.FWriting then
    FInstance.Close;
end;

class procedure TAtlasIdeUnwrap.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

procedure TAtlasIdeUnwrap.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

procedure TAtlasIdeUnwrap.Close;
var
  Painted: Boolean;
begin
  Painted := FPreview >= 0;
  FPreview := -1;
  FEntries := nil;
  if (FWindow <> nil) and FWindow.IsShown then
    FWindow.Dismiss;
  if Painted then
    Invalidate;
end;

procedure TAtlasIdeUnwrap.Execute;
var
  View: IOTAEditView;
  Session: TLspSession;
  Cursor: TOTAEditPos;
  Line, Character: Integer;
  CaretLine, Arguments: string;
  Answer: TJSONValue;
  Entries: TArray<TAtlasUnwrapEntry>;
  Point: TPoint;
begin
  Close;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or View.Buffer.IsReadOnly or not IsPascal(View.Buffer.FileName) then
    Exit;
  Session := nil;
  if Assigned(FSession) then
    Session := FSession();
  if Session = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  FFileName := View.Buffer.FileName;
  FText := TAtlasEditorBuffer.Text(View.Buffer);
  FLines := TTextLines.SplitLines(FText);
  FTabWidth := TAtlasEditorBuffer.TabWidth(View.Buffer);
  Cursor := View.CursorPos;
  Line := Cursor.Line - 1;
  CaretLine := '';
  if (Line >= 0) and (Line < Length(FLines)) then
    CaretLine := FLines[Line];
  Character := Min(TLspSession.ColumnToIndex(CaretLine, Cursor.Col, FTabWidth), Length(CaretLine));
  Arguments := TAtlasUnwrap.Arguments(TLspSession.PathToUri(FFileName), Line, Character,
    TAtlasEditorBuffer.BlockIndent(View.Buffer));
  try
    Session.Sync(FFileName, FText);
    Answer := Session.RunCommand(TAtlasUnwrap.Command, Arguments, TimeoutMs);
    try
      Entries := TAtlasUnwrap.ReadEntries(Answer);
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Report(TAtlasStrings.Fmt(TAtlasTextId.UnwrapFailed, [E.Message]));
      Exit;
    end;
  end;
  if Length(Entries) = 0 then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.UnwrapNothing));
    Exit;
  end;
  FEntries := Entries;
  if FWindow = nil then
  begin
    FWindow := TAtlasUnwrapWindow.Create(nil);
    FWindow.OnSelect :=
      procedure(AIndex: Integer)
      begin
        TAtlasGuard.Run(TAtlasFeature.Unwrap,
          procedure
          begin
            if FInstance <> nil then
              FInstance.Preview(AIndex);
          end);
      end;
    FWindow.OnAccept :=
      procedure(AIndex: Integer)
      begin
        TAtlasGuard.Run(TAtlasFeature.Unwrap,
          procedure
          begin
            if FInstance <> nil then
              FInstance.Accept(AIndex);
          end);
      end;
    FWindow.OnCancel :=
      procedure
      begin
        TAtlasGuard.Run(TAtlasFeature.Unwrap,
          procedure
          begin
            if FInstance <> nil then
              FInstance.Close;
          end);
      end;
  end;
  Point := CaretPoint;
  FWindow.Colors := TAtlasIdeStyle.Colors;
  FWindow.SetScaling(TAtlasPopupWindow.MonitorPPI(Point), 1, '', 10);
  FWindow.ShowFor(FEntries, Point);
end;

procedure TAtlasIdeUnwrap.Preview(AIndex: Integer);
var
  View: IOTAEditView;
  First, Last: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then
    Exit;
  FPreview := AIndex;
  // Die Vorschau soll ganz zu sehen sein: oberste Zeile des Konstrukts in den sichtbaren Bereich.
  View := TAtlasEditorBuffer.ActiveView;
  if (View <> nil) and (View.Buffer <> nil) and SameText(View.Buffer.FileName, FFileName) and
    TAtlasUnwrap.LineSpan(FEntries[AIndex], First, Last) and (First + 1 < View.TopRow) then
    View.SetTopLeft(First + 1, View.LeftColumn);
  Invalidate;
end;

procedure TAtlasIdeUnwrap.Accept(AIndex: Integer);
var
  View: IOTAEditView;
  Entry: TAtlasUnwrapEntry;
  Outcome: TAtlasWorkspaceEditResult;
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) or not FEntries[AIndex].Available then
  begin
    Close;
    Exit;
  end;
  Entry := FEntries[AIndex];
  Close;
  View := TAtlasEditorBuffer.ActiveView;
  // Nur auf den Stand, für den die Antwort gilt.
  if (View = nil) or (View.Buffer = nil) or not SameText(View.Buffer.FileName, FFileName) or
    (TAtlasEditorBuffer.Text(View.Buffer) <> FText) then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.UnwrapChanged));
    Exit;
  end;
  FWriting := True;
  try
    Outcome := TAtlasIdeWorkspaceEdit.Apply(TAtlasUnwrap.EditOf(Entry, FFileName), TAtlasUnopenedPolicy.OpenInEditor,
      TAtlasStrings.Text(TAtlasTextId.UnwrapCommand));
  finally
    FWriting := False;
  end;
  if Outcome.Error <> '' then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  Report(TAtlasStrings.Fmt(TAtlasTextId.UnwrapDone, [TAtlasUnwrapWindow.EntryCaption(Entry)]));
end;

procedure TAtlasIdeUnwrap.KeyDown(const Msg: TMsg; var Handled: Boolean);
var
  Key: Word;
begin
  if (FWindow = nil) or not FWindow.IsShown then
    Exit;
  Key := Word(Msg.wParam);
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) then
    Exit;
  if (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_MENU) >= 0) then
    case Key of
      VK_RETURN:
        begin
          FWindow.Accept;
          Handled := True;
          Exit;
        end;
      VK_ESCAPE:
        begin
          FWindow.Cancel;
          Handled := True;
          Exit;
        end;
      VK_UP:
        begin
          FWindow.MoveRow(-1);
          Handled := True;
          Exit;
        end;
      VK_DOWN:
        begin
          FWindow.MoveRow(1);
          Handled := True;
          Exit;
        end;
    end;
  // Jede andere Taste schließt ohne Änderung und geht an den Editor.
  Close;
end;

procedure TAtlasIdeUnwrap.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.Unwrap) or (FWindow = nil) or not FWindow.IsShown then
    Exit;
  try
    case Msg.message of
      WM_KEYDOWN, WM_SYSKEYDOWN:
        if IsEditorWindow(Msg.hwnd) then
          KeyDown(Msg, Handled);
      WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN, WM_NCLBUTTONDOWN:
        if not FWindow.HandleAllocated or (Msg.hwnd <> FWindow.Handle) then
          Close;
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.Unwrap, E);
    end;
  end;
end;

procedure TAtlasIdeUnwrap.PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
  var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Spans: TArray<TAtlasUnwrapSpan>;
  Span: TAtlasUnwrapSpan;
  Text: string;
  Line, Stop, Middle, Saved: Integer;
  First, Last, Code, Area: TRect;
  Colors: TAtlasColors;
  DC: HDC;
  Pen, OldPen: HPEN;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or (FPreview < 0) or (FPreview > High(FEntries)) or
    TAtlasGuard.Disabled(TAtlasFeature.Unwrap) then
    Exit;
  try
    if not SameText(Context.FileName, FFileName) then
      Exit;
    LineState := Context.LineState;
    if LineState = nil then
      Exit;
    Line := Context.LogicalLineNum - 1;
    if (Line < 0) or (Line >= Length(FLines)) then
      Exit;
    Spans := TAtlasUnwrap.SpansOnLine(FEntries[FPreview], Line);
    if Length(Spans) = 0 then
      Exit;
    Text := FLines[Line];
    // Nur, wenn die Zeile im Editor dem gefragten Stand entspricht.
    if TrimRight(LineState.Text) <> TrimRight(Text) then
      Exit;
    Colors := TAtlasColors.ForBackground(TAtlasIdeStyle.SampleBack(Context.Canvas, Rect.Right - 2, Rect.Top + 1));
    DC := Context.Canvas.Handle;
    Code := LineState.CodeRect;
    Saved := SaveDC(DC);
    Pen := CreatePen(PS_SOLID, Max(1, (Rect.Bottom - Rect.Top) div 14),
      COLORREF(ColorToRGB(TColor(Colors.Error))));
    try
      if Code.Right > Code.Left then
        IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
      for Span in Spans do
      begin
        Stop := Min(Span.Stop, Length(Text));
        if Stop <= Span.Start then
          Continue;
        First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Span.Start, FTabWidth),
          Context.EditorLineNum);
        Last := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Stop, FTabWidth),
          Context.EditorLineNum);
        Area := TRect.Create(First.Left, Rect.Top, Max(Last.Left, First.Left + 1), Rect.Bottom);
        if Span.Keep then
          TAtlasIdeStyle.Blend(DC, Area, COLORREF(ColorToRGB(TColor(Colors.Add))), KeepAlpha)
        else
        begin
          TAtlasIdeStyle.Blend(DC, Area, COLORREF(ColorToRGB(TColor(Colors.Error))), RemoveAlpha);
          // Durchgestrichen: Linie auf halber Höhe.
          Middle := (Area.Top + Area.Bottom) div 2;
          OldPen := SelectObject(DC, Pen);
          MoveToEx(DC, Area.Left, Middle, nil);
          LineTo(DC, Area.Right, Middle);
          SelectObject(DC, OldPen);
        end;
      end;
    finally
      DeleteObject(Pen);
      RestoreDC(DC, Saved);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Unwrap, E);
  end;
end;

end.
