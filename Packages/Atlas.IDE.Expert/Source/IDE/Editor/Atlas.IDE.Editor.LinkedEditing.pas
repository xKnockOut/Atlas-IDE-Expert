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
  System.Generics.Collections,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.LinkedEditing;

type
  TAtlasLinkedSessionFunc = reference to function: TLspSession;
  /// <summary>Statusfeld setzen; AText '' entfernt es.</summary>
  TAtlasLinkedStatusProc = reference to procedure(const AText, AHint: string);

  TAtlasIdeLinkedEditing = class
  private const
    TickMs = 100;
    /// <summary>So viele Takte ohne Bewegung, bevor Atlas den Server fragt.</summary>
    IdleTicks = 2;
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;

    /// <summary>Letzte Antwort des Servers und der Text, für den sie gilt.</summary>
    TCandidate = record
      Valid: Boolean;
      FileName: string;
      Text: string;
      Ranges: TAtlasLinkedRanges;
      Conflicts: TAtlasLinkedConflicts;
    end;
  private class var
    FInstance: TAtlasIdeLinkedEditing;
  private
    FBusy: TFunc<Boolean>;
    FSession: TAtlasLinkedSessionFunc;
    FStatus: TAtlasLinkedStatusProc;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FMessages: TApplicationEvents;
    FTimer: TTimer;
    FWorkers: TList<TThread>;
    FRequest: Integer;
    FIdleKey: string;
    FIdleCount: Integer;
    FAskedKey: string;
    FCandidate: TCandidate;
    // Laufende Sitzung: Ansicht, bekannter Text, Vorkommen ([FPrimary] wird bearbeitet), Stand zu Beginn.
    FView: IOTAEditView;
    FText: string;
    FLines: TArray<string>;
    FRanges: TAtlasLinkedRanges;
    FPrimary: Integer;
    FConflicts: TAtlasLinkedConflicts;
    FOriginal: string;
    FOriginalText: string;
    FOriginalRanges: TAtlasLinkedRanges;
    // Der eigene Schritt oben in der Rückgängig-Liste enthält die ganze Sitzung.
    FGrouped: Boolean;
    FProblem: TAtlasLinkedProblem;
    FDetail: string;
    FWriting: Boolean;
    FHighSurrogate: Char;
    function IsBusy: Boolean;
    function IsActive: Boolean;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure KeyDown(const Msg: TMsg; var Handled: Boolean);
    procedure CharTyped(const Msg: TMsg; var Handled: Boolean);
    procedure TimerTick(Sender: TObject);
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    /// <summary>Ruht der Cursor, den Server fragen (nur ohne Sitzung).</summary>
    procedure WatchIdle;
    procedure Ask(const AView: IOTAEditView; ALine, ACharacter: Integer);
    procedure Accept(ARequest: Integer; const AFileName, AText: string; const ARanges: TAtlasLinkedRanges;
      const AConflicts: TAtlasLinkedConflicts);
    procedure ReapWorkers(AWait: Boolean);
    /// <summary>Sitzung mit der letzten Antwort beginnen; False, wenn sie nicht mehr gilt.</summary>
    function Start(const AView: IOTAEditView): Boolean;
    /// <summary>Taste im Namen ausführen; False gibt sie an die IDE (und beendet die Sitzung).</summary>
    function Edit(AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
    /// <summary>Fremde Änderung: nur am bearbeiteten Namen, dann die übrigen nachziehen; sonst False.</summary>
    function Follow(const AText: string): Boolean;
    /// <summary>Esc bei Konflikt: alten Namen wiederherstellen.</summary>
    procedure Restore;
    procedure Reconcile;
    /// <summary>AName in die Bereiche ARanges von ABase schreiben (ein Schreiber), ASkip ausgenommen.</summary>
    procedure WriteNames(const ABuffer: IOTAEditBuffer; const ABase: string; const ARanges: TAtlasLinkedRanges;
      const AName: string; ASkip: Integer);
    procedure SetState(const AText: string; const ARanges: TAtlasLinkedRanges);
    procedure UpdateProblem;
    procedure Refresh;
    procedure Finish;
    class procedure ReadCaret(const AView: IOTAEditView; out ALine, ACharacter: Integer); static;
    class procedure WriteCaret(const AView: IOTAEditView; const ALines: TArray<string>; ALine,
      ACharacter: Integer); static;
    class function HasBlock(const AView: IOTAEditView): Boolean; static;
    class procedure Invalidate; static;
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
  System.JSON,
  Vcl.Forms,
  Vcl.Graphics,
  Atlas.Text.Chars,
  Atlas.Text.Lines,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.EditorStyle;

function CurrentShift: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_SHIFT) < 0 then
    Include(Result, ssShift);
  if GetKeyState(VK_CONTROL) < 0 then
    Include(Result, ssCtrl);
  if GetKeyState(VK_MENU) < 0 then
    Include(Result, ssAlt);
end;

function IsEditorWindow(AWnd: HWND): Boolean;
var
  Control: TWinControl;
begin
  Control := FindControl(AWnd);
  Result := (Control <> nil) and Control.ClassNameIs('TEditControl');
end;

function LineOf(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine < Length(ALines)) then
    Result := ALines[ALine];
end;

/// <summary>Steht an oder vor ACharacter ein Zeichen eines Bezeichners?</summary>
function NearIdentifier(const ALine: string; ACharacter: Integer): Boolean;
begin
  Result := ((ACharacter < Length(ALine)) and TTextChars.IsIdentChar(ALine[ACharacter + 1])) or
    ((ACharacter > 0) and (ACharacter <= Length(ALine)) and TTextChars.IsIdentChar(ALine[ACharacter]));
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

{ TAtlasIdeLinkedEditing }

constructor TAtlasIdeLinkedEditing.Create(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
  const AStatus: TAtlasLinkedStatusProc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FBusy := ABusy;
  FSession := ASession;
  FStatus := AStatus;
  FIndex := -1;
  FPrimary := -1;
  FWorkers := TList<TThread>.Create;
  FMessages := TApplicationEvents.Create(nil);
  FMessages.OnMessage := AppMessage;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := TickMs;
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
end;

destructor TAtlasIdeLinkedEditing.Destroy;
var
  Services: INTACodeEditorServices;
begin
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  FreeAndNil(FMessages);
  FreeAndNil(FTimer);
  // Laufende Anfragen halten die Sitzung als rohen Zeiger: abwarten.
  ReapWorkers(True);
  FreeAndNil(FWorkers);
  if Assigned(FStatus) and IsActive then
    FStatus('', '');
  FView := nil;
  FRanges := nil;
  FCandidate := Default(TCandidate);
  inherited;
end;

class procedure TAtlasIdeLinkedEditing.Install(const ABusy: TFunc<Boolean>; const ASession: TAtlasLinkedSessionFunc;
  const AStatus: TAtlasLinkedStatusProc);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeLinkedEditing.Create(ABusy, ASession, AStatus);
end;

class procedure TAtlasIdeLinkedEditing.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeLinkedEditing.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and Settings.LinkedEditing;
end;

class function TAtlasIdeLinkedEditing.Active: Boolean;
begin
  Result := (FInstance <> nil) and FInstance.IsActive;
end;

function TAtlasIdeLinkedEditing.IsActive: Boolean;
begin
  Result := Length(FRanges) > 0;
end;

function TAtlasIdeLinkedEditing.IsBusy: Boolean;
begin
  Result := Assigned(FBusy) and FBusy();
end;

class procedure TAtlasIdeLinkedEditing.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

class procedure TAtlasIdeLinkedEditing.ReadCaret(const AView: IOTAEditView; out ALine, ACharacter: Integer);
var
  Cursor: TOTAEditPos;
  LineText: string;
begin
  Cursor := AView.CursorPos;
  ALine := Max(0, Cursor.Line - 1);
  LineText := TAtlasEditorBuffer.LineText(AView, ALine + 1);
  ACharacter := Min(TLspSession.ColumnToIndex(LineText, Cursor.Col, TAtlasEditorBuffer.TabWidth(AView.Buffer)),
    Length(LineText));
end;

class procedure TAtlasIdeLinkedEditing.WriteCaret(const AView: IOTAEditView; const ALines: TArray<string>; ALine,
  ACharacter: Integer);
var
  Position: TOTAEditPos;
begin
  AView.Block.Reset;
  Position.Line := ALine + 1;
  Position.Col := TLspSession.IndexToColumn(LineOf(ALines, ALine), ACharacter,
    TAtlasEditorBuffer.TabWidth(AView.Buffer));
  AView.CursorPos := Position;
  AView.MoveViewToCursor;
  AView.Paint;
end;

class function TAtlasIdeLinkedEditing.HasBlock(const AView: IOTAEditView): Boolean;
var
  Block: IOTAEditBlock;
begin
  Block := AView.Block;
  Result := (Block <> nil) and Block.IsValid and (Block.Size > 0);
end;

procedure TAtlasIdeLinkedEditing.ReapWorkers(AWait: Boolean);
var
  Index: Integer;
begin
  if FWorkers = nil then
    Exit;
  for Index := FWorkers.Count - 1 downto 0 do
    if AWait or FWorkers[Index].Finished then
    begin
      FWorkers[Index].WaitFor;
      FWorkers[Index].Free;
      FWorkers.Delete(Index);
    end;
end;

procedure TAtlasIdeLinkedEditing.Ask(const AView: IOTAEditView; ALine, ACharacter: Integer);
var
  Session: TLspSession;
  FileName, Text: string;
  Request: Integer;
  Worker: TThread;
begin
  if not Assigned(FSession) then
    Exit;
  Session := FSession();
  if Session = nil then
    Exit;
  // Im Hauptthread: Die Sitzung führt ihre Dokumentstände nicht threadsicher.
  FileName := AView.Buffer.FileName;
  Text := TAtlasEditorBuffer.Text(AView.Buffer);
  Session.Sync(FileName, Text);
  ReapWorkers(False);
  Inc(FRequest);
  Request := FRequest;
  Worker := TThread.CreateAnonymousThread(
    procedure
    var
      Answer: TJSONValue;
      Ranges: TAtlasLinkedRanges;
      Conflicts: TAtlasLinkedConflicts;
    begin
      Ranges := nil;
      Conflicts := nil;
      try
        Answer := Session.LinkedLocals(FileName, ALine, ACharacter);
        try
          TAtlasLinkedEditing.FromJson(Answer, Ranges, Conflicts);
        finally
          Answer.Free;
        end;
      except
        // Server langsam oder weg: keine Sitzung, die Taste geht an die IDE.
        Ranges := nil;
      end;
      // Atlas gehört der Eintrag: beim Entladen verworfen (Code-Review A-02).
      TAtlasMainThread.Queue(TAtlasFeature.LinkedEditing,
        procedure
        begin
          if FInstance <> nil then
            TAtlasGuard.Run(TAtlasFeature.LinkedEditing,
              procedure
              begin
                if FInstance <> nil then
                  FInstance.Accept(Request, FileName, Text, Ranges, Conflicts);
              end);
        end);
    end);
  Worker.FreeOnTerminate := False;
  FWorkers.Add(Worker);
  Worker.Start;
end;

procedure TAtlasIdeLinkedEditing.Accept(ARequest: Integer; const AFileName, AText: string;
  const ARanges: TAtlasLinkedRanges; const AConflicts: TAtlasLinkedConflicts);
begin
  // Nur die jüngste Antwort zählt.
  if ARequest <> FRequest then
    Exit;
  FCandidate.Valid := Length(ARanges) > 0;
  FCandidate.FileName := AFileName;
  FCandidate.Text := AText;
  FCandidate.Ranges := ARanges;
  FCandidate.Conflicts := AConflicts;
end;

procedure TAtlasIdeLinkedEditing.WatchIdle;
var
  View: IOTAEditView;
  Line, Character: Integer;
  LineText, Key: string;
begin
  if not Enabled or IsBusy or not Application.Active then
    Exit;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) or View.Buffer.IsReadOnly then
    Exit;
  ReadCaret(View, Line, Character);
  LineText := TAtlasEditorBuffer.LineText(View, Line + 1);
  Key := Format('%s|%d|%d|', [View.Buffer.FileName, Line, Character]) + LineText;
  if Key <> FIdleKey then
  begin
    FIdleKey := Key;
    FIdleCount := 0;
    Exit;
  end;
  Inc(FIdleCount);
  if (FIdleCount <> IdleTicks) or (Key = FAskedKey) or not NearIdentifier(LineText, Character) then
    Exit;
  // Die letzte Antwort deckt den Cursor noch ab; jede Änderung am Text verwirft sie (EditorModified).
  if FCandidate.Valid and SameText(FCandidate.FileName, View.Buffer.FileName) and
    (TAtlasLinkedEditing.IndexAt(FCandidate.Ranges, Line, Character) >= 0) then
    Exit;
  FAskedKey := Key;
  FCandidate.Valid := False;
  Ask(View, Line, Character);
end;

function TAtlasIdeLinkedEditing.Start(const AView: IOTAEditView): Boolean;
var
  Text: string;
  Lines: TArray<string>;
  Line, Character, Primary: Integer;
begin
  Result := False;
  if not Enabled or IsBusy or not FCandidate.Valid or (AView = nil) or (AView.Buffer = nil) or
    AView.Buffer.IsReadOnly or not SameText(FCandidate.FileName, AView.Buffer.FileName) or HasBlock(AView) then
    Exit;
  Text := TAtlasEditorBuffer.Text(AView.Buffer);
  if Text <> FCandidate.Text then
    Exit;
  Lines := TTextLines.SplitLines(Text);
  if not TAtlasLinkedEditing.Matches(Lines, FCandidate.Ranges) then
    Exit;
  ReadCaret(AView, Line, Character);
  Primary := TAtlasLinkedEditing.IndexAt(FCandidate.Ranges, Line, Character);
  if Primary < 0 then
    Exit;
  FView := AView;
  FPrimary := Primary;
  FConflicts := FCandidate.Conflicts;
  FOriginalText := Text;
  FOriginalRanges := Copy(FCandidate.Ranges);
  SetState(Text, FCandidate.Ranges);
  FOriginal := TAtlasLinkedEditing.NameOf(FLines, FRanges[FPrimary]);
  FGrouped := False;
  FProblem := TAtlasLinkedProblem.None;
  FDetail := '';
  FCandidate.Valid := False;
  Result := True;
end;

procedure TAtlasIdeLinkedEditing.SetState(const AText: string; const ARanges: TAtlasLinkedRanges);
begin
  FText := AText;
  FLines := TTextLines.SplitLines(AText);
  FRanges := Copy(ARanges);
end;

procedure TAtlasIdeLinkedEditing.WriteNames(const ABuffer: IOTAEditBuffer; const ABase: string;
  const ARanges: TAtlasLinkedRanges; const AName: string; ASkip: Integer);
var
  Table: TLineTable;
  Starts: TList<Integer>;
  Lengths: TDictionary<Integer, Integer>;
  Index, Offset: Integer;
  Writer: IOTAEditWriter;
  Utf8: UTF8String;
begin
  Table := TLineTable.Build(ABase);
  Starts := TList<Integer>.Create;
  Lengths := TDictionary<Integer, Integer>.Create;
  FWriting := True;
  try
    for Index := 0 to High(ARanges) do
      if Index <> ASkip then
      begin
        Offset := Table.LineStart(ARanges[Index].Line) + ARanges[Index].Character;
        if not Lengths.ContainsKey(Offset) then
        begin
          Starts.Add(Offset);
          Lengths.Add(Offset, ARanges[Index].Length);
        end;
      end;
    Starts.Sort;
    Utf8 := UTF8Encode(AName);
    // Ein Schreiber: ein Rückgängig-Schritt; nur die Namen, der Text dazwischen bleibt unberührt.
    Writer := ABuffer.CreateUndoableWriter;
    for Offset in Starts do
    begin
      Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(ABase, 1, Offset)));
      Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(ABase, 1, Offset + Lengths[Offset])));
      if Utf8 <> '' then
        Writer.Insert(PAnsiChar(Utf8));
    end;
    Writer := nil;
  finally
    FWriting := False;
    Lengths.Free;
    Starts.Free;
  end;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

function TAtlasIdeLinkedEditing.Edit(AKind: TAtlasLinkedKey; const AInsert: string): Boolean;
var
  View: IOTAEditView;
  Buffer: IOTAEditBuffer;
  Text, Name, NewName, Base, NewText: string;
  Line, Character, NewOffset: Integer;
  Range: TAtlasLinkedRange;
  BaseRanges, NewRanges: TAtlasLinkedRanges;
  Grouped: Boolean;
begin
  Result := False;
  View := TAtlasEditorBuffer.ActiveView;
  if (View = nil) or (View.Buffer = nil) then
    Exit;
  if IsActive and not SameText(View.Buffer.FileName, FView.Buffer.FileName) then
    Finish;
  if not IsActive and not Start(View) then
    Exit;
  Buffer := View.Buffer;
  // Mit Markierung ersetzt die Taste die Markierung: das bleibt der IDE.
  if HasBlock(View) then
  begin
    Finish;
    Exit;
  end;
  Text := TAtlasEditorBuffer.Text(Buffer);
  if (Text <> FText) and not Follow(Text) then
  begin
    Finish;
    Exit;
  end;
  ReadCaret(View, Line, Character);
  Range := FRanges[FPrimary];
  Name := TAtlasLinkedEditing.NameOf(FLines, Range);
  if not Range.Contains(Line, Character) or
    not TAtlasLinkedEditing.Key(Name, Character - Range.Character, AKind, AInsert, NewName, NewOffset) then
  begin
    Finish;
    Exit;
  end;
  // Direkt auf den eigenen Schritt: zurücknehmen und die ganze Sitzung als einen Schritt schreiben.
  Base := FText;
  BaseRanges := FRanges;
  if FGrouped then
  begin
    if Buffer.Undo and (TAtlasEditorBuffer.Text(Buffer) = FOriginalText) then
    begin
      Base := FOriginalText;
      BaseRanges := FOriginalRanges;
    end
    else
    begin
      if TAtlasEditorBuffer.Text(Buffer) <> FText then
        Buffer.Redo;
      // Lässt sich der Stand nicht wiederherstellen, lieber nichts ändern.
      if TAtlasEditorBuffer.Text(Buffer) <> FText then
      begin
        Finish;
        Result := True;
        Exit;
      end;
    end;
  end;
  if not TAtlasLinkedEditing.Rename(Base, BaseRanges, NewName, NewText, NewRanges) then
  begin
    Finish;
    Exit;
  end;
  // Ein Schritt ab dem Stand zu Beginn enthält die ganze Sitzung.
  Grouped := Base = FOriginalText;
  WriteNames(Buffer, Base, BaseRanges, NewName, -1);
  if TAtlasEditorBuffer.Text(Buffer) <> NewText then
  begin
    // Der Puffer sieht anders aus als gerechnet: Sitzung beenden, nichts weiter schreiben.
    Finish;
    Result := True;
    Exit;
  end;
  FGrouped := Grouped;
  SetState(NewText, NewRanges);
  WriteCaret(View, FLines, FRanges[FPrimary].Line, FRanges[FPrimary].Character + NewOffset);
  UpdateProblem;
  Refresh;
  Result := True;
end;

function TAtlasIdeLinkedEditing.Follow(const AText: string): Boolean;
var
  Lines: TArray<string>;
  Index, Line: Integer;
  Name, NewText: string;
  Ranges, NewRanges: TAtlasLinkedRanges;
begin
  Result := False;
  if not IsActive then
    Exit;
  Lines := TTextLines.SplitLines(AText);
  Line := FRanges[FPrimary].Line;
  if Length(Lines) <> Length(FLines) then
    Exit;
  for Index := 0 to High(Lines) do
    if (Index <> Line) and (Lines[Index] <> FLines[Index]) then
      Exit;
  if not TAtlasLinkedEditing.Follow(FLines[Line], Lines[Line], FRanges[FPrimary], Name) or
    not TAtlasLinkedEditing.IsName(Name) then
    Exit;
  Ranges := TAtlasLinkedEditing.Resized(FRanges, FPrimary, Length(Name));
  if not TAtlasLinkedEditing.Rename(AText, Ranges, Name, NewText, NewRanges) then
    Exit;
  // Die Änderung der IDE liegt jetzt oben in der Rückgängig-Liste: ab hier ein Schritt je Taste.
  WriteNames(FView.Buffer, AText, Ranges, Name, FPrimary);
  if TAtlasEditorBuffer.Text(FView.Buffer) <> NewText then
    Exit;
  FGrouped := False;
  SetState(NewText, NewRanges);
  UpdateProblem;
  Result := True;
end;

procedure TAtlasIdeLinkedEditing.Restore;
var
  Buffer: IOTAEditBuffer;
  Text: string;
begin
  if not IsActive or (FView = nil) or (FView.Buffer = nil) then
    Exit;
  Buffer := FView.Buffer;
  Text := TAtlasEditorBuffer.Text(Buffer);
  if FGrouped and (Text = FText) and Buffer.Undo and (TAtlasEditorBuffer.Text(Buffer) = FOriginalText) then
  begin
    SetState(FOriginalText, FOriginalRanges);
    WriteCaret(FView, FLines, FRanges[FPrimary].Line, FRanges[FPrimary].EndCharacter);
    Exit;
  end;
  if TAtlasEditorBuffer.Text(Buffer) <> FText then
    Buffer.Redo;
  if TAtlasEditorBuffer.Text(Buffer) = FText then
  begin
    WriteNames(Buffer, FText, FRanges, FOriginal, -1);
    WriteCaret(FView, TTextLines.SplitLines(TAtlasEditorBuffer.Text(Buffer)), FRanges[FPrimary].Line,
      FRanges[FPrimary].Character + Length(FOriginal));
  end;
end;

procedure TAtlasIdeLinkedEditing.Reconcile;
var
  Text: string;
begin
  if not IsActive or (FView = nil) or (FView.Buffer = nil) then
    Exit;
  Text := TAtlasEditorBuffer.Text(FView.Buffer);
  if Text = FText then
    Exit;
  if Follow(Text) then
    Refresh
  else
    Finish;
end;

procedure TAtlasIdeLinkedEditing.UpdateProblem;
begin
  FProblem := TAtlasLinkedEditing.Problem(TAtlasLinkedEditing.NameOf(FLines, FRanges[FPrimary]), FOriginal,
    FConflicts, FDetail);
end;

procedure TAtlasIdeLinkedEditing.Refresh;
var
  Text, Hint: string;
begin
  if not IsActive then
    Exit;
  if Assigned(FStatus) then
  begin
    Text := TAtlasStrings.Fmt(TAtlasTextId.LinkedEditingCount, [Length(FRanges)]);
    Hint := '';
    case FProblem of
      TAtlasLinkedProblem.Reserved:
        Hint := TAtlasStrings.Fmt(TAtlasTextId.LinkedEditingReserved,
          [TAtlasLinkedEditing.NameOf(FLines, FRanges[FPrimary])]);
      TAtlasLinkedProblem.Visible:
        Hint := TAtlasStrings.Fmt(TAtlasTextId.LinkedEditingVisible, [FDetail]);
    end;
    if Hint <> '' then
    begin
      Text := Hint;
      Hint := TAtlasStrings.Text(TAtlasTextId.LinkedEditingRestoreHint);
    end;
    FStatus(Text, Hint);
  end;
  Invalidate;
end;

procedure TAtlasIdeLinkedEditing.Finish;
var
  Was: Boolean;
begin
  Was := IsActive;
  FRanges := nil;
  FOriginalRanges := nil;
  FConflicts := nil;
  FLines := nil;
  FText := '';
  FOriginalText := '';
  FOriginal := '';
  FView := nil;
  FPrimary := -1;
  FGrouped := False;
  FProblem := TAtlasLinkedProblem.None;
  FDetail := '';
  FHighSurrogate := #0;
  if Was then
  begin
    if Assigned(FStatus) then
      FStatus('', '');
    Invalidate;
  end;
end;

class procedure TAtlasIdeLinkedEditing.Dismiss;
begin
  if FInstance <> nil then
  begin
    FInstance.Finish;
    FInstance.FCandidate.Valid := False;
  end;
end;

class procedure TAtlasIdeLinkedEditing.EditorModified(const AView: IOTAEditView);
begin
  if (FInstance = nil) or FInstance.FWriting then
    Exit;
  // Ohne Sitzung gilt die letzte Antwort nicht mehr; beim nächsten Ruhen fragt Atlas neu.
  if not FInstance.IsActive then
  begin
    FInstance.FCandidate.Valid := False;
    FInstance.FAskedKey := '';
    Exit;
  end;
  if (AView = nil) or
    (AView.Buffer = nil) or (FInstance.FView = nil) or
    not SameText(AView.Buffer.FileName, FInstance.FView.Buffer.FileName) then
    Exit;
  // Nie im Notifier schreiben: nach der Änderung, in der Warteschlange des Hauptthreads.
  TAtlasMainThread.ForceQueue(TAtlasFeature.LinkedEditing,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.LinkedEditing,
        procedure
        begin
          if FInstance <> nil then
            FInstance.Reconcile;
        end);
    end);
end;

procedure TAtlasIdeLinkedEditing.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
    Exit;
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

procedure TAtlasIdeLinkedEditing.KeyDown(const Msg: TMsg; var Handled: Boolean);
var
  Key: Word;
begin
  if not IsEditorWindow(Msg.hwnd) then
    Exit;
  if not Enabled or IsBusy then
  begin
    Finish;
    Exit;
  end;
  Key := Word(Msg.wParam);
  // Mit Strg, Alt oder Umschalt (Wort löschen, Rückgängig ...) arbeitet die IDE; Follow bzw. der Takt ziehen nach.
  if (Key = VK_SHIFT) or (Key = VK_CONTROL) or (Key = VK_MENU) or (CurrentShift <> []) then
    Exit;
  case Key of
    VK_ESCAPE:
      if IsActive then
      begin
        if FProblem <> TAtlasLinkedProblem.None then
          Restore;
        Finish;
        Handled := True;
      end;
    VK_RETURN:
      if IsActive then
      begin
        Finish;
        Handled := True;
      end;
    VK_BACK:
      Handled := Edit(TAtlasLinkedKey.Backspace, '');
    VK_DELETE:
      Handled := Edit(TAtlasLinkedKey.Delete, '');
  end;
end;

procedure TAtlasIdeLinkedEditing.CharTyped(const Msg: TMsg; var Handled: Boolean);
var
  Typed: Char;
  Pair: string;
begin
  if not IsEditorWindow(Msg.hwnd) or not Enabled or IsBusy then
    Exit;
  Typed := Char(Msg.wParam);
  if (Typed < ' ') or (Typed = #127) then
    Exit;
  // Zeichen außerhalb der Grundebene kommen als zwei WM_CHAR; nur in einer laufenden Sitzung.
  if (Typed >= #$D800) and (Typed <= #$DBFF) then
  begin
    if IsActive then
    begin
      FHighSurrogate := Typed;
      Handled := True;
    end;
    Exit;
  end;
  if (FHighSurrogate <> #0) and (Typed >= #$DC00) and (Typed <= #$DFFF) then
  begin
    Pair := FHighSurrogate + Typed;
    FHighSurrogate := #0;
    Handled := True;
    if not Edit(TAtlasLinkedKey.Insert, Pair) and (TAtlasEditorBuffer.ActiveView <> nil) then
      TAtlasEditorBuffer.ActiveView.Position.InsertText(Pair);
    Exit;
  end;
  FHighSurrogate := #0;
  if not TTextChars.IsIdentChar(Typed) then
  begin
    // Leerzeichen, Punkt, Klammer ...: Sitzung zu Ende, das Zeichen schreibt die IDE.
    Finish;
    Exit;
  end;
  Handled := Edit(TAtlasLinkedKey.Insert, Typed);
end;

procedure TAtlasIdeLinkedEditing.TimerTick(Sender: TObject);
var
  View: IOTAEditView;
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Form: IOTAFormEditor;
  Line, Character: Integer;
begin
  try
    if TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
      Exit;
    ReapWorkers(False);
    if not IsActive then
    begin
      WatchIdle;
      Exit;
    end;
    if FWriting then
      Exit;
    View := TAtlasEditorBuffer.ActiveView;
    // Datei gewechselt, Formular angezeigt oder abgeschaltet: Sitzung zu Ende.
    if (View = nil) or (View.Buffer = nil) or (FView = nil) or
      not SameText(View.Buffer.FileName, FView.Buffer.FileName) or not Enabled or IsBusy then
    begin
      Finish;
      Exit;
    end;
    if Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    begin
      Module := Modules.CurrentModule;
      if (Module <> nil) and Supports(Module.CurrentEditor, IOTAFormEditor, Form) then
      begin
        Finish;
        Exit;
      end;
    end;
    // Eine Änderung, deren Meldung noch aussteht, zuerst nachziehen.
    if TAtlasEditorBuffer.LineText(View, FRanges[FPrimary].Line + 1) <> FLines[FRanges[FPrimary].Line] then
      Reconcile;
    if not IsActive then
      Exit;
    // Cursor hat den Namen verlassen.
    ReadCaret(View, Line, Character);
    if not FRanges[FPrimary].Contains(Line, Character) then
      Finish;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LinkedEditing, E);
  end;
end;

procedure TAtlasIdeLinkedEditing.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  LineState: INTACodeEditorLineState;
  Text, Mark: string;
  Line, Index, TabWidth: Integer;
  Range: TAtlasLinkedRange;
  Color: COLORREF;
  DC: HDC;
  Saved: Integer;
  First, Last, Code, Frame: TRect;
  Brush: HBRUSH;
  Pen, OldPen: HPEN;
  OldBrush: HGDIOBJ;
  Font: TFont;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not IsActive or
    TAtlasGuard.Disabled(TAtlasFeature.LinkedEditing) then
    Exit;
  try
    if (FView = nil) or not SameText(Context.FileName, FView.Buffer.FileName) then
      Exit;
    LineState := Context.LineState;
    if LineState = nil then
      Exit;
    Line := Context.LogicalLineNum - 1;
    Text := LineOf(FLines, Line);
    // Nur, wenn die Zeile im Editor dem bekannten Stand entspricht (sonst steht gleich ein Reconcile an).
    if TrimRight(LineState.Text) <> TrimRight(Text) then
      Exit;
    TabWidth := TAtlasEditorBuffer.TabWidth(FView.Buffer);
    if FProblem = TAtlasLinkedProblem.None then
      Color := COLORREF(ColorToRGB(TColor(TAtlasIdeStyle.Colors.Accent)))
    else
      Color := COLORREF(ColorToRGB(TColor(TAtlasIdeStyle.Colors.Error)));
    DC := Context.Canvas.Handle;
    Code := LineState.CodeRect;
    Saved := SaveDC(DC);
    Brush := CreateSolidBrush(Color);
    Pen := CreatePen(PS_DOT, 1, Color);
    try
      if Code.Right > Code.Left then
        IntersectClipRect(DC, Code.Left, Rect.Top, Rect.Right, Rect.Bottom);
      for Index := 0 to High(FRanges) do
      begin
        Range := FRanges[Index];
        if Range.Line <> Line then
          Continue;
        First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Range.Character, TabWidth),
          Context.EditorLineNum);
        Last := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Range.EndCharacter,
          TabWidth), Context.EditorLineNum);
        // Ein leerer Name bleibt als schmaler Rahmen sichtbar.
        Frame := TRect.Create(First.Left - 1, Rect.Top, Max(Last.Left + 1, First.Left + 2), Rect.Bottom);
        if Index = FPrimary then
          FrameRect(DC, Frame, Brush)
        else
        begin
          OldPen := SelectObject(DC, Pen);
          OldBrush := SelectObject(DC, GetStockObject(NULL_BRUSH));
          Winapi.Windows.Rectangle(DC, Frame.Left, Frame.Top, Frame.Right, Frame.Bottom);
          SelectObject(DC, OldBrush);
          SelectObject(DC, OldPen);
        end;
      end;
      // Marke hinter der Zeile des bearbeiteten Vorkommens: Anzahl bzw. Konflikt.
      if FRanges[FPrimary].Line = Line then
      begin
        Mark := TAtlasStrings.Fmt(TAtlasTextId.LinkedEditingCount, [Length(FRanges)]);
        case FProblem of
          TAtlasLinkedProblem.Reserved:
            Mark := TAtlasStrings.Fmt(TAtlasTextId.LinkedEditingReserved,
              [TAtlasLinkedEditing.NameOf(FLines, FRanges[FPrimary])]);
          TAtlasLinkedProblem.Visible:
            Mark := TAtlasStrings.Fmt(TAtlasTextId.LinkedEditingVisible, [FDetail]);
        end;
        First := Context.EditorState.GetCharacterPosPx(TLspSession.IndexToColumn(Text, Length(Text), TabWidth) + 2,
          Context.EditorLineNum);
        Font := TFont.Create;
        try
          Font.Assign(Context.Canvas.Font);
          Context.Canvas.Font.Style := [fsItalic];
          Context.Canvas.Font.Color := TColor(Color);
          Context.Canvas.Brush.Style := bsClear;
          Context.Canvas.TextOut(First.Left, Rect.Top, Mark);
          Context.Canvas.Font.Assign(Font);
        finally
          Font.Free;
        end;
      end;
    finally
      DeleteObject(Pen);
      DeleteObject(Brush);
      RestoreDC(DC, Saved);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.LinkedEditing, E);
  end;
end;

end.
