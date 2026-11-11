unit Atlas.IDE.Editor.LinkedEditing;

// Bezeichner live mitziehen (#658, experimentell) im Editor. Was eine Taste
// aus dem Namen macht und wie er in alle Vorkommen kommt, rechnet
// Atlas.Core.Editor.LinkedEditing; hier bleiben Anfrage, Tasten, Puffer und
// Zeichnen.
// - Ruht der Cursor auf einem Bezeichner, fragt Atlas im Hintergrund den
//   Server nach den Vorkommen (linkedEditingRange mit "atlasLocals"). Nur
//   lokale Variablen, Parameter, lokale Konstanten, Inline- und
//   Schleifenvariablen bekommen eine Antwort.
// - Tippt man dann ein Zeichen eines Bezeichners, Rücktaste oder Entf im
//   Namen und gilt die Antwort noch für den Text, beginnt die Sitzung:
//   Application.OnMessage fängt die Taste ab, Atlas schreibt den neuen Namen
//   in alle Vorkommen (ein Schreiber, nur die Namen, damit Haltepunkte und
//   Lesezeichen bleiben). Folgt die nächste Taste, nimmt Atlas den eigenen
//   Schritt zurück und schreibt die ganze Umbenennung neu: Strg+Z nimmt die
//   Sitzung auf einmal zurück (wie Zeilen verschieben, #634).
// - Ändert die IDE den Namen selbst (Einfügen, Vorschlag übernommen), zieht
//   Atlas die übrigen Vorkommen nach; das ist ein eigener Rückgängig-Schritt.
// - Ende: Enter (ohne Zeilenumbruch), Esc, ein Zeichen, das kein Bezeichner
//   ist, Rücktaste am Anfang bzw. Entf am Ende des Namens, Cursor verlässt den
//   Namen, Datei- oder Formularwechsel, Einstellung aus.
// - Konflikt (reserviertes Wort, Name in der Routine schon sichtbar): Rahmen
//   und Marke rot, Hinweis an der Marke und im Statusfeld; Esc stellt den
//   alten Namen wieder her.
// - Zeichnen per PaintLine (plsEndPaint): das bearbeitete Vorkommen
//   durchgezogen, die übrigen gestrichelt, dahinter „4 Vorkommen“.
// - Nie bei offener Vervollständigung, im Platzhalter-Modus oder mit
//   mehreren Einfügemarken (#589).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Editor.LinkedEditing,
  Atlas.IDE.Editor.LinkedEditingQuery;

type
  /// <summary>Statusfeld setzen; AText '' entfernt es.</summary>
  TAtlasLinkedStatusProc = reference to procedure(const AText, AHint: string);

  TAtlasIdeLinkedEditing = class
  private const
    cTickMs = 100;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    /// <summary>Laufende Sitzung: Ansicht, bekannter Text, Vorkommen ([Primary] wird bearbeitet), Stand zu
    /// Beginn.</summary>
    TRun = record
      View: IOTAEditView;
      Text: string;
      Lines: TArray<string>;
      Ranges: TAtlasLinkedRanges;
      Primary: Integer;
      Conflicts: TAtlasLinkedConflicts;
      Original: string;
      OriginalText: string;
      OriginalRanges: TAtlasLinkedRanges;
      // Der eigene Schritt oben in der Rückgängig-Liste enthält die ganze Sitzung.
      Grouped: Boolean;
      Problem: TAtlasLinkedProblem;
      Detail: string;
      function Active: Boolean;
      /// <summary>Datei der Sitzung; '' ohne.</summary>
      function FileName: string;
      function PrimaryRange: TAtlasLinkedRange;
      function PrimaryName: string;
      /// <summary>Hinweis zum Konflikt; '' ohne.</summary>
      function ProblemText: string;
      /// <summary>Marke und Statusfeld: Konflikt oder Anzahl der Vorkommen.</summary>
      function Caption: string;
      procedure SetState(const AText: string; const ARanges: TAtlasLinkedRanges);
      procedure UpdateProblem;
      /// <summary>Neuer Name und Cursorversatz für die Taste AKind am Cursor von AView; False außerhalb des Namens
      /// oder wenn die Taste die Sitzung beendet.</summary>
      function NextName(const AView: IOTAEditView; AKind: TAtlasLinkedKey; const AInsert: string;
        out ANewName: string; out ANewOffset: Integer): Boolean;
      /// <summary>Eigenen Schritt zurücknehmen: ABase/ABaseRanges werden der Stand zu Beginn; sonst den letzten
      /// Stand wiederherstellen. False, wenn das nicht gelingt.</summary>
      function Rewind(var ABase: string; var ABaseRanges: TAtlasLinkedRanges): Boolean;
    end;
  private class var
    FInstance: TAtlasIdeLinkedEditing;
  private
    FBusy: TFunc<Boolean>;
    FStatus: TAtlasLinkedStatusProc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FMessages: TApplicationEvents;
    FTimer: TTimer;
    FQuery: TAtlasIdeLinkedEditingQuery;
    FRun: TRun;
    FWriting: Boolean;
    FHighSurrogate: Char;
    function IsBusy: Boolean;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const AMsg: TMsg; var AHandled: Boolean);
    procedure CharTyped(const AMsg: TMsg; var AHandled: Boolean);
    /// <summary>Hälfte eines Zeichens außerhalb der Grundebene behandeln; True, wenn ATyped eine war.</summary>
    function Surrogate(ATyped: Char; var AHandled: Boolean): Boolean;
    procedure TimerTick(Sender: TObject);
    /// <summary>Takt mit Sitzung: beenden, wenn sie nicht mehr gilt; ausstehende Änderung nachziehen.</summary>
    procedure CheckRun;
    /// <summary>Datei gewechselt, Formular angezeigt oder abgeschaltet?</summary>
    function Lost(const AView: IOTAEditView): Boolean;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Sitzung mit der letzten Antwort beginnen; False, wenn sie nicht mehr gilt.</summary>
    function Start(const AView: IOTAEditView): Boolean;
    /// <summary>Taste im Namen ausführen; False gibt sie an die IDE (und beendet die Sitzung).</summary>
    function Edit(AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
    /// <summary>Sitzung für die aktive Ansicht AView bereit (begonnen, ohne Markierung, Text nachgezogen)?</summary>
    function Prepare(out AView: IOTAEditView): Boolean;
    /// <summary>ANewName ab ABase in alle Vorkommen schreiben und den Cursor setzen.</summary>
    function Apply(const AView: IOTAEditView; const ABase: string; const ABaseRanges: TAtlasLinkedRanges;
      const ANewName: string; ANewOffset: Integer): Boolean;
    /// <summary>Fremde Änderung: nur am bearbeiteten Namen, dann die übrigen nachziehen; sonst False.</summary>
    function Follow(const AText: string): Boolean;
    /// <summary>Esc bei Konflikt: alten Namen wiederherstellen.</summary>
    procedure Restore;
    procedure Reconcile;
    /// <summary>AName in die Bereiche ARanges von ABase schreiben (ein Schreiber), ASkip ausgenommen.</summary>
    procedure WriteNames(const ABuffer: IOTAEditBuffer; const ABase: string; const ARanges: TAtlasLinkedRanges;
      const AName: string; ASkip: Integer);
    procedure Refresh;
    procedure Finish;
  public
    constructor Create(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
      const AStatus: TAtlasLinkedStatusProc);
    destructor Destroy; override;
    /// <summary>ABusy: Vervollständigung offen, Platzhalter-Modus oder mehrere Einfügemarken? ASession liefert
    /// die laufende Sitzung des Servers (nil ohne), AStatus setzt das Statusfeld.</summary>
    class procedure Install(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
      const AStatus: TAtlasLinkedStatusProc); static;
    class procedure Uninstall; static;
    /// <summary>editor.linkedEditing an (experimentell, also nur mit experimental.enabled) und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Läuft eine Sitzung?</summary>
    class function Active: Boolean; static;
    /// <summary>Sitzung beenden (Ansicht gewechselt).</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: fremde Änderung nachziehen (in der Warteschlange).</summary>
    class procedure EditorModified(const AView: IOTAEditView); static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Editor.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorRefresh,
  Atlas.IDE.Editor.PaintedLine;

function CurrentShift: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_SHIFT) < 0 then
  begin
    Include(Result, ssShift);
  end;
  if GetKeyState(VK_CONTROL) < 0 then
  begin
    Include(Result, ssCtrl);
  end;
  if GetKeyState(VK_MENU) < 0 then
  begin
    Include(Result, ssAlt);
  end;
end;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  mControl: TWinControl;
begin
  mControl := FindControl(AWnd);
  Result := (mControl <> nil) and mControl.ClassNameIs('TEditControl');
end;

function LineOf(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine < Length(ALines)) then
  begin
    Result := ALines[ALine];
  end;
end;

procedure Invalidate;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

procedure WriteCaret(const AView: IOTAEditView; const ALines: TArray<string>; ALine, ACharacter: Integer);
var
  mPosition: TOTAEditPos;
begin
  AView.Block.Reset;
  mPosition.Line := ALine + 1;
  mPosition.Col := TLspSession.IndexToColumn(LineOf(ALines, ALine), ACharacter,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  AView.CursorPos := mPosition;
  AView.MoveViewToCursor;
  AView.Paint;
end;

function HasBlock(const AView: IOTAEditView): Boolean;
var
  mBlock: IOTAEditBlock;
begin
  mBlock := AView.Block;
  Result := (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0);
end;

/// <summary>Zeigt der aktuelle Modul ein Formular?</summary>
function FormShown: Boolean;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mForm: IOTAFormEditor;
begin
  Result := False;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mModule := mModules.CurrentModule;
    Result := (mModule <> nil) and Supports(mModule.CurrentEditor, IOTAFormEditor, mForm);
  end;
end;

/// <summary>Antwort an die laufende Instanz; nach dem Abbau verworfen.</summary>
function DeliverToInstance: TAtlasLinkedDeliverProc;
begin
  Result :=
    procedure(ARequest: Integer; const AFileName, AText: string; const ARanges: TAtlasLinkedRanges;
      const AConflicts: TAtlasLinkedConflicts)
    begin
      if TAtlasIdeLinkedEditing.FInstance <> nil then
      begin
        TAtlasIdeLinkedEditing.FInstance.FQuery.Accept(ARequest, AFileName, AText, ARanges, AConflicts);
      end;
    end;
end;

/// <summary>Rahmen um das Vorkommen ARange in der Zeile ARect; ein leerer Name bleibt als schmaler Rahmen
/// sichtbar.</summary>
function FrameOf(const AContext: INTACodeEditorPaintContext; const AText: string; const ARange: TAtlasLinkedRange;
  ATabWidth: Integer; const ARect: TRect): TRect;
var
  mFirst, mLast: TRect;
begin
  mFirst := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, ARange.Character, ATabWidth),
    AContext.EditorLineNum);
  mLast := AContext.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(AText, ARange.EndCharacter, ATabWidth),
    AContext.EditorLineNum);
  Result := TRect.Create(mFirst.Left - 1, ARect.Top, Max(mLast.Left + 1, mFirst.Left + 2), ARect.Bottom);
end;

/// <summary>Bearbeitetes Vorkommen durchgezogen (ABrush), die übrigen gestrichelt (APen).</summary>
procedure PaintFrame(ADC: HDC; const AFrame: TRect; APrimary: Boolean; ABrush: HBRUSH; APen: HPEN);
var
  mOldPen, mOldBrush: HGDIOBJ;
begin
  if APrimary then
  begin
    FrameRect(ADC, AFrame, ABrush);
    Exit;
  end;
  mOldPen := SelectObject(ADC, APen);
  mOldBrush := SelectObject(ADC, GetStockObject(NULL_BRUSH));
  Winapi.Windows.Rectangle(ADC, AFrame.Left, AFrame.Top, AFrame.Right, AFrame.Bottom);
  SelectObject(ADC, mOldBrush);
  SelectObject(ADC, mOldPen);
end;

/// <summary>Marke ACaption kursiv ab Spalte AColumn der Zeile ARect.</summary>
procedure PaintMark(const AContext: INTACodeEditorPaintContext; AColumn: Integer; const ARect: TRect;
  const ACaption: string; AColor: TColor);
var
  mAt: TRect;
  mFont: TFont;
begin
  mAt := AContext.EditorState.GetCharacterPosPx(AColumn, AContext.EditorLineNum);
  mFont := TFont.Create;
  try
    mFont.Assign(AContext.Canvas.Font);
    AContext.Canvas.Font.Style := [fsItalic];
    AContext.Canvas.Font.Color := AColor;
    AContext.Canvas.Brush.Style := bsClear;
    AContext.Canvas.TextOut(mAt.Left, ARect.Top, ACaption);
    AContext.Canvas.Font.Assign(mFont);
  finally
    mFont.Free;
  end;
end;

/// <summary>Rahmen der Vorkommen in Zeile ALine und (in der Zeile des bearbeiteten) die Marke dahinter.</summary>
procedure PaintRun(const ARun: TAtlasIdeLinkedEditing.TRun; const ARect: TRect;
  const AContext: INTACodeEditorPaintContext; ALine: Integer);
var
  mText: string;
  mIndex, mTabWidth, mSaved: Integer;
  mColor: COLORREF;
  mDC: HDC;
  mCode: TRect;
  mBrush: HBRUSH;
  mPen: HPEN;
begin
  mText := ARun.Lines[ALine];
  mTabWidth := TAtlasEditorBuffer.TabWidth(ARun.View.Buffer);
  mColor := COLORREF(ColorToRGB(TColor(TAtlasIdeStyle.Colors.Accent)));
  if ARun.Problem <> TAtlasLinkedProblem.None then
  begin
    mColor := COLORREF(ColorToRGB(TColor(TAtlasIdeStyle.Colors.Error)));
  end;
  mDC := AContext.Canvas.Handle;
  mCode := AContext.LineState.CodeRect;
  mSaved := SaveDC(mDC);
  mBrush := CreateSolidBrush(mColor);
  mPen := CreatePen(PS_DOT, 1, mColor);
  try
    if mCode.Right > mCode.Left then
    begin
      IntersectClipRect(mDC, mCode.Left, ARect.Top, ARect.Right, ARect.Bottom);
    end;
    for mIndex := 0 to High(ARun.Ranges) do
    begin
      if ARun.Ranges[mIndex].Line = ALine then
      begin
        PaintFrame(mDC, FrameOf(AContext, mText, ARun.Ranges[mIndex], mTabWidth, ARect), mIndex = ARun.Primary,
          mBrush, mPen);
      end;
    end;
    // Marke hinter der Zeile des bearbeiteten Vorkommens: Anzahl bzw. Konflikt.
    if ARun.PrimaryRange.Line = ALine then
    begin
      PaintMark(AContext, TLspSession.IndexToColumn(mText, Length(mText), mTabWidth) + 2, ARect, ARun.Caption,
        TColor(mColor));
    end;
  finally
    DeleteObject(mPen);
    DeleteObject(mBrush);
    RestoreDC(mDC, mSaved);
  end;
end;

{ TAtlasIdeLinkedEditing.TEvents }

function TAtlasIdeLinkedEditing.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasIdeLinkedEditing.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasIdeLinkedEditing.TRun }

function TAtlasIdeLinkedEditing.TRun.Active: Boolean;
begin
  Result := Length(Ranges) > 0;
end;

function TAtlasIdeLinkedEditing.TRun.FileName: string;
begin
  Result := '';
  if (View <> nil) and (View.Buffer <> nil) then
  begin
    Result := View.Buffer.FileName;
  end;
end;

function TAtlasIdeLinkedEditing.TRun.PrimaryRange: TAtlasLinkedRange;
begin
  Result := Ranges[Primary];
end;

function TAtlasIdeLinkedEditing.TRun.PrimaryName: string;
begin
  Result := TAtlasLinkedEditing.NameOf(Lines, Ranges[Primary]);
end;

function TAtlasIdeLinkedEditing.TRun.ProblemText: string;
begin
  case Problem of
    TAtlasLinkedProblem.Reserved:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.LinkedEditingReserved, [PrimaryName]);
    TAtlasLinkedProblem.Visible:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.LinkedEditingVisible, [Detail]);
  else
    Result := '';
  end;
end;

function TAtlasIdeLinkedEditing.TRun.Caption: string;
begin
  Result := ProblemText;
  if Result = '' then
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.LinkedEditingCount, [Length(Ranges)]);
  end;
end;

procedure TAtlasIdeLinkedEditing.TRun.SetState(const AText: string; const ARanges: TAtlasLinkedRanges);
begin
  Text := AText;
  Lines := TTextLines.SplitLines(AText);
  Ranges := Copy(ARanges);
end;

procedure TAtlasIdeLinkedEditing.TRun.UpdateProblem;
begin
  Problem := TAtlasLinkedEditing.Problem(PrimaryName, Original, Conflicts, Detail);
end;

function TAtlasIdeLinkedEditing.TRun.NextName(const AView: IOTAEditView; AKind: TAtlasLinkedKey;
  const AInsert: string; out ANewName: string; out ANewOffset: Integer): Boolean;
var
  mLine, mCharacter: Integer;
  mRange: TAtlasLinkedRange;
begin
  ANewName := '';
  ANewOffset := 0;
  TAtlasIdeLinkedEditingQuery.ReadCaret(AView, mLine, mCharacter);
  mRange := PrimaryRange;
  Result := mRange.Contains(mLine, mCharacter) and TAtlasLinkedEditing.Key(TAtlasLinkedEditing.NameOf(Lines, mRange),
    mCharacter - mRange.Character, AKind, AInsert, ANewName, ANewOffset);
end;

function TAtlasIdeLinkedEditing.TRun.Rewind(var ABase: string; var ABaseRanges: TAtlasLinkedRanges): Boolean;
var
  mBuffer: IOTAEditBuffer;
begin
  mBuffer := View.Buffer;
  if mBuffer.Undo and (TAtlasEditorBuffer.Text(mBuffer) = OriginalText) then
  begin
    ABase := OriginalText;
    ABaseRanges := OriginalRanges;
    Exit(True);
  end;
  if TAtlasEditorBuffer.Text(mBuffer) <> Text then
  begin
    mBuffer.Redo;
  end;
  Result := TAtlasEditorBuffer.Text(mBuffer) = Text;
end;

{ TAtlasIdeLinkedEditing }

constructor TAtlasIdeLinkedEditing.Create(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
  const AStatus: TAtlasLinkedStatusProc);
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FBusy := ABusy;
  FStatus := AStatus;
  FIndex := -1;
  FRun.Primary := -1;
  FQuery := TAtlasIdeLinkedEditingQuery.Create(ASession, DeliverToInstance());
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
end;

destructor TAtlasIdeLinkedEditing.Destroy;
var
  mServices: INTACodeEditorServices;
begin
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
  FreeAndNil(FMessages);
  FreeAndNil(FTimer);
  // Wartet laufende Anfragen ab.
  FreeAndNil(FQuery);
  if Assigned(FStatus) and FRun.Active then
  begin
    FStatus('', '');
  end;
  FRun := Default(TRun);
  inherited;
end;

class procedure TAtlasIdeLinkedEditing.Install(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
  const AStatus: TAtlasLinkedStatusProc);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeLinkedEditing.Create(ABusy, ASession, AStatus);
  end;
end;

class procedure TAtlasIdeLinkedEditing.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeLinkedEditing.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.LinkedEditing;
end;

class function TAtlasIdeLinkedEditing.Active: Boolean;
begin
  Result := (FInstance <> nil) and FInstance.FRun.Active;
end;

function TAtlasIdeLinkedEditing.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

function TAtlasIdeLinkedEditing.Start(const AView: IOTAEditView): Boolean;
var
  mCandidate: TAtlasLinkedCandidate;
  mText: string;
  mLine, mCharacter, mPrimary: Integer;
begin
  mCandidate := FQuery.Candidate;
  Result := Enabled and not IsBusy and mCandidate.Valid and (AView <> nil) and (AView.Buffer <> nil) and
    not AView.Buffer.IsReadOnly and SameText(mCandidate.FileName, AView.Buffer.FileName) and not HasBlock(AView);
  if not Result then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(AView.Buffer);
  TAtlasIdeLinkedEditingQuery.ReadCaret(AView, mLine, mCharacter);
  mPrimary := TAtlasLinkedEditing.IndexAt(mCandidate.Ranges, mLine, mCharacter);
  Result := (mText = mCandidate.Text) and
    TAtlasLinkedEditing.Matches(TTextLines.SplitLines(mText), mCandidate.Ranges) and (mPrimary >= 0);
  if not Result then
  begin
    Exit;
  end;
  FRun.View := AView;
  FRun.Primary := mPrimary;
  FRun.Conflicts := mCandidate.Conflicts;
  FRun.OriginalText := mText;
  FRun.OriginalRanges := Copy(mCandidate.Ranges);
  FRun.SetState(mText, mCandidate.Ranges);
  FRun.Original := FRun.PrimaryName;
  FRun.Grouped := False;
  FRun.Problem := TAtlasLinkedProblem.None;
  FRun.Detail := '';
  FQuery.Drop;
end;

procedure TAtlasIdeLinkedEditing.WriteNames(const ABuffer: IOTAEditBuffer; const ABase: string;
  const ARanges: TAtlasLinkedRanges; const AName: string; ASkip: Integer);
var
  mTable: TLineTable;
  mStarts: TList<Integer>;
  mLengths: TDictionary<Integer, Integer>;
  mIndex, mOffset: Integer;
  mWriter: IOTAEditWriter;
  mUtf8: UTF8String;
begin
  mTable := TLineTable.Build(ABase);
  mStarts := TList<Integer>.Create;
  mLengths := TDictionary<Integer, Integer>.Create;
  FWriting := True;
  try
    for mIndex := 0 to High(ARanges) do
    begin
      mOffset := mTable.LineStart(ARanges[mIndex].Line) + ARanges[mIndex].Character;
      if (mIndex <> ASkip) and not mLengths.ContainsKey(mOffset) then
      begin
        mStarts.Add(mOffset);
        mLengths.Add(mOffset, ARanges[mIndex].Length);
      end;
    end;
    mStarts.Sort;
    mUtf8 := UTF8Encode(AName);
    // Ein Schreiber: ein Rückgängig-Schritt; nur die Namen, der Text dazwischen bleibt unberührt.
    mWriter := ABuffer.CreateUndoableWriter;
    for mOffset in mStarts do
    begin
      mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(ABase, 1, mOffset)));
      mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(ABase, 1, mOffset + mLengths[mOffset])));
      if mUtf8 <> '' then
      begin
        mWriter.Insert(PAnsiChar(mUtf8));
      end;
    end;
    mWriter := nil;
  finally
    FWriting := False;
    mLengths.Free;
    mStarts.Free;
  end;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function TAtlasIdeLinkedEditing.Prepare(out AView: IOTAEditView): Boolean;
var
  mText: string;
begin
  Result := False;
  AView := TAtlasEditorBuffer.ActiveView;
  if (AView = nil) or (AView.Buffer = nil) then
  begin
    Exit;
  end;
  if FRun.Active and not SameText(AView.Buffer.FileName, FRun.FileName) then
  begin
    Finish;
  end;
  if not FRun.Active and not Start(AView) then
  begin
    Exit;
  end;
  // Mit Markierung ersetzt die Taste die Markierung: das bleibt der IDE.
  Result := not HasBlock(AView);
  if Result then
  begin
    mText := TAtlasEditorBuffer.Text(AView.Buffer);
    Result := (mText = FRun.Text) or Follow(mText);
  end;
  if not Result then
  begin
    Finish;
  end;
end;

function TAtlasIdeLinkedEditing.Edit(AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
var
  mView: IOTAEditView;
  mNewName, mBase: string;
  mNewOffset: Integer;
  mBaseRanges: TAtlasLinkedRanges;
begin
  Result := False;
  if not Prepare(mView) then
  begin
    Exit;
  end;
  if not FRun.NextName(mView, AKind, AInsert, mNewName, mNewOffset) then
  begin
    Finish;
    Exit;
  end;
  // Direkt auf den eigenen Schritt: zurücknehmen und die ganze Sitzung als einen Schritt schreiben.
  mBase := FRun.Text;
  mBaseRanges := FRun.Ranges;
  if FRun.Grouped and not FRun.Rewind(mBase, mBaseRanges) then
  begin
    // Lässt sich der Stand nicht wiederherstellen, lieber nichts ändern.
    Finish;
    Exit(True);
  end;
  Result := Apply(mView, mBase, mBaseRanges, mNewName, mNewOffset);
end;

function TAtlasIdeLinkedEditing.Apply(const AView: IOTAEditView; const ABase: string;
  const ABaseRanges: TAtlasLinkedRanges; const ANewName: string; ANewOffset: Integer): Boolean;
var
  mNewText: string;
  mNewRanges: TAtlasLinkedRanges;
  mGrouped: Boolean;
begin
  Result := TAtlasLinkedEditing.Rename(ABase, ABaseRanges, ANewName, mNewText, mNewRanges);
  if not Result then
  begin
    Finish;
    Exit;
  end;
  // Ein Schritt ab dem Stand zu Beginn enthält die ganze Sitzung.
  mGrouped := ABase = FRun.OriginalText;
  WriteNames(AView.Buffer, ABase, ABaseRanges, ANewName, -1);
  if TAtlasEditorBuffer.Text(AView.Buffer) <> mNewText then
  begin
    // Der Puffer sieht anders aus als gerechnet: Sitzung beenden, nichts weiter schreiben.
    Finish;
    Exit;
  end;
  FRun.Grouped := mGrouped;
  FRun.SetState(mNewText, mNewRanges);
  WriteCaret(AView, FRun.Lines, FRun.PrimaryRange.Line, FRun.PrimaryRange.Character + ANewOffset);
  FRun.UpdateProblem;
  Refresh;
end;

function TAtlasIdeLinkedEditing.Follow(const AText: string): Boolean;
var
  mLines: TArray<string>;
  mIndex, mLine: Integer;
  mName, mNewText: string;
  mRanges, mNewRanges: TAtlasLinkedRanges;
begin
  Result := FRun.Active;
  if not Result then
  begin
    Exit;
  end;
  // Nur die Zeile des bearbeiteten Namens darf sich geändert haben.
  mLines := TTextLines.SplitLines(AText);
  mLine := FRun.PrimaryRange.Line;
  Result := Length(mLines) = Length(FRun.Lines);
  mIndex := 0;
  while Result and (mIndex <= High(mLines)) do
  begin
    Result := (mIndex = mLine) or (mLines[mIndex] = FRun.Lines[mIndex]);
    Inc(mIndex);
  end;
  Result := Result and TAtlasLinkedEditing.Follow(FRun.Lines[mLine], mLines[mLine], FRun.PrimaryRange, mName) and
    TAtlasLinkedEditing.IsName(mName);
  if Result then
  begin
    mRanges := TAtlasLinkedEditing.Resized(FRun.Ranges, FRun.Primary, Length(mName));
    Result := TAtlasLinkedEditing.Rename(AText, mRanges, mName, mNewText, mNewRanges);
  end;
  if not Result then
  begin
    Exit;
  end;
  // Die Änderung der IDE liegt jetzt oben in der Rückgängig-Liste: ab hier ein Schritt je Taste.
  WriteNames(FRun.View.Buffer, AText, mRanges, mName, FRun.Primary);
  Result := TAtlasEditorBuffer.Text(FRun.View.Buffer) = mNewText;
  if Result then
  begin
    FRun.Grouped := False;
    FRun.SetState(mNewText, mNewRanges);
    FRun.UpdateProblem;
  end;
end;

procedure TAtlasIdeLinkedEditing.Restore;
var
  mBuffer: IOTAEditBuffer;
  mText: string;
begin
  if not FRun.Active or (FRun.View = nil) or (FRun.View.Buffer = nil) then
  begin
    Exit;
  end;
  mBuffer := FRun.View.Buffer;
  mText := TAtlasEditorBuffer.Text(mBuffer);
  if FRun.Grouped and (mText = FRun.Text) and mBuffer.Undo and
    (TAtlasEditorBuffer.Text(mBuffer) = FRun.OriginalText) then
  begin
    FRun.SetState(FRun.OriginalText, FRun.OriginalRanges);
    WriteCaret(FRun.View, FRun.Lines, FRun.PrimaryRange.Line, FRun.PrimaryRange.EndCharacter);
    Exit;
  end;
  if TAtlasEditorBuffer.Text(mBuffer) <> FRun.Text then
  begin
    mBuffer.Redo;
  end;
  if TAtlasEditorBuffer.Text(mBuffer) = FRun.Text then
  begin
    WriteNames(mBuffer, FRun.Text, FRun.Ranges, FRun.Original, -1);
    WriteCaret(FRun.View, TTextLines.SplitLines(TAtlasEditorBuffer.Text(mBuffer)), FRun.PrimaryRange.Line,
      FRun.PrimaryRange.Character + Length(FRun.Original));
  end;
end;

procedure TAtlasIdeLinkedEditing.Reconcile;
var
  mText: string;
begin
  if not FRun.Active or (FRun.View = nil) or (FRun.View.Buffer = nil) then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(FRun.View.Buffer);
  if mText = FRun.Text then
  begin
    Exit;
  end;
  if Follow(mText) then
  begin
    Refresh;
  end
  else
  begin
    Finish;
  end;
end;

procedure TAtlasIdeLinkedEditing.Refresh;
var
  mHint: string;
begin
  if not FRun.Active then
  begin
    Exit;
  end;
  if Assigned(FStatus) then
  begin
    mHint := '';
    if FRun.ProblemText <> '' then
    begin
      mHint := TAtlasEditorStrings.Text(TAtlasEditorTextId.LinkedEditingRestoreHint);
    end;
    FStatus(FRun.Caption, mHint);
  end;
  Invalidate;
end;

procedure TAtlasIdeLinkedEditing.Finish;
var
  mWas: Boolean;
begin
  mWas := FRun.Active;
  FRun := Default(TRun);
  FRun.Primary := -1;
  FRun.Problem := TAtlasLinkedProblem.None;
  FHighSurrogate := #0;
  if mWas then
  begin
    if Assigned(FStatus) then
    begin
      FStatus('', '');
    end;
    Invalidate;
  end;
end;

class procedure TAtlasIdeLinkedEditing.Dismiss;
begin
  if FInstance <> nil then
  begin
    FInstance.Finish;
    FInstance.FQuery.Drop;
  end;
end;

class procedure TAtlasIdeLinkedEditing.EditorModified(const AView: IOTAEditView);
begin
  if (FInstance = nil) or FInstance.FWriting then
  begin
    Exit;
  end;
  // Ohne Sitzung gilt die letzte Antwort nicht mehr; beim nächsten Ruhen fragt Atlas neu.
  if not FInstance.FRun.Active then
  begin
    FInstance.FQuery.Forget;
    Exit;
  end;
  if (AView = nil) or (AView.Buffer = nil) or not SameText(AView.Buffer.FileName, FInstance.FRun.FileName) then
  begin
    Exit;
  end;
  // Nie im Notifier schreiben: nach der Änderung, in der Warteschlange des Hauptthreads.
  TAtlasMainThread.ForceQueue(TAtlasFeature.LinkedEditing,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.LinkedEditing,
        procedure
        begin
          if FInstance <> nil then
          begin
            FInstance.Reconcile;
          end;
        end);
    end);
end;

procedure TAtlasIdeLinkedEditing.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
  begin
    Exit;
  end;
  try
    case Msg.message of
      WM_KEYDOWN, WM_SYSKEYDOWN:
        KeyDown(Msg, Handled);
      WM_CHAR:
        CharTyped(Msg, Handled);
    end;
  except
    // Keine Exception an die IDE (#493); die Nachricht geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.LinkedEditing, E);
    end;
  end;
end;

procedure TAtlasIdeLinkedEditing.KeyDown(const AMsg: TMsg; var AHandled: Boolean);
var
  mKey: Word;
begin
  if not IsEditorWindow(AMsg.hwnd) then
  begin
    Exit;
  end;
  if not Enabled or IsBusy then
  begin
    Finish;
    Exit;
  end;
  mKey := Word(AMsg.wParam);
  // Mit Strg, Alt oder Umschalt (Wort löschen, Rückgängig ...) arbeitet die IDE; Follow bzw. der Takt ziehen nach.
  if (mKey = VK_SHIFT) or (mKey = VK_CONTROL) or (mKey = VK_MENU) or (CurrentShift <> []) then
  begin
    Exit;
  end;
  case mKey of
    VK_ESCAPE:
      if FRun.Active then
      begin
        if FRun.Problem <> TAtlasLinkedProblem.None then
        begin
          Restore;
        end;
        Finish;
        AHandled := True;
      end;
    VK_RETURN:
      if FRun.Active then
      begin
        Finish;
        AHandled := True;
      end;
    VK_BACK:
      AHandled := Edit(TAtlasLinkedKey.Backspace, '');
    VK_DELETE:
      AHandled := Edit(TAtlasLinkedKey.Delete, '');
  end;
end;

function TAtlasIdeLinkedEditing.Surrogate(ATyped: Char; var AHandled: Boolean): Boolean;
var
  mPair: string;
begin
  // Zeichen außerhalb der Grundebene kommen als zwei WM_CHAR; nur in einer laufenden Sitzung.
  Result := (ATyped >= #$D800) and (ATyped <= #$DBFF);
  if Result then
  begin
    if FRun.Active then
    begin
      FHighSurrogate := ATyped;
      AHandled := True;
    end;
    Exit;
  end;
  Result := (FHighSurrogate <> #0) and (ATyped >= #$DC00) and (ATyped <= #$DFFF);
  if Result then
  begin
    mPair := FHighSurrogate + ATyped;
    FHighSurrogate := #0;
    AHandled := True;
    if not Edit(TAtlasLinkedKey.Insert, mPair) and (TAtlasEditorBuffer.ActiveView <> nil) then
    begin
      TAtlasEditorBuffer.ActiveView.Position.InsertText(mPair);
    end;
  end;
end;

procedure TAtlasIdeLinkedEditing.CharTyped(const AMsg: TMsg; var AHandled: Boolean);
var
  mTyped: Char;
begin
  if not IsEditorWindow(AMsg.hwnd) or not Enabled or IsBusy then
  begin
    Exit;
  end;
  mTyped := Char(AMsg.wParam);
  if (mTyped < ' ') or (mTyped = #127) or Surrogate(mTyped, AHandled) then
  begin
    Exit;
  end;
  FHighSurrogate := #0;
  // Leerzeichen, Punkt, Klammer ...: Sitzung zu Ende, das Zeichen schreibt die IDE.
  if TTextChars.IsIdentChar(mTyped) then
  begin
    AHandled := Edit(TAtlasLinkedKey.Insert, mTyped);
  end
  else
  begin
    Finish;
  end;
end;

procedure TAtlasIdeLinkedEditing.TimerTick(Sender: TObject);
begin
  try
    if TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
    begin
      Exit;
    end;
    FQuery.Prune;
    if FRun.Active then
    begin
      if not FWriting then
      begin
        CheckRun;
      end;
    end
    else if Enabled and not IsBusy and Application.Active then
    begin
      FQuery.Watch(TAtlasEditorBuffer.ActiveView);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LinkedEditing, E);
  end;
end;

function TAtlasIdeLinkedEditing.Lost(const AView: IOTAEditView): Boolean;
begin
  Result := (AView = nil) or (AView.Buffer = nil) or not SameText(AView.Buffer.FileName, FRun.FileName) or
    not Enabled or IsBusy or FormShown;
end;

procedure TAtlasIdeLinkedEditing.CheckRun;
var
  mView: IOTAEditView;
  mLine, mCharacter: Integer;
begin
  mView := TAtlasEditorBuffer.ActiveView;
  // Datei gewechselt, Formular angezeigt oder abgeschaltet: Sitzung zu Ende.
  if Lost(mView) then
  begin
    Finish;
    Exit;
  end;
  // Eine Änderung, deren Meldung noch aussteht, zuerst nachziehen.
  if TAtlasEditorBuffer.LineText(mView, FRun.PrimaryRange.Line + 1) <> FRun.Lines[FRun.PrimaryRange.Line] then
  begin
    Reconcile;
  end;
  if not FRun.Active then
  begin
    Exit;
  end;
  // Cursor hat den Namen verlassen.
  TAtlasIdeLinkedEditingQuery.ReadCaret(mView, mLine, mCharacter);
  if not FRun.PrimaryRange.Contains(mLine, mCharacter) then
  begin
    Finish;
  end;
end;

procedure TAtlasIdeLinkedEditing.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mLine: Integer;
begin
  if not FRun.Active or TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
  begin
    Exit;
  end;
  try
    // Nur, wenn die Zeile im Editor dem bekannten Stand entspricht (sonst steht gleich ein Reconcile an).
    if TAtlasPaintedLine.Resolve(Stage, BeforeEvent, Context, FRun.FileName, FRun.Lines, mLine) then
    begin
      PaintRun(FRun, Rect, Context, mLine);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LinkedEditing, E);
  end;
end;

end.
