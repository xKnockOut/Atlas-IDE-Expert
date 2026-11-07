unit Atlas.IDE.Editor.WrapSelection;

// Markierung beim Tippen umschließen (#672) im Editor. Was mit dem Text
// geschieht, rechnet Atlas.Core.Editor.WrapSelection aus; hier bleiben Taste,
// Puffer und Markierung.
// - Application.OnMessage fängt im Editor ein Zeichen (WM_CHAR, also auch
//   AltGr wie { und [) nur ab, wenn Text markiert ist und das Zeichen nach
//   editor.wrapSelection.chars umschließt; sonst tippt die IDE wie immer.
//   Lässt sich die Markierung nicht umschließen (' in einem String, < ohne
//   Typnamen davor), geht das Zeichen ebenfalls an die IDE.
// - Spaltenblock: jede Zeile einzeln; mehrere Einfügemarken (#589) erledigt
//   Atlas.IDE.Editor.MultiCursor mit demselben Kern.
// - Ein Schreiber (CreateUndoableWriter), also ein Rückgängig-Schritt; danach
//   liegt die Markierung wieder auf dem ursprünglichen Text.
// - Nie bei offener Vervollständigung, im Platzhalter-Modus, mit mehreren
//   Einfügemarken oder beim Mitziehen von Bezeichnern (#658).
// - editor.wrapSelection aus: keine Wirkung.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.AppEvnts;

type
  TAtlasIdeWrapSelection = class
  private class var
    FInstance: TAtlasIdeWrapSelection;
  private
    FBusy: TFunc<Boolean>;
    FMessages: TApplicationEvents;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
  public
    constructor Create(const ABusy: TFunc<Boolean>);
    destructor Destroy; override;
    /// <summary>ABusy: True, solange Atlas keine Taste abfangen darf (Vervollständigung, Platzhalter, mehrere
    /// Einfügemarken, Mitziehen).</summary>
    class procedure Install(const ABusy: TFunc<Boolean>); static;
    class procedure Uninstall; static;
    /// <summary>editor.wrapSelection an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Zeichen, die umschließen (editor.wrapSelection.chars, bereinigt).</summary>
    class function Chars: string; static;
    /// <summary>Umschließt die Markierung im oberen Editor mit AOpen; False, wenn die IDE das Zeichen tippen soll.
    /// </summary>
    class function Run(AOpen: Char): Boolean; static;
  end;

implementation

uses
  System.Math,
  Vcl.Controls,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LineMove,
  Atlas.Core.Editor.WrapSelection,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  mControl: TWinControl;
begin
  mControl := FindControl(AWnd);
  Result := (mControl <> nil) and mControl.ClassNameIs('TEditControl');
end;

/// <summary>Ersetzt in ABuffer (Text AText) ab Zeichen AStart AOldLength Zeichen durch AInsert; ein
/// Rückgängig-Schritt.</summary>
procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText: string; AStart, AOldLength: Integer;
  const AInsert: string);
var
  mWriter: IOTAEditWriter;
begin
  mWriter := ABuffer.CreateUndoableWriter;
  mWriter.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart)));
  mWriter.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart + AOldLength)));
  if AInsert <> '' then
  begin
    mWriter.Insert(PAnsiChar(UTF8Encode(AInsert)));
  end;
  mWriter := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function LineOf(const ALines: TArray<string>; ARow: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow <= Length(ALines)) then
  begin
    Result := ALines[ARow - 1];
  end;
end;

function EditPos(const ALines: TArray<string>; const APosition: TLspTextPosition; ATabWidth: Integer): TOTAEditPos;
begin
  Result.Line := APosition.Line + 1;
  Result.Col := TLspSession.IndexToColumn(LineOf(ALines, Result.Line), APosition.Character, ATabWidth);
end;

function PositionOf(const ALines: TArray<string>; ARow, AColumn, ATabWidth: Integer): TLspTextPosition;
begin
  Result := TLspTextPosition.Create(ARow - 1, TLspSession.ColumnToIndex(LineOf(ALines, ARow), AColumn, ATabWidth));
end;

/// <summary>AView hat einen beschreibbaren Puffer und eine Markierung.</summary>
function WritableSelection(const AView: IOTAEditView): Boolean;
var
  mBlock: IOTAEditBlock;
begin
  Result := (AView <> nil) and (AView.Buffer <> nil) and not AView.Buffer.IsReadOnly;
  if Result then
  begin
    mBlock := AView.Block;
    Result := (mBlock <> nil) and mBlock.IsValid and (mBlock.Size > 0);
  end;
end;

/// <summary>Bereiche der Markierung ABlock in ALines: einer, im Spaltenblock je Zeile der Ausschnitt zwischen den
/// Spalten (zu kurze Zeilen bleiben, wie sie sind).</summary>
function BlockRanges(const ABlock: IOTAEditBlock; const ALines: TArray<string>; ATabWidth: Integer):
  TArray<TLspRange>;
var
  mRow, mFirstColumn, mLastColumn: Integer;
  mStart, mStop: TLspTextPosition;
begin
  if ABlock.Style <> btColumn then
  begin
    mStart := PositionOf(ALines, ABlock.StartingRow, ABlock.StartingColumn, ATabWidth);
    mStop := PositionOf(ALines, ABlock.EndingRow, ABlock.EndingColumn, ATabWidth);
    Result := [TLspRange.Create(mStart.Line, mStart.Character, mStop.Line, mStop.Character)];
    Exit;
  end;
  Result := nil;
  mFirstColumn := Min(ABlock.StartingColumn, ABlock.EndingColumn);
  mLastColumn := Max(ABlock.StartingColumn, ABlock.EndingColumn);
  for mRow := ABlock.StartingRow to ABlock.EndingRow do
  begin
    mStart := PositionOf(ALines, mRow, mFirstColumn, ATabWidth);
    mStop := PositionOf(ALines, mRow, mLastColumn, ATabWidth);
    if mStart.Character < Length(LineOf(ALines, mRow)) then
    begin
      Result := Result + [TLspRange.Create(mStart.Line, mStart.Character, mStop.Line, mStop.Character)];
    end;
  end;
end;

/// <summary>Schreibt AWrapped in den Puffer von AView (Text AText) und legt die Markierung wieder auf den
/// ursprünglichen Text, als Spaltenblock, wenn AColumn.</summary>
procedure WriteWrapped(const AView: IOTAEditView; const AText: string; const AWrapped: TAtlasWrapResult;
  AColumn: Boolean; ATabWidth: Integer);
var
  mLineBreak, mInsert: string;
  mStart, mOldLength: Integer;
begin
  mLineBreak := #10;
  if Pos(#13#10, AText) > 0 then
  begin
    mLineBreak := #13#10;
  end;
  if TAtlasLineMover.Difference(AText, string.Join(mLineBreak, AWrapped.Lines), mStart, mOldLength, mInsert) then
  begin
    WriteBuffer(AView.Buffer, AText, mStart, mOldLength, mInsert);
  end;
  if AColumn then
  begin
    AView.Block.Style := btColumn;
  end
  else
  begin
    AView.Block.Style := btNonInclusive;
  end;
  AView.CursorPos := EditPos(AWrapped.Lines, AWrapped.Selections[0].StartPos, ATabWidth);
  AView.Block.BeginBlock;
  AView.CursorPos := EditPos(AWrapped.Lines, AWrapped.Selections[High(AWrapped.Selections)].EndPos, ATabWidth);
  AView.Block.EndBlock;
  AView.MoveViewToCursor;
  AView.Paint;
end;

{ TAtlasIdeWrapSelection }

constructor TAtlasIdeWrapSelection.Create(const ABusy: TFunc<Boolean>);
begin
  inherited Create;
  FBusy := ABusy;
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
end;

destructor TAtlasIdeWrapSelection.Destroy;
begin
  FreeAndNil(FMessages);
  FBusy := nil;
  inherited;
end;

class procedure TAtlasIdeWrapSelection.Install(const ABusy: TFunc<Boolean>);
begin
  if FInstance = nil then
  begin
    FInstance := TAtlasIdeWrapSelection.Create(ABusy);
  end;
end;

class procedure TAtlasIdeWrapSelection.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeWrapSelection.Enabled: Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.Enabled and mSettings.WrapSelection;
end;

class function TAtlasIdeWrapSelection.Chars: string;
begin
  Result := TAtlasWrapSelection.Normalize(TAtlasIdeSettings.Current.WrapSelectionChars);
end;

procedure TAtlasIdeWrapSelection.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  mTyped: Char;
begin
  if Handled or (Msg.message <> WM_CHAR) or TAtlasGuard.Disabled(TAtlasFeature.WrapSelection) then
  begin
    Exit;
  end;
  try
    mTyped := Char(Msg.wParam);
    if not IsEditorWindow(Msg.hwnd) or not Enabled or not TAtlasWrapSelection.Accepts(mTyped, Chars) then
    begin
      Exit;
    end;
    if Assigned(FBusy) and FBusy() then
    begin
      Exit;
    end;
    Handled := Run(mTyped);
  except
    // Keine Exception an die IDE (#493); das Zeichen geht dann normal weiter.
    on E: Exception do
    begin
      Handled := False;
      TAtlasGuard.Report(TAtlasFeature.WrapSelection, E);
    end;
  end;
end;

class function TAtlasIdeWrapSelection.Run(AOpen: Char): Boolean;
var
  mView: IOTAEditView;
  mText: string;
  mLines: TArray<string>;
  mWrapped: TAtlasWrapResult;
  mTabWidth: Integer;
  mColumn: Boolean;
begin
  Result := False;
  mView := TAtlasEditorBuffer.ActiveView;
  // Ohne Markierung bleibt alles wie in der IDE.
  if not WritableSelection(mView) then
  begin
    Exit;
  end;
  mText := TAtlasEditorBuffer.Text(mView.Buffer);
  mLines := mText.Split([#13#10, #10]);
  mTabWidth := TAtlasEditorBuffer.TabWidth(mView.Buffer);
  mColumn := mView.Block.Style = btColumn;
  Result := TAtlasWrapSelection.Wrap(mLines, BlockRanges(mView.Block, mLines, mTabWidth), AOpen, Chars, mWrapped);
  if Result then
  begin
    WriteWrapped(mView, mText, mWrapped, mColumn, mTabWidth);
  end;
end;

end.
