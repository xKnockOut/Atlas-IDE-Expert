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
  Control: TWinControl;
begin
  Control := FindControl(AWnd);
  Result := (Control <> nil) and Control.ClassNameIs('TEditControl');
end;

/// <summary>Ersetzt in ABuffer (Text AText) ab Zeichen AStart AOldLength Zeichen durch AInsert; ein
/// Rückgängig-Schritt.</summary>
procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText: string; AStart, AOldLength: Integer;
  const AInsert: string);
var
  Writer: IOTAEditWriter;
begin
  Writer := ABuffer.CreateUndoableWriter;
  Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart)));
  Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, AStart + AOldLength)));
  if AInsert <> '' then
    Writer.Insert(PAnsiChar(UTF8Encode(AInsert)));
  Writer := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function LineOf(const ALines: TArray<string>; ARow: Integer): string;
begin
  Result := '';
  if (ARow >= 1) and (ARow <= Length(ALines)) then
    Result := ALines[ARow - 1];
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
    FInstance := TAtlasIdeWrapSelection.Create(ABusy);
end;

class procedure TAtlasIdeWrapSelection.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeWrapSelection.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.WrapSelection;
end;

class function TAtlasIdeWrapSelection.Chars: string;
begin
  Result := TAtlasWrapSelection.Normalize(TAtlasIdeSettings.Current.WrapSelectionChars);
end;

procedure TAtlasIdeWrapSelection.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  Typed: Char;
begin
  if Handled or (Msg.message <> WM_CHAR) or TAtlasGuard.Disabled(TAtlasFeature.WrapSelection) then
    Exit;
  try
    Typed := Char(Msg.wParam);
    if not IsEditorWindow(Msg.hwnd) or not Enabled or not TAtlasWrapSelection.Accepts(Typed, Chars) then
      Exit;
    if Assigned(FBusy) and FBusy() then
      Exit;
    Handled := Run(Typed);
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
  View: IOTAEditView;
  Buffer: IOTAEditBuffer;
  Block: IOTAEditBlock;
  Text, NewText, LineBreak, Insert: string;
  Lines: TArray<string>;
  Ranges: TArray<TLspRange>;
  Wrapped: TAtlasWrapResult;
  TabWidth, Row, FirstColumn, LastColumn, Start, OldLength: Integer;
  StartPos, StopPos: TLspTextPosition;
  Column: Boolean;
begin
  Result := False;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  Buffer := View.Buffer;
  Block := View.Block;
  // Ohne Markierung bleibt alles wie in der IDE.
  if Buffer.IsReadOnly or (Block = nil) or not Block.IsValid or (Block.Size = 0) then
    Exit;
  Text := TAtlasEditorBuffer.Text(Buffer);
  LineBreak := #10;
  if Pos(#13#10, Text) > 0 then
    LineBreak := #13#10;
  Lines := Text.Split([#13#10, #10]);
  TabWidth := TAtlasEditorBuffer.TabWidth(Buffer);
  Column := Block.Style = btColumn;
  Ranges := nil;
  if Column then
  begin
    // Spaltenblock: je Zeile der Ausschnitt zwischen den Spalten; zu kurze Zeilen bleiben, wie sie sind.
    FirstColumn := Min(Block.StartingColumn, Block.EndingColumn);
    LastColumn := Max(Block.StartingColumn, Block.EndingColumn);
    for Row := Block.StartingRow to Block.EndingRow do
    begin
      StartPos := PositionOf(Lines, Row, FirstColumn, TabWidth);
      StopPos := PositionOf(Lines, Row, LastColumn, TabWidth);
      if StartPos.Character < Length(LineOf(Lines, Row)) then
        Ranges := Ranges + [TLspRange.Create(StartPos.Line, StartPos.Character, StopPos.Line, StopPos.Character)];
    end;
  end
  else
  begin
    StartPos := PositionOf(Lines, Block.StartingRow, Block.StartingColumn, TabWidth);
    StopPos := PositionOf(Lines, Block.EndingRow, Block.EndingColumn, TabWidth);
    Ranges := [TLspRange.Create(StartPos.Line, StartPos.Character, StopPos.Line, StopPos.Character)];
  end;
  if not TAtlasWrapSelection.Wrap(Lines, Ranges, AOpen, Chars, Wrapped) then
    Exit;
  NewText := string.Join(LineBreak, Wrapped.Lines);
  if TAtlasLineMover.Difference(Text, NewText, Start, OldLength, Insert) then
    WriteBuffer(Buffer, Text, Start, OldLength, Insert);
  // Markierung wieder auf dem ursprünglichen Text.
  StartPos := Wrapped.Selections[0].StartPos;
  StopPos := Wrapped.Selections[High(Wrapped.Selections)].EndPos;
  if Column then
    View.Block.Style := btColumn
  else
    View.Block.Style := btNonInclusive;
  View.CursorPos := EditPos(Wrapped.Lines, StartPos, TabWidth);
  View.Block.BeginBlock;
  View.CursorPos := EditPos(Wrapped.Lines, StopPos, TabWidth);
  View.Block.EndBlock;
  View.MoveViewToCursor;
  View.Paint;
  Result := True;
end;

end.
