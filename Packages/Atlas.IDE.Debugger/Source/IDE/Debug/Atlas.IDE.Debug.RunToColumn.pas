unit Atlas.IDE.Debug.RunToColumn;

// Spalte „Bis hier ausführen“ im Rand (#851): Solange das Programm
// angehalten ist und debug.runToClick an ist, steht rechts der Zeilennummern
// eine schmale Spalte (TAtlasIdeDebugStopColumn); läuft das Programm wieder,
// verschwindet sie.
// - Unter dem Mauszeiger zeigt die Spalte ▶, wenn die Zeile ausführbaren Code
//   hat (TAtlasRunTo.CodeLine auf dem Text des Editors).
// - Klick: bis hier ausführen; Strg+Klick: dabei andere Haltepunkte
//   überspringen (TAtlasIdeRunTo.RunToLine). Rechtsklick merkt die Zeile für
//   die Befehle im Kontextmenü (TAtlasIdeGutterMarks.RememberLine).
// - Nach kurzem Verweilen ein Tooltip mit den Tastenhinweisen.
// Gesichert über TAtlasFeature.Debugger. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Editor.MethodToggle,
  Atlas.IDE.Debug.StopColumn;

type
  TAtlasIdeRunToColumn = class(TAtlasIdeDebugStopColumn)
  private const
    cHoverMs = 400;
    cTextMs = 500;
  private class var
    FInstance: TAtlasIdeRunToColumn;
  private
    FHover: TAtlasDebugStopRow;
    FHovering: Boolean;
    FHoverSince: UInt64;
    FHoverScreen: TRect;
    // Text der oberen Datei für CodeLine, höchstens alle cTextMs gelesen.
    FCodeFile: string;
    FCodeText: string;
    FCodeLines: TArray<string>;
    FCodePlaces: TArray<TAtlasMethodPlace>;
    FCodeReadAt: UInt64;
    procedure ReadText;
    function IsCode(const AFileName: string; ALine: Integer): Boolean;
    procedure CheckHover;
    procedure Leave;
  protected
    function Wanted: Boolean; override;
    procedure Tick; override;
    procedure Idle; override;
    procedure PaintRow(ACanvas: TCanvas; const ARow: TAtlasDebugStopRow); override;
    procedure EditorMouseDown(const AEditor: TWinControl; AButton: TMouseButton; AShift: TShiftState;
      AX, AY: Integer); override;
    procedure EditorMouseMove(const AEditor: TWinControl; AShift: TShiftState; AX, AY: Integer); override;
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  ToolsAPI,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Debug.RunToColumnFlow,
  Atlas.Core.Editor.LineAnchor,
  Atlas.Core.Debug.RunTo,
  Atlas.UI.Debug.Stepping.Strings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.RunTo;

const
  /// <summary>Abstand des Tooltips zur Zelle (Pixel).</summary>
  cTipGap = 4;

{ TAtlasIdeRunToColumn }

function TAtlasIdeRunToColumn.Wanted: Boolean;
begin
  Result := Registered and not TAtlasGuard.Disabled(TAtlasFeature.Debugger) and TAtlasIdeRunTo.Enabled and
    (TAtlasIdeDebugSession.StoppedThread <> nil);
end;

procedure TAtlasIdeRunToColumn.Idle;
begin
  Leave;
  FCodeFile := '';
end;

procedure TAtlasIdeRunToColumn.Tick;
begin
  ReadText;
  CheckHover;
end;

procedure TAtlasIdeRunToColumn.ReadText;
var
  mView: IOTAEditView;
  mText: string;
begin
  mView := TAtlasEditorBuffer.TopView;
  if (mView = nil) or (mView.Buffer = nil) or not TAtlasRunToColumnFlow.ReadDue(SameText(FCodeFile,
    mView.Buffer.FileName), TThread.GetTickCount64, FCodeReadAt, cTextMs) then
  begin
    Exit;
  end;
  FCodeReadAt := TThread.GetTickCount64;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  if SameText(FCodeFile, mView.Buffer.FileName) and (mText = FCodeText) then
  begin
    Exit;
  end;
  FCodeFile := mView.Buffer.FileName;
  FCodeText := mText;
  FCodeLines := TAtlasLineAnchors.Lines(mText);
  FCodePlaces := TAtlasMethodToggle.Places(mText);
end;

function TAtlasIdeRunToColumn.IsCode(const AFileName: string; ALine: Integer): Boolean;
begin
  Result := SameText(AFileName, FCodeFile) and TAtlasRunTo.CodeLine(FCodeLines, FCodePlaces, ALine);
end;

procedure TAtlasIdeRunToColumn.PaintRow(ACanvas: TCanvas; const ARow: TAtlasDebugStopRow);
begin
  if TAtlasRunToColumnFlow.SameHover(FHovering, FHover, ARow) and IsCode(ARow.FileName, ARow.Line) then
  begin
    PaintArrow(ACanvas, ARow.Rect, False);
  end;
end;

procedure TAtlasIdeRunToColumn.EditorMouseMove(const AEditor: TWinControl; AShift: TShiftState; AX, AY: Integer);
var
  mRow: TAtlasDebugStopRow;
begin
  if not Wanted or not RowAt(AX, AY, False, mRow) or not IsCode(mRow.FileName, mRow.Line) then
  begin
    Leave;
    Exit;
  end;
  if TAtlasRunToColumnFlow.SameHover(FHovering, FHover, mRow) then
  begin
    Exit;
  end;
  HideTip;
  FHover := mRow;
  FHovering := True;
  FHoverSince := TThread.GetTickCount64;
  FHoverScreen := ScreenRect(AEditor, mRow);
  Invalidate;
end;

procedure TAtlasIdeRunToColumn.EditorMouseDown(const AEditor: TWinControl; AButton: TMouseButton;
  AShift: TShiftState; AX, AY: Integer);
var
  mRow: TAtlasDebugStopRow;
begin
  if not Wanted or not RowAt(AX, AY, False, mRow) then
  begin
    Exit;
  end;
  if AButton = mbRight then
  begin
    // Gilt für „Bis hier …“ und „Einmaliger Haltepunkt“ im Kontextmenü.
    TAtlasIdeGutterMarks.RememberLine(mRow.FileName, mRow.Line);
  end
  else if (AButton = mbLeft) and IsCode(mRow.FileName, mRow.Line) then
  begin
    Leave;
    TAtlasIdeRunTo.RunToLine(mRow.FileName, mRow.Line, ssCtrl in AShift);
  end;
end;

procedure TAtlasIdeRunToColumn.CheckHover;
begin
  if not FHovering then
  begin
    Exit;
  end;
  // Maus hat die Zeile verlassen, ohne dass der Editor es gemeldet hat (anderes Fenster).
  if not PtInRect(FHoverScreen, Mouse.CursorPos) then
  begin
    Leave;
  end
  else if TAtlasRunToColumnFlow.TipDue(Tip.IsShown, TThread.GetTickCount64, FHoverSince, cHoverMs) then
  begin
    TAtlasIdeStyle.Apply(Tip, FHoverScreen);
    Tip.ShowNote(TAtlasSteppingStrings.Text(TAtlasSteppingTextId.RunToTipTitle),
      TAtlasSteppingStrings.Fmt(TAtlasSteppingTextId.RunToTipText, [FHover.Line + 1]),
      Point(FHoverScreen.Right + cTipGap, FHoverScreen.Bottom + cTipGap div 2));
  end;
end;

procedure TAtlasIdeRunToColumn.Leave;
begin
  HideTip;
  if FHovering then
  begin
    FHovering := False;
    Invalidate;
  end;
end;

class procedure TAtlasIdeRunToColumn.Install;
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeRunToColumn.Create;
  end;
end;

class procedure TAtlasIdeRunToColumn.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeRunToColumn.Installed: Boolean;
begin
  Result := FInstance <> nil;
end;

end.
