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
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.Unwrap,
  Atlas.UI.Editor.Unwrap,
  Atlas.Core.Notifications.MessageSink,
  Atlas.IDE.Editor.CaretPopup;

type
  TAtlasUnwrapSessionFunc = reference to function: TLspSession;

  TAtlasIdeUnwrap = class
  private const
    /// <summary>„with auflösen“ fragt die Namensauflösung: etwas länger als eine einfache Anfrage.</summary>
    cTimeoutMs = 10000;
    /// <summary>Deckkraft der Vorschau über dem Text (0–255).</summary>
    cKeepAlpha = 56;
    cRemoveAlpha = 64;
  private class var
    FInstance: TAtlasIdeUnwrap;
  private
    FSession: TAtlasUnwrapSessionFunc;
    FMessage: TAtlasMessageSink;
    FHooks: TAtlasIdeCaretPopupHooks;
    FWindow: TAtlasUnwrapWindow;
    FWriting: Boolean;
    // Offene Liste: Datei, Text beim Fragen, Einträge und der gewählte (Vorschau).
    FFileName: string;
    FText: string;
    FLines: TArray<string>;
    FTabWidth: Integer;
    FEntries: TArray<TAtlasUnwrapEntry>;
    FPreview: Integer;
    procedure KeyDown(AKey: Word; var AHandled: Boolean);
    function ListKey(AKey: Word): Boolean;
    procedure Execute;
    function Ready(out AView: IOTAEditView; out ASession: TLspSession): Boolean;
    function Ask(ASession: TLspSession; const AView: IOTAEditView; out AEntries: TArray<TAtlasUnwrapEntry>): Boolean;
    procedure CreateWindow;
    procedure Preview(AIndex: Integer);
    procedure Accept(AIndex: Integer);
    procedure Close;
    procedure PaintLine(const ARect: TRect; const AStage: TPaintLineStage; ABeforeEvent: Boolean;
      const AContext: INTACodeEditorPaintContext);
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
  Winapi.Windows,
  Vcl.Graphics,
  Atlas.Text.Lines,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Strings,
  Atlas.UI.Popup.Window,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Editor.PaintedLine;

{ TAtlasIdeUnwrap }

constructor TAtlasIdeUnwrap.Create(const ASession: TAtlasUnwrapSessionFunc; const AMessage: TProc<string>);
begin
  inherited Create;
  FSession := ASession;
  FMessage := TAtlasMessageSink.Create(AMessage);
  FPreview := -1;
  FHooks := TAtlasIdeCaretPopupHooks.Create(TAtlasFeature.Unwrap, KeyDown, Close, PaintLine);
end;

destructor TAtlasIdeUnwrap.Destroy;
var
  mPainted: Boolean;
begin
  // Erst abmelden, dann freigeben (#493).
  FreeAndNil(FHooks);
  mPainted := FPreview >= 0;
  FreeAndNil(FWindow);
  FEntries := nil;
  FLines := nil;
  if mPainted then
  begin
    TAtlasIdeCaretPopupHooks.Invalidate;
  end;
  inherited;
end;

procedure TAtlasIdeUnwrap.KeyDown(AKey: Word; var AHandled: Boolean);
begin
  if ListKey(AKey) then
  begin
    AHandled := True;
  end
  else
  begin
    // Jede andere Taste schließt ohne Änderung und geht an den Editor.
    Close;
  end;
end;

/// <summary>Führt AKey in der Liste aus (Eingabe, Escape, Pfeile ohne Strg/Alt); False für jede andere Taste.
/// </summary>
function TAtlasIdeUnwrap.ListKey(AKey: Word): Boolean;
begin
  Result := (GetKeyState(VK_CONTROL) >= 0) and (GetKeyState(VK_MENU) >= 0);
  if not Result then
  begin
    Exit;
  end;
  case AKey of
    VK_RETURN:
      FWindow.Accept;
    VK_ESCAPE:
      FWindow.Cancel;
    VK_UP:
      FWindow.MoveRow(-1);
    VK_DOWN:
      FWindow.MoveRow(1);
  else
    Result := False;
  end;
end;

procedure TAtlasIdeUnwrap.Execute;
var
  mView: IOTAEditView;
  mSession: TLspSession;
  mEntries: TArray<TAtlasUnwrapEntry>;
  mPoint: TPoint;
begin
  Close;
  if not Ready(mView, mSession) or not Ask(mSession, mView, mEntries) then
  begin
    Exit;
  end;
  FEntries := mEntries;
  if FWindow = nil then
  begin
    CreateWindow;
  end;
  mPoint := TAtlasIdeCaretPopupHooks.CaretPoint;
  FWindow.Colors := TAtlasIdeStyle.Colors;
  FWindow.SetScaling(TAtlasPopupWindow.MonitorPPI(mPoint), 1, '', 10);
  FWindow.ShowFor(FEntries, mPoint);
end;

function TAtlasIdeUnwrap.Ready(out AView: IOTAEditView; out ASession: TLspSession): Boolean;
begin
  ASession := nil;
  AView := TAtlasEditorBuffer.ActiveView;
  Result := (AView <> nil) and (AView.Buffer <> nil) and not AView.Buffer.IsReadOnly and
    TAtlasUnwrap.Handles(AView.Buffer.FileName);
  if Result and Assigned(FSession) then
  begin
    ASession := FSession();
  end;
  if Result and (ASession = nil) then
  begin
    FMessage.Say(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Result := False;
  end;
end;

function TAtlasIdeUnwrap.Ask(ASession: TLspSession; const AView: IOTAEditView;
  out AEntries: TArray<TAtlasUnwrapEntry>): Boolean;
var
  mCursor: TOTAEditPos;
  mLine, mCharacter: Integer;
  mCaretLine, mArguments: string;
  mAnswer: TJSONValue;
begin
  Result := False;
  AEntries := nil;
  FFileName := AView.Buffer.FileName;
  FText := TAtlasEditorBuffer.Text(AView.Buffer);
  FLines := TTextLines.SplitLines(FText);
  FTabWidth := TAtlasEditorBuffer.TabWidth(AView.Buffer);
  mCursor := AView.CursorPos;
  mLine := mCursor.Line - 1;
  mCaretLine := '';
  if (mLine >= 0) and (mLine < Length(FLines)) then
  begin
    mCaretLine := FLines[mLine];
  end;
  mCharacter := Min(TLspSession.ColumnToIndex(mCaretLine, mCursor.Col, FTabWidth), Length(mCaretLine));
  mArguments := TAtlasUnwrap.Arguments(TLspSession.PathToUri(FFileName), mLine, mCharacter,
    TAtlasEditorBuffer.BlockIndent(AView.Buffer));
  try
    ASession.Sync(FFileName, FText);
    mAnswer := ASession.RunCommand(TAtlasUnwrap.cCommand, mArguments, cTimeoutMs);
    try
      AEntries := TAtlasUnwrap.ReadEntries(mAnswer);
    finally
      mAnswer.Free;
    end;
    Result := Length(AEntries) > 0;
    if not Result then
    begin
      FMessage.Say(TAtlasEditorStrings.Text(TAtlasEditorTextId.UnwrapNothing));
    end;
  except
    on E: ELspClientError do
    begin
      FMessage.Say(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnwrapFailed, [E.Message]));
    end;
  end;
end;

procedure TAtlasIdeUnwrap.CreateWindow;
begin
  FWindow := TAtlasUnwrapWindow.Create(nil);
  FHooks.Popup := FWindow;
  FWindow.OnSelect :=
    procedure(AIndex: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Unwrap,
        procedure
        begin
          if FInstance <> nil then
          begin
            FInstance.Preview(AIndex);
          end;
        end);
    end;
  FWindow.OnAccept :=
    procedure(AIndex: Integer)
    begin
      TAtlasGuard.Run(TAtlasFeature.Unwrap,
        procedure
        begin
          if FInstance <> nil then
          begin
            FInstance.Accept(AIndex);
          end;
        end);
    end;
  FWindow.OnCancel :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Unwrap,
        procedure
        begin
          if FInstance <> nil then
          begin
            FInstance.Close;
          end;
        end);
    end;
end;

procedure TAtlasIdeUnwrap.Preview(AIndex: Integer);
var
  mView: IOTAEditView;
  mFirst, mLast: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) then
  begin
    Exit;
  end;
  FPreview := AIndex;
  // Die Vorschau soll ganz zu sehen sein: oberste Zeile des Konstrukts in den sichtbaren Bereich.
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) and SameText(mView.Buffer.FileName, FFileName) and
    TAtlasUnwrap.LineSpan(FEntries[AIndex], mFirst, mLast) and (mFirst + 1 < mView.TopRow) then
  begin
    mView.SetTopLeft(mFirst + 1, mView.LeftColumn);
  end;
  TAtlasIdeCaretPopupHooks.Invalidate;
end;

procedure TAtlasIdeUnwrap.Accept(AIndex: Integer);
var
  mView: IOTAEditView;
  mEntry: TAtlasUnwrapEntry;
  mOutcome: TAtlasWorkspaceEditResult;
begin
  if (AIndex < 0) or (AIndex > High(FEntries)) or not FEntries[AIndex].Available then
  begin
    Close;
    Exit;
  end;
  mEntry := FEntries[AIndex];
  Close;
  mView := TAtlasEditorBuffer.ActiveView;
  // Nur auf den Stand, für den die Antwort gilt.
  if (mView = nil) or (mView.Buffer = nil) or not SameText(mView.Buffer.FileName, FFileName) or
    (TAtlasEditorBuffer.Text(mView.Buffer) <> FText) then
  begin
    FMessage.Say(TAtlasEditorStrings.Text(TAtlasEditorTextId.UnwrapChanged));
    Exit;
  end;
  FWriting := True;
  try
    mOutcome := TAtlasIdeWorkspaceEdit.Apply(TAtlasUnwrap.EditOf(mEntry, FFileName), TAtlasUnopenedPolicy.OpenInEditor,
      TAtlasStrings.Text(TAtlasTextId.UnwrapCommand));
  finally
    FWriting := False;
  end;
  if mOutcome.Error <> '' then
  begin
    FMessage.Say(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [mOutcome.Error]));
    Exit;
  end;
  FMessage.Say(TAtlasEditorStrings.Fmt(TAtlasEditorTextId.UnwrapDone, [TAtlasUnwrapWindow.EntryCaption(mEntry)]));
end;

procedure TAtlasIdeUnwrap.Close;
var
  mPainted: Boolean;
begin
  mPainted := FPreview >= 0;
  FPreview := -1;
  FEntries := nil;
  if (FWindow <> nil) and FWindow.IsShown then
  begin
    FWindow.Dismiss;
  end;
  if mPainted then
  begin
    TAtlasIdeCaretPopupHooks.Invalidate;
  end;
end;

class procedure TAtlasIdeUnwrap.Install(const ASession: TAtlasUnwrapSessionFunc; const AMessage: TProc<string>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeUnwrap.Create(ASession, AMessage);
  end;
end;

class procedure TAtlasIdeUnwrap.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeUnwrap.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.Unwrap;
end;

class function TAtlasIdeUnwrap.Active: Boolean;
begin
  Result := (FInstance <> nil) and (FInstance.FWindow <> nil) and FInstance.FWindow.IsShown;
end;

class procedure TAtlasIdeUnwrap.Run;
begin
  if (FInstance <> nil) and Enabled then
  begin
    FInstance.Execute;
  end;
end;

class procedure TAtlasIdeUnwrap.Dismiss;
begin
  if FInstance <> nil then
  begin
    FInstance.Close;
  end;
end;

class procedure TAtlasIdeUnwrap.EditorModified;
begin
  if (FInstance <> nil) and not FInstance.FWriting then
  begin
    FInstance.Close;
  end;
end;

/// <summary>Bereich von ASpan in der Zeile AText; False, wenn er leer ist.</summary>
function SpanArea(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
  const ASpan: TAtlasUnwrapSpan; ATabWidth: Integer; out AArea: TRect): Boolean;
var
  mStop: Integer;
  mFirst, mLast: TRect;
begin
  mStop := Min(ASpan.Stop, Length(AText));
  Result := mStop > ASpan.Start;
  if not Result then
  begin
    Exit;
  end;
  mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, ASpan.Start, ATabWidth),
    AContext.EditorLineNum);
  mLast := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, mStop, ATabWidth),
    AContext.EditorLineNum);
  AArea := TRect.Create(mFirst.Left, ARect.Top, Max(mLast.Left, mFirst.Left + 1), ARect.Bottom);
end;

/// <summary>Hinterlegt AArea grün (bleibt) oder rot und durchgestrichen (fällt weg).</summary>
procedure MarkSpan(ADC: HDC; const AArea: TRect; AKeep: Boolean; const AColors: TAtlasColors; APen: HPEN);
var
  mMiddle: Integer;
  mOldPen: HPEN;
begin
  if AKeep then
  begin
    TAtlasIdeStyle.Blend(ADC, AArea, COLORREF(ColorToRGB(TColor(AColors.Add))), TAtlasIdeUnwrap.cKeepAlpha);
    Exit;
  end;
  TAtlasIdeStyle.Blend(ADC, AArea, COLORREF(ColorToRGB(TColor(AColors.Error))), TAtlasIdeUnwrap.cRemoveAlpha);
  // Durchgestrichen: Linie auf halber Höhe.
  mMiddle := (AArea.Top + AArea.Bottom) div 2;
  mOldPen := SelectObject(ADC, APen);
  MoveToEx(ADC, AArea.Left, mMiddle, nil);
  LineTo(ADC, AArea.Right, mMiddle);
  SelectObject(ADC, mOldPen);
end;

/// <summary>Vorschau für die Teile ASpans der Zeile AText.</summary>
procedure PaintSpans(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const AText: string;
  const ASpans: TArray<TAtlasUnwrapSpan>; ATabWidth: Integer);
var
  mSpan: TAtlasUnwrapSpan;
  mCode, mArea: TRect;
  mColors: TAtlasColors;
  mDC: HDC;
  mPen: HPEN;
  mSaved: Integer;
begin
  mColors := TAtlasColors.ForBackground(TAtlasIdeStyle.SampleBack(AContext.Canvas, ARect.Right - 2, ARect.Top + 1));
  mDC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mSaved := SaveDC(mDC);
  mPen := CreatePen(PS_SOLID, Max(1, (ARect.Bottom - ARect.Top) div 14), COLORREF(ColorToRGB(TColor(mColors.Error))));
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mSpan in ASpans do
    begin
      if SpanArea(ARect, AContext, AText, mSpan, ATabWidth, mArea) then
      begin
        MarkSpan(mDC, mArea, mSpan.Keep, mColors, mPen);
      end;
    end;
  finally
    DeleteObject(mPen);
    RestoreDC(mDC, mSaved);
  end;
end;

procedure TAtlasIdeUnwrap.PaintLine(const ARect: TRect; const AStage: TPaintLineStage; ABeforeEvent: Boolean;
  const AContext: INTACodeEditorPaintContext);
var
  mSpans: TArray<TAtlasUnwrapSpan>;
  mLine: Integer;
begin
  // Nur, wenn die Zeile im Editor dem gefragten Stand entspricht.
  if (FPreview < 0) or (FPreview > High(FEntries)) or
    not TAtlasPaintedLine.Resolve(AStage, ABeforeEvent, AContext, FFileName, FLines, mLine) then
  begin
    Exit;
  end;
  mSpans := TAtlasUnwrap.SpansOnLine(FEntries[FPreview], mLine);
  if Length(mSpans) > 0 then
  begin
    PaintSpans(ARect, AContext, FLines[mLine], mSpans, FTabWidth);
  end;
end;

end.
