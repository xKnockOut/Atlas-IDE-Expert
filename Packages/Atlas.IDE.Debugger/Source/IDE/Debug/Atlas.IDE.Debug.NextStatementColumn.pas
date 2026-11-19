unit Atlas.IDE.Debug.NextStatementColumn;

// Ausführungspfeil ziehen (#871): Solange das Programm angehalten ist und debug.dragNextStatement an ist, steht
// rechts der Zeilennummern eine schmale Spalte (TAtlasIdeDebugStopColumn) mit einem Pfeil in der Warnfarbe an der
// Zeile des Ausführungspunkts. Läuft das Programm wieder, verschwindet die Spalte.
// - Maustaste auf dem Pfeil drücken greift ihn; beim Ziehen zeigt der Mauszeiger, ob die Zeile darunter ein
//   erlaubtes Ziel ist (sonst Verbot), ein Tooltip nennt die Folge bzw. den Grund, und an erlaubten Zielen steht
//   der Pfeil in der Akzentfarbe.
// - Loslassen auf einem erlaubten Ziel setzt die nächste Anweisung (TAtlasIdeNextStatement.MoveTo, nach dem
//   Ereignis des Editors eingereiht, weil beim ersten Mal ein Hinweis kommt).
// - Rechtsklick merkt die Zeile für „Nächste Anweisung hier“ im Kontextmenü (TAtlasIdeGutterMarks.RememberLine).
// Gesichert über TAtlasFeature.Debugger. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.IDE.Debug.StopColumn;

type
  TAtlasIdeNextStatementColumn = class(TAtlasIdeDebugStopColumn)
  private class var
    FInstance: TAtlasIdeNextStatementColumn;
  private
    /// <summary>Pfeil gegriffen; FOver ist die Zeile darunter, FAllowed ob sie ein erlaubtes Ziel ist.</summary>
    FDragging: Boolean;
    FOver: TAtlasDebugStopRow;
    FAllowed: Boolean;
    function IsCurrent(const ARow: TAtlasDebugStopRow): Boolean;
    procedure DragTo(const AEditor: TWinControl; const ARow: TAtlasDebugStopRow);
    procedure EndDrag;
  protected
    function Wanted: Boolean; override;
    procedure Tick; override;
    procedure Idle; override;
    procedure PaintRow(ACanvas: TCanvas; const ARow: TAtlasDebugStopRow); override;
    procedure EditorMouseDown(const AEditor: TWinControl; AButton: TMouseButton; AShift: TShiftState;
      AX, AY: Integer); override;
    procedure EditorMouseMove(const AEditor: TWinControl; AShift: TShiftState; AX, AY: Integer); override;
    procedure EditorMouseUp(const AEditor: TWinControl; AButton: TMouseButton; AShift: TShiftState;
      AX, AY: Integer); override;
  public
    destructor Destroy; override;
    class procedure Install; static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
  end;

implementation

uses
  Winapi.Windows,
  System.UITypes,
  Vcl.Forms,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Debug.NextStatement,
  Atlas.UI.Debug.NextStatement.Strings;

const
  /// <summary>Abstand des Tooltips zur Zelle (Pixel).</summary>
  cTipGap = 4;

{ TAtlasIdeNextStatementColumn }

destructor TAtlasIdeNextStatementColumn.Destroy;
begin
  EndDrag;
  inherited Destroy;
end;

function TAtlasIdeNextStatementColumn.Wanted: Boolean;
var
  mFileName: string;
  mLine: Integer;
begin
  Result := Registered and not TAtlasGuard.Disabled(TAtlasFeature.Debugger) and TAtlasIdeNextStatement.Enabled and
    TAtlasIdeNextStatement.Current(mFileName, mLine);
end;

procedure TAtlasIdeNextStatementColumn.Idle;
begin
  EndDrag;
end;

procedure TAtlasIdeNextStatementColumn.Tick;
begin
  // Maustaste außerhalb des Editors losgelassen: Ziehen abbrechen.
  if FDragging and (GetAsyncKeyState(VK_LBUTTON) >= 0) then
  begin
    EndDrag;
  end;
end;

function TAtlasIdeNextStatementColumn.IsCurrent(const ARow: TAtlasDebugStopRow): Boolean;
var
  mFileName: string;
  mLine: Integer;
begin
  Result := TAtlasIdeNextStatement.Current(mFileName, mLine) and (ARow.Line = mLine) and
    SameText(ARow.FileName, mFileName);
end;

procedure TAtlasIdeNextStatementColumn.PaintRow(ACanvas: TCanvas; const ARow: TAtlasDebugStopRow);
begin
  if IsCurrent(ARow) then
  begin
    PaintArrow(ACanvas, ARow.Rect, True);
  end
  else if FDragging and FAllowed and (ARow.Line = FOver.Line) and SameText(ARow.FileName, FOver.FileName) then
  begin
    PaintArrow(ACanvas, ARow.Rect, False);
  end;
end;

procedure TAtlasIdeNextStatementColumn.EditorMouseDown(const AEditor: TWinControl; AButton: TMouseButton;
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
    // Gilt für „Nächste Anweisung hier“ im Kontextmenü.
    TAtlasIdeGutterMarks.RememberLine(mRow.FileName, mRow.Line);
  end
  else if (AButton = mbLeft) and IsCurrent(mRow) then
  begin
    FDragging := True;
    FOver := mRow;
    FAllowed := False;
    Screen.Cursor := crDrag;
  end;
end;

procedure TAtlasIdeNextStatementColumn.EditorMouseMove(const AEditor: TWinControl; AShift: TShiftState;
  AX, AY: Integer);
var
  mRow: TAtlasDebugStopRow;
begin
  if not FDragging then
  begin
    Exit;
  end;
  if not Wanted or not RowAt(AX, AY, True, mRow) then
  begin
    FAllowed := False;
    Screen.Cursor := crNo;
    HideTip;
  end
  else if (mRow.Line <> FOver.Line) or not SameText(mRow.FileName, FOver.FileName) then
  begin
    DragTo(AEditor, mRow);
  end;
end;

procedure TAtlasIdeNextStatementColumn.DragTo(const AEditor: TWinControl; const ARow: TAtlasDebugStopRow);
var
  mText: string;
  mScreen: TRect;
begin
  FOver := ARow;
  FAllowed := False;
  Screen.Cursor := crDrag;
  HideTip;
  // Zurück am Ausgangspunkt: nichts setzen, kein Verbot.
  if not IsCurrent(ARow) then
  begin
    FAllowed := TAtlasIdeNextStatement.Preview(ARow.FileName, ARow.Line, mText);
    if not FAllowed then
    begin
      Screen.Cursor := crNo;
    end;
    mScreen := ScreenRect(AEditor, ARow);
    TAtlasIdeStyle.Apply(Tip, mScreen);
    Tip.ShowNote(TAtlasNextStatementStrings.Text(TAtlasNextStatementTextId.TipTitle), mText,
      Point(mScreen.Right + cTipGap, mScreen.Bottom + cTipGap div 2));
  end;
  Invalidate;
end;

/// <summary>Nach dem Ereignis des Editors setzen: Beim ersten Mal fragt ein Dialog nach.</summary>
procedure QueueMove(const AFileName: string; ALine: Integer);
begin
  TAtlasMainThread.ForceQueue(TAtlasFeature.Debugger,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Debugger,
        procedure
        begin
          if TAtlasIdeNextStatement.Enabled then
          begin
            TAtlasIdeNextStatement.MoveTo(AFileName, ALine);
          end;
        end);
    end);
end;

procedure TAtlasIdeNextStatementColumn.EditorMouseUp(const AEditor: TWinControl; AButton: TMouseButton;
  AShift: TShiftState; AX, AY: Integer);
var
  mDrop: Boolean;
  mTarget: TAtlasDebugStopRow;
begin
  if not FDragging or (AButton <> mbLeft) then
  begin
    Exit;
  end;
  mDrop := FAllowed;
  mTarget := FOver;
  EndDrag;
  if mDrop then
  begin
    QueueMove(mTarget.FileName, mTarget.Line);
  end;
end;

procedure TAtlasIdeNextStatementColumn.EndDrag;
begin
  if not FDragging then
  begin
    Exit;
  end;
  FDragging := False;
  FAllowed := False;
  Screen.Cursor := crDefault;
  HideTip;
  Invalidate;
end;

class procedure TAtlasIdeNextStatementColumn.Install;
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeNextStatementColumn.Create;
  end;
end;

class procedure TAtlasIdeNextStatementColumn.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeNextStatementColumn.Installed: Boolean;
begin
  Result := FInstance <> nil;
end;

end.
