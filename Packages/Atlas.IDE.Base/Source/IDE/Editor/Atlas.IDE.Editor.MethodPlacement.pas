unit Atlas.IDE.Editor.MethodPlacement;

// Methodenrümpfe in Deklarationsreihenfolge (#660) im Editor. Ordnen und
// Einfügestelle rechnet der Server (atlas.server.methodOrder), Argumente,
// Antwort und die eine Änderung Atlas.Core.Editor.MethodPlacement; hier
// bleiben Puffer, Zeitgeber, Vorschau und Schreiben.
// - Neue Rümpfe: Nach jeder Änderung wartet ein Zeitgeber, bis der Editor
//   400 ms ruht, und vergleicht den Puffer mit dem letzten Stand. Ist ein
//   Methodenkopf dazugekommen (Strg+Umschalt+C der IDE, Atlas-Aktionen wie
//   „Methode anlegen“), fragt Atlas den Server, wohin der Rumpf gehört.
//   Steht er falsch, nimmt Atlas den letzten Schritt zurück und schreibt
//   Vervollständigung und Verschieben als einen Schritt: Ein Strg+Z stellt
//   den Stand davor her. Lässt sich der Schritt nicht sauber zurücknehmen
//   (mehrere Schritte, andere Änderungen dazwischen), wird nur verschoben,
//   als eigener Schritt. Die Schreibmarke wandert im Rumpf mit.
// - Befehl „implementation wie Klasse ordnen“ (Menü Atlas, Palette,
//   Kontextmenü): Vorschau mit Richtung und Abstand je Methode („↑ 3“) und
//   den stehen bleibenden („bleibt: in einer Region“), dann ein
//   Rückgängig-Schritt und ein Eintrag in den Atlas-Änderungen.
// - editor.methodPlacement = off oder Atlas aus: kein Verschieben, der Befehl
//   meldet, dass er abgeschaltet ist.
// Gesichert über TAtlasFeature.MethodPlacement (#493). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.ExtCtrls,
  ToolsAPI,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Editor.MethodPlacement;

type
  TAtlasMethodPlacementSessionFunc = reference to function: TLspSession;

  TAtlasIdeMethodPlacement = class
  private const
    /// <summary>Kurze Antwort beim Einfügen; das Ordnen der Unit darf länger dauern.</summary>
    PlaceTimeoutMs = 3000;
    ArrangeTimeoutMs = 15000;
  private class var
    FInstance: TAtlasIdeMethodPlacement;
  private
    FSession: TAtlasMethodPlacementSessionFunc;
    FMessage: TProc<string>;
    FPolicy: TFunc<TAtlasUnopenedPolicy>;
    FTimer: TTimer;
    // Letzter Stand der aktiven Datei, gegen den neue Rümpfe zählen.
    FFileName: string;
    FText: string;
    FWriting: Boolean;
    procedure TimerTick(Sender: TObject);
    procedure Snapshot;
    procedure Place(const AView: IOTAEditView; const ABefore, AAfter: string);
    procedure Arrange;
    procedure Report(const AText: string);
    function CurrentSession: TLspSession;
    class function Mode: string; static;
    class function Texts: TAtlasMethodPlacementTexts; static;
    class procedure WriteBuffer(const ABuffer: IOTAEditBuffer; const AText, ANewText: string); static;
  public
    constructor Create(const ASession: TAtlasMethodPlacementSessionFunc; const AMessage: TProc<string>;
      const APolicy: TFunc<TAtlasUnopenedPolicy>);
    destructor Destroy; override;
    /// <summary>ASession liefert die laufende Sitzung (nil ohne), AMessage schreibt eine Zeile in die
    /// Meldungsansicht, APolicy sagt, wie der Befehl nicht geöffnete Dateien behandelt.</summary>
    class procedure Install(const ASession: TAtlasMethodPlacementSessionFunc; const AMessage: TProc<string>;
      const APolicy: TFunc<TAtlasUnopenedPolicy>); static;
    class procedure Uninstall; static;
    /// <summary>editor.methodPlacement nicht off und Atlas an?</summary>
    class function Enabled: Boolean; static;
    /// <summary>„implementation wie Klasse ordnen“ (Befehl Atlas.MethodOrder).</summary>
    class procedure Run; static;
    /// <summary>Ansicht gewechselt: neuer Ausgangsstand beim nächsten Takt.</summary>
    class procedure Dismiss; static;
    /// <summary>Aus EditorViewModified: Zeitgeber neu starten.</summary>
    class procedure EditorModified; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Results.Model,
  Atlas.UI.Strings,
  Atlas.UI.Results.Frame,
  Atlas.UI.Results.RenamePreview,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Editor.WorkspaceEdit;

function IsPascal(const AFileName: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(AFileName));
  Result := (Ext = '.pas') or (Ext = '.dpr') or (Ext = '.dpk') or (Ext = '.inc');
end;

/// <summary>Aktive Ansicht einer Pascal-Datei; nil ohne.</summary>
function PascalView: IOTAEditView;
begin
  Result := TAtlasEditorBuffer.ActiveView;
  if (Result <> nil) and ((Result.Buffer = nil) or not IsPascal(Result.Buffer.FileName)) then
    Result := nil;
end;

{ TAtlasIdeMethodPlacement }

constructor TAtlasIdeMethodPlacement.Create(const ASession: TAtlasMethodPlacementSessionFunc;
  const AMessage: TProc<string>; const APolicy: TFunc<TAtlasUnopenedPolicy>);
begin
  inherited Create;
  FSession := ASession;
  FMessage := AMessage;
  FPolicy := APolicy;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := TAtlasMethodPlacement.DelayMs;
  FTimer.OnTimer := TimerTick;
  Snapshot;
end;

destructor TAtlasIdeMethodPlacement.Destroy;
begin
  FreeAndNil(FTimer);
  FFileName := '';
  FText := '';
  inherited;
end;

class procedure TAtlasIdeMethodPlacement.Install(const ASession: TAtlasMethodPlacementSessionFunc;
  const AMessage: TProc<string>; const APolicy: TFunc<TAtlasUnopenedPolicy>);
begin
  if FInstance = nil then
    FInstance := TAtlasIdeMethodPlacement.Create(ASession, AMessage, APolicy);
end;

class procedure TAtlasIdeMethodPlacement.Uninstall;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeMethodPlacement.Enabled: Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := Settings.Enabled and not SameText(Settings.MethodPlacement, 'off');
end;

class function TAtlasIdeMethodPlacement.Mode: string;
begin
  Result := TAtlasIdeSettings.Current.MethodPlacement;
end;

class function TAtlasIdeMethodPlacement.Texts: TAtlasMethodPlacementTexts;
begin
  Result := Default(TAtlasMethodPlacementTexts);
  Result.Up := TAtlasStrings.Text(TAtlasTextId.MethodOrderUp);
  Result.Down := TAtlasStrings.Text(TAtlasTextId.MethodOrderDown);
  Result.Stays := TAtlasStrings.Text(TAtlasTextId.MethodOrderStays);
  Result.Region := TAtlasStrings.Text(TAtlasTextId.MethodOrderRegion);
  Result.Conditional := TAtlasStrings.Text(TAtlasTextId.MethodOrderConditional);
  Result.SharedLine := TAtlasStrings.Text(TAtlasTextId.MethodOrderSharedLine);
end;

class procedure TAtlasIdeMethodPlacement.Run;
begin
  if FInstance = nil then
    Exit;
  if not Enabled then
  begin
    FInstance.Report(TAtlasStrings.Text(TAtlasTextId.MethodOrderOff));
    Exit;
  end;
  FInstance.Arrange;
end;

class procedure TAtlasIdeMethodPlacement.Dismiss;
begin
  // Die neue Ansicht steht erst nach dem Wechsel fest: Der nächste Takt nimmt ihren Stand.
  if FInstance <> nil then
  begin
    FInstance.FFileName := '';
    FInstance.FText := '';
    FInstance.FTimer.Enabled := False;
    FInstance.FTimer.Enabled := True;
  end;
end;

class procedure TAtlasIdeMethodPlacement.EditorModified;
begin
  if (FInstance = nil) or FInstance.FWriting or not Enabled then
    Exit;
  FInstance.FTimer.Enabled := False;
  FInstance.FTimer.Enabled := True;
end;

procedure TAtlasIdeMethodPlacement.Report(const AText: string);
begin
  if Assigned(FMessage) then
    FMessage(AText);
end;

function TAtlasIdeMethodPlacement.CurrentSession: TLspSession;
begin
  Result := nil;
  if Assigned(FSession) then
    Result := FSession();
end;

procedure TAtlasIdeMethodPlacement.Snapshot;
var
  View: IOTAEditView;
begin
  FFileName := '';
  FText := '';
  View := PascalView;
  if View = nil then
    Exit;
  FFileName := View.Buffer.FileName;
  FText := TAtlasEditorBuffer.Text(View.Buffer);
end;

class procedure TAtlasIdeMethodPlacement.WriteBuffer(const ABuffer: IOTAEditBuffer; const AText, ANewText: string);
var
  Range: TLspTextRange;
  Writer: IOTAEditWriter;
begin
  if not TAtlasMethodPlacement.Difference(AText, ANewText, Range) then
    Exit;
  // Ein Schreiber = ein Rückgängig-Schritt.
  Writer := ABuffer.CreateUndoableWriter;
  Writer.CopyTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, Range.StartOffset)));
  Writer.DeleteTo(TEncoding.UTF8.GetByteCount(Copy(AText, 1, Range.EndOffset)));
  if Range.NewText <> '' then
    Writer.Insert(PAnsiChar(UTF8Encode(Range.NewText)));
  Writer := nil;
  TAtlasEditorSnapshots.Invalidate(ABuffer.FileName);
end;

procedure TAtlasIdeMethodPlacement.TimerTick(Sender: TObject);
begin
  FTimer.Enabled := False;
  TAtlasGuard.Run(TAtlasFeature.MethodPlacement,
    procedure
    var
      View: IOTAEditView;
      Text, Before: string;
    begin
      if not Enabled then
        Exit;
      View := PascalView;
      if View = nil then
        Exit;
      Text := TAtlasEditorBuffer.Text(View.Buffer);
      Before := FText;
      // Andere Datei als beim letzten Stand: erst der neue Ausgangsstand.
      if SameText(View.Buffer.FileName, FFileName) and TAtlasMethodPlacement.NewHeaders(Before, Text) then
        Place(View, Before, Text);
      Snapshot;
    end);
end;

procedure TAtlasIdeMethodPlacement.Place(const AView: IOTAEditView; const ABefore, AAfter: string);
var
  Session: TLspSession;
  Buffer: IOTAEditBuffer;
  FileName, Final: string;
  Answer: TJSONValue;
  Reply: TAtlasMethodPlacementReply;
  Caret: TOTAEditPos;
  Line: Integer;
begin
  Session := CurrentSession;
  if Session = nil then
    Exit;
  Buffer := AView.Buffer;
  FileName := Buffer.FileName;
  try
    Session.Sync(FileName, AAfter);
    Answer := Session.RunCommand(TAtlasMethodPlacement.Command,
      TAtlasMethodPlacement.Arguments(TLspSession.PathToUri(FileName), Mode, False, ABefore), PlaceTimeoutMs);
    try
      TAtlasMethodPlacement.Read(Answer, Reply);
    finally
      Answer.Free;
    end;
  except
    // Ohne Antwort bleibt der Rumpf, wo die IDE ihn hingesetzt hat.
    on ELspClientError do
    begin
      TAtlasGuard.Log('Methodenreihenfolge: keine Antwort des Servers');
      Exit;
    end;
  end;
  if (Reply.Edits = nil) or (Reply.Moved = 0) then
    Exit;
  Final := TLspEdits.Apply(AAfter, Reply.Edits);
  Caret := AView.CursorPos;
  FWriting := True;
  try
    // Ein Schritt mit der Vervollständigung, wenn sich genau sie zurücknehmen lässt.
    if Buffer.Undo and (TAtlasEditorBuffer.Text(Buffer) = ABefore) then
      WriteBuffer(Buffer, ABefore, Final)
    else
    begin
      if TAtlasEditorBuffer.Text(Buffer) <> AAfter then
        Buffer.Redo;
      // Lässt sich der Stand nicht wiederherstellen, lieber nichts ändern.
      if TAtlasEditorBuffer.Text(Buffer) <> AAfter then
        Exit;
      WriteBuffer(Buffer, AAfter, Final);
    end;
    if TAtlasMethodPlacement.CaretLine(Reply.Moves, Caret.Line - 1, Line) then
    begin
      Caret.Line := Line + 1;
      AView.CursorPos := Caret;
      AView.MoveViewToCursor;
    end;
    AView.Paint;
  finally
    FWriting := False;
  end;
end;

procedure TAtlasIdeMethodPlacement.Arrange;
var
  View: IOTAEditView;
  Session: TLspSession;
  FileName, Text, Hint: string;
  Answer: TJSONValue;
  Reply: TAtlasMethodPlacementReply;
  Move: TAtlasMethodMove;
  Preview: TArray<TAtlasResultEntry>;
  Entry: TAtlasResultEntry;
  Edit: TLspWorkspaceEdit;
  Files: TLspFileEdits;
  Outcome: TAtlasWorkspaceEditResult;
  Open: TAtlasResultsOpen;
begin
  View := PascalView;
  if View = nil then
    Exit;
  Session := CurrentSession;
  if Session = nil then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MenuIndexNoServer));
    Exit;
  end;
  FileName := View.Buffer.FileName;
  Text := TAtlasEditorBuffer.Text(View.Buffer);
  try
    Session.Sync(FileName, Text);
    Answer := Session.RunCommand(TAtlasMethodPlacement.Command,
      TAtlasMethodPlacement.Arguments(TLspSession.PathToUri(FileName), Mode, True, ''), ArrangeTimeoutMs);
    try
      TAtlasMethodPlacement.Read(Answer, Reply);
    finally
      Answer.Free;
    end;
  except
    on E: ELspClientError do
    begin
      Report(TAtlasStrings.Fmt(TAtlasTextId.MethodOrderFailed, [E.Message]));
      Exit;
    end;
  end;
  if (Reply.Edits = nil) or (Reply.Moved = 0) then
  begin
    Report(TAtlasStrings.Text(TAtlasTextId.MethodOrderNothing));
    Exit;
  end;
  Preview := nil;
  for Move in Reply.Moves do
  begin
    Entry := TAtlasResultEntry.Create(FileName, Move.Line, 0);
    Entry.Text := TAtlasMethodPlacement.MoveText(Move, Texts);
    Preview := Preview + [Entry];
  end;
  Hint := TAtlasStrings.Fmt(TAtlasTextId.MethodOrderHint, [Reply.Moved, Length(Reply.Moves) - Reply.Moved]);
  Open :=
    procedure(const AFileName: string; ALine, ACharacter: Integer)
    begin
      TAtlasIdeNavigation.GoToLocation(AFileName, ALine, ACharacter);
    end;
  if not TAtlasRenamePreview.Execute(TAtlasStrings.Text(TAtlasTextId.MethodOrderTitle), Hint,
    TAtlasStrings.Text(TAtlasTextId.MethodOrderApply), TAtlasResults.Group(Preview), Open) then
    Exit;
  Files := Default(TLspFileEdits);
  Files.FileName := FileName;
  Files.Edits := Reply.Edits;
  Edit := Default(TLspWorkspaceEdit);
  Edit.Files := [Files];
  FWriting := True;
  try
    Outcome := TAtlasIdeWorkspaceEdit.Apply(Edit, FPolicy(), TAtlasStrings.Text(TAtlasTextId.MethodOrderTitle));
  finally
    FWriting := False;
  end;
  Snapshot;
  if Outcome.Error <> '' then
  begin
    Report(TAtlasStrings.Fmt(TAtlasTextId.EditFailed, [Outcome.Error]));
    Exit;
  end;
  Report(TAtlasStrings.Fmt(TAtlasTextId.MethodOrderDone, [Reply.Moved]));
end;

end.
